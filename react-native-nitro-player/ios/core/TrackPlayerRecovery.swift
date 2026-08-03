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
  /// Must be called on `playerQueue`.
  func recoverFailedItem(_ item: AVPlayerItem) {
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

    // Resume from the furthest-known position: the failed item's own playhead is
    // usually more current than the last periodic boundary-observer tick.
    let itemTime = item.currentTime().seconds
    let resumePosition = (itemTime.isFinite && itemTime > lastKnownPosition) ? itemTime : lastKnownPosition
    // Keep lastKnownPosition aligned so a re-failure during recovery resumes here too.
    lastKnownPosition = resumePosition

    NitroPlayerLogger.log("TrackPlayerCore",
      "🔁 Recreating failed item '\(track.title)' "
        + "(attempt \(attempts)/\(Constants.maxFailedItemRetries), resume @ \(Int(resumePosition))s)")

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

      if resumePosition > 1 {
        let time = CMTime(seconds: resumePosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time)
      }
      if self.intendedToPlay {
        player.playImmediately(atRate: Float(self.currentPlaybackSpeed))
      }
    }
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
