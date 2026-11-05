//
//  TrackPlayerRecovery.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 22/05/26.
//

import AVFoundation
import Foundation
import Network

extension TrackPlayerCore {

  // MARK: - Failed-item recovery

  /// Recreates a current AVPlayerItem that reached `status == .failed`.
  /// A failed item cannot be revived, so we build a fresh one from the same
  /// track URL, seek back to the last known position and resume if intended.
  /// The stall watchdog also uses it for an item whose connection went silent; it passes
  /// `countsAgainstRetryBudget: false` because it keeps its own budget.
  /// Must be called on `playerQueue`.
  func recoverFailedItem(_ item: AVPlayerItem, countsAgainstRetryBudget: Bool = true) {
    guard let player else { return }
    guard player.currentItem === item else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Failed item is not the current item — ignoring")
      return
    }
    guard let trackId = item.trackId, let track = findTrackById(trackId) else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Failed item has no recoverable track — stopping")
      isRecoveringFromStall = false
      // Nothing left to recover — playback is not happening; drop the intent so a
      // later network restore doesn't try to resume a track we can't rebuild.
      intendedToPlay = false
      notifyPlaybackStateChange(.stopped, .error)
      return
    }

    let attempts = (failedItemRetryCounts[trackId] ?? 0) + 1
    if countsAgainstRetryBudget {
      guard attempts <= Constants.maxFailedItemRetries else {
        NitroPlayerLogger.log("TrackPlayerCore",
          "❌ '\(track.title)' failed \(attempts - 1)x — giving up")
        failedItemRetryCounts.removeValue(forKey: trackId)
        isRecoveringFromStall = false
        // Don't silently resurrect a track the user already saw fail: clear the play
        // intent so a later network-restore path doesn't auto-resume it.
        intendedToPlay = false
        notifyPlaybackStateChange(.stopped, .error)
        return
      }
      failedItemRetryCounts[trackId] = attempts
    }

    // Resume from the furthest-known position: the failed item's own playhead is
    // usually more current than the last periodic boundary-observer tick.
    let itemTime = item.currentTime().seconds
    let resumePosition = (itemTime.isFinite && itemTime > lastKnownPosition) ? itemTime : lastKnownPosition
    // Keep lastKnownPosition aligned so a re-failure during recovery resumes here too.
    lastKnownPosition = resumePosition

    let budget = countsAgainstRetryBudget
      ? "attempt \(attempts)/\(Constants.maxFailedItemRetries)" : "stall watchdog"
    NitroPlayerLogger.log("TrackPlayerCore",
      "🔁 Recreating item '\(track.title)' (\(budget), resume @ \(Int(resumePosition))s)")

    // The failure may be a stale/expired streaming URL. Ask the JS layer for a fresh
    // one; if it arrives before the retry fires, updateTracks replaces the item
    // directly and the retry below aborts on the currentItem identity check.
    notifyTracksNeedUpdate(tracks: [track], lookahead: lookaheadCount)

    // A preloaded asset for this track shares the same dead connection state.
    preloadedAssets.removeValue(forKey: trackId)?.cancelLoading()
    // Surface a buffering state while the retry is pending.
    isRecoveringFromStall = true
    emitStateChange()

    playerQueue.asyncAfter(deadline: .now() + Constants.failedItemRetryDelay) { [weak self] in
      guard let self, let player = self.player else { return }
      // Bail if the user moved to a different track — or updateTracks already
      // swapped in a fresh-URL item — while we waited.
      guard player.currentItem === item else {
        NitroPlayerLogger.log("TrackPlayerCore", "⏭️ Current item changed before retry — aborting recovery")
        return
      }
      // A Cast session took over while we waited: the local player stays silent.
      if self.isCasting {
        NitroPlayerLogger.log("TrackPlayerCore", "⏭️ Casting started before retry — aborting recovery")
        self.isRecoveringFromStall = false
        return
      }
      // A stalled item (the stall watchdog's case, not a failed one) may have resumed on its
      // own while we waited; recreating it now would cut off audio that is playing.
      if item.status != .failed && player.timeControlStatus == .playing {
        NitroPlayerLogger.log("TrackPlayerCore", "⏭️ Playback resumed before retry — aborting recovery")
        return
      }
      // Re-resolve the track so we pick up any URL refreshed during the wait.
      guard let track = self.findTrackById(trackId),
        let newItem = self.createGaplessPlayerItem(for: track, isPreload: false)
      else {
        NitroPlayerLogger.log("TrackPlayerCore", "❌ Could not rebuild item for track '\(trackId)'")
        self.isRecoveringFromStall = false
        self.intendedToPlay = false
        self.notifyPlaybackStateChange(.stopped, .error)
        return
      }
      // Mark the imminent currentItem change as an in-place recovery so the
      // resulting currentItemDidChange does not emit a spurious onChangeTrack
      // or reset per-track state (resume position, retry budget).
      self.suppressTrackChangeEmit = true
      player.replaceCurrentItem(with: newItem)

      if resumePosition > 1 { self.seekWhenReady(newItem, to: resumePosition) }
      if self.intendedToPlay {
        player.playImmediately(atRate: Float(self.currentPlaybackSpeed))
      }
    }
  }

  // MARK: - Failed-player recovery

  /// Replaces a failed player after a short delay; false once the budget since playback last ran is spent.
  /// Must be called on `playerQueue`.
  func scheduleFailedPlayerReplacement() -> Bool {
    guard !isCasting, failedPlayerReplacements < Constants.maxFailedItemRetries else { return false }
    failedPlayerReplacements += 1
    isRecoveringFromStall = true
    emitStateChange()
    playerQueue.asyncAfter(deadline: .now() + Constants.failedItemRetryDelay) { [weak self] in
      self?.replaceFailedPlayer()
    }
    return true
  }

  /// An AVPlayer that fails never recovers; the system media server crashing fails every player
  /// in the process. Builds a new player and, with `restoringQueue`, the same track and position
  /// and the rest of the queue. Must be called on `playerQueue`.
  func replaceFailedPlayer(restoringQueue: Bool = true) {
    guard let old = player, old.status == .failed, !isCasting else { return }
    // A failed player drops its items, so fall back to the track the core considers current
    let currentId = old.currentItem?.trackId ?? getCurrentTrack()?.id
    let itemTime = old.currentItem?.currentTime().seconds ?? .nan
    let resumePosition = (itemTime.isFinite && itemTime > lastKnownPosition) ? itemTime : lastKnownPosition
    NitroPlayerLogger.log("TrackPlayerCore",
      "♻️ Replacing the failed player (attempt \(failedPlayerReplacements)/\(Constants.maxFailedItemRetries)), track \(currentId ?? "none"), resume @ \(Int(resumePosition))s")

    if let observer = boundaryTimeObserver {
      old.removeTimeObserver(observer)
      boundaryTimeObserver = nil
    }
    currentItemObservers.removeAll()
    detachMetadataOutput()
    for keyPath in Self.observedPlayerKeyPaths { old.removeObserver(self, forKeyPath: keyPath) }
    old.removeAllItems()
    // Assets loaded through the dead media server are unusable as well
    for asset in preloadedAssets.values { asset.cancelLoading() }
    preloadedAssets.removeAll()
    preloadGeneration += 1

    let player = makeQueuePlayer()
    // setVolume only ever sets the player, so the new one takes it over
    player.volume = old.volume
    self.player = player
    for keyPath in Self.observedPlayerKeyPaths {
      player.addObserver(self, forKeyPath: keyPath, options: [.new], context: nil)
    }
    guard restoringQueue else {
      // The caller builds a new queue, so there is nothing left to recover
      isRecoveringFromStall = false
      return
    }
    guard let currentId, let track = findTrackById(currentId),
      let item = createGaplessPlayerItem(for: track, isPreload: true)
    else {
      NitroPlayerLogger.log("TrackPlayerCore", "♻️ Nothing to resume on the new player")
      isRecoveringFromStall = false
      return
    }
    // Same track as before, so the item change must not look like a track change
    suppressTrackChangeEmit = true
    player.insert(item, after: nil)
    rebuildAVQueueFromCurrentPosition()
    if resumePosition > 1 { seekWhenReady(item, to: resumePosition) }
    if intendedToPlay {
      activateAudioSessionIfNeeded()
      player.playImmediately(atRate: Float(currentPlaybackSpeed))
    }
  }

  /// Playback the user starts gets a working player even after the automatic replacements ran out;
  /// callers about to build a new queue pass `restoringQueue: false`
  func replacePlayerIfFailed(restoringQueue: Bool) {
    guard player?.status == .failed else { return }
    failedPlayerReplacements = 0
    replaceFailedPlayer(restoringQueue: restoringQueue)
  }

  /// Seeks `item` once it is ready to play (see seekInternal); a later request replaces this one
  func seekWhenReady(_ item: AVPlayerItem, to position: Double) {
    pendingSeekItem = item
    pendingSeekPosition = position
    lastKnownPosition = position
  }

  /// The seek waiting for `item`, if any; call once the item is ready
  func takePendingSeek(for item: AVPlayerItem) -> Double? {
    guard let pending = pendingSeekItem, pending === item else { return nil }
    pendingSeekItem = nil
    return pendingSeekPosition
  }

  /// Where `item` is, counting a seek that still waits for it as done
  func reportedPosition(of item: AVPlayerItem) -> Double {
    pendingSeekItem === item ? pendingSeekPosition : item.currentTime().seconds
  }

  // MARK: - Network path monitoring

  /// Starts watching the network path. VPN toggles and Wi-Fi band switches
  /// produce a path update we use to recover a player left stuck by the change.
  func startNetworkMonitoring() {
    guard pathMonitor == nil else { return }
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      // Handler is delivered on `playerQueue` (passed to start(queue:)).
      guard let self else { return }
      let previous = self.lastPathStatus
      self.lastPathStatus = path.status
      NitroPlayerLogger.log("TrackPlayerCore",
        "🌐 Network path update — status: \(path.status) (was: \(previous))")
      // React only to a real down→up transition. A satisfied→satisfied update
      // (e.g. Wi-Fi↔cellular handoff) is not an outage recovery.
      if previous != .satisfied && path.status == .satisfied {
        self.handleNetworkRestored()
      }
    }
    monitor.start(queue: playerQueue)
    pathMonitor = monitor
    NitroPlayerLogger.log("TrackPlayerCore", "🌐 Network monitoring started")
  }

  /// Called on `playerQueue` on a genuine down→up network transition.
  /// Heavily guarded so it is a no-op during healthy playback and never fights an
  /// intentional pause (user pause, audio-session interruption, route loss).
  func handleNetworkRestored() {
    // `intendedToPlay` alone is not enough: an audio interruption pauses playback
    // while leaving the intent set. Never resume into an active interruption.
    guard intendedToPlay, !isInterrupted, let player, let currentItem = player.currentItem else { return }

    // The connection died completely — the item is dead, recreate it.
    if currentItem.status == .failed {
      NitroPlayerLogger.log("TrackPlayerCore", "🌐 Network restored — recreating failed item")
      // A genuine outage→restore earns the current track one fresh retry budget
      // (only this track's count — not a blanket reset, which would let a flapping
      // network defeat `maxFailedItemRetries`).
      if let tid = currentItem.trackId { failedItemRetryCounts.removeValue(forKey: tid) }
      recoverFailedItem(currentItem)
      return
    }

    // The item survived but playback stalled — nudge it back to life.
    if player.timeControlStatus != .playing {
      NitroPlayerLogger.log("TrackPlayerCore", "🌐 Network restored — resuming stalled playback")
      isRecoveringFromStall = true
      player.playImmediately(atRate: Float(currentPlaybackSpeed))
    }
  }

  // MARK: - Audio session handling

  func setupAudioSessionObservers() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleAudioRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleMediaServicesReset(_:)),
      name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
  }

  /// The system media server restarted: the session lost its setup, and the player fails
  /// (status KVO), which replaceFailedPlayer handles.
  @objc func handleMediaServicesReset(_ notification: Notification) {
    NitroPlayerLogger.log("TrackPlayerCore", "♻️ Media services were reset")
    playerQueue.async { [weak self] in self?.resetAudioSession() }
  }

  /// Phone calls, Siri, other apps, etc. interrupt the audio session. When the
  /// interruption ends the session may be inactive — reactivate it and resume.
  @objc func handleAudioSessionInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    switch type {
    case .began:
      NitroPlayerLogger.log("TrackPlayerCore", "🔇 Audio session interruption began")
      // The system has paused playback. Flag the interruption so network/stall
      // recovery does not fight it by resuming mid-interruption.
      playerQueue.async { [weak self] in self?.isInterrupted = true }
    case .ended:
      let options: AVAudioSession.InterruptionOptions =
        (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { .init(rawValue: $0) } ?? []
      let shouldResume = options.contains(.shouldResume)
      NitroPlayerLogger.log("TrackPlayerCore",
        "🔊 Audio session interruption ended (shouldResume: \(shouldResume))")
      playerQueue.async { [weak self] in
        guard let self else { return }
        self.isInterrupted = false
        do {
          try AVAudioSession.sharedInstance().setActive(true)
        } catch {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Failed to reactivate audio session — \(error)")
        }
        if shouldResume && self.intendedToPlay {
          self.player?.playImmediately(atRate: Float(self.currentPlaybackSpeed))
        } else if !shouldResume {
          // System says do not resume — treat playback as no longer intended so
          // recovery won't silently restart it. The user must press play again.
          self.intendedToPlay = false
        }
      }
    @unknown default:
      break
    }
  }

  /// Pauses when the current output device disappears (e.g. headphones unplugged),
  /// matching standard iOS playback behaviour.
  @objc func handleAudioRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
      let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

    NitroPlayerLogger.log("TrackPlayerCore", "🎧 Audio route changed — reason: \(reason.rawValue)")
    if reason == .oldDeviceUnavailable {
      playerQueue.async { [weak self] in self?.pauseInternal() }
    }
  }
}
