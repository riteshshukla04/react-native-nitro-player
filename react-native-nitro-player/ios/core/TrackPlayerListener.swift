//
//  TrackPlayerListener.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation
import Foundation

extension TrackPlayerCore {

  func setupPlayer() {
    // Must be called on playerQueue
    player = AVQueuePlayer()

    // Start with stall-waiting enabled so the first track buffers before playing.
    // Once playback actually starts (timeControlStatus == .playing), this is flipped
    // to false for gapless inter-track transitions (see observeValue).
    player?.automaticallyWaitsToMinimizeStalling = true

    // Set action at item end to advance for gapless playback
    player?.actionAtItemEnd = .advance

    // Configure for high-quality audio playback with minimal latency
    if #available(iOS 15.0, *) {
      player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🎵 Gapless playback configured - automaticallyWaitsToMinimizeStalling=true (flipped to false once playback starts)")

    // Listen for EQ enabled/disabled changes so we can update ALL items in
    // the queue atomically, keeping the audio pipeline configuration uniform.
    // A mismatch (some items with tap, some without) forces AVQueuePlayer to
    // reconfigure the pipeline at transition boundaries → audible gap.
    EqualizerCore.shared.addOnEnabledChangeListener { [weak self] enabled in
      self?.playerQueue.async {
        guard let self, let player = self.player else { return }
        for item in player.items() {
          if enabled {
            EqualizerCore.shared.applyAudioMix(to: item)
          } else {
            item.audioMix = nil
          }
        }
        NitroPlayerLogger.log("TrackPlayerCore",
          "🎛️ EQ toggled \(enabled ? "ON" : "OFF") — updated \(player.items().count) items for pipeline consistency")
      }
    }

    setupPlayerObservers()
    setupAudioSessionObservers()
    startNetworkMonitoring()
  }

  func setupPlayerObservers() {
    guard let player else { return }

    player.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
    player.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
    player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)
    player.addObserver(self, forKeyPath: "currentItem", options: [.new], context: nil)

    NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidPlayToEndTime(_:)),
      name: .AVPlayerItemDidPlayToEndTime, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime(_:)),
      name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemNewErrorLogEntry(_:)),
      name: .AVPlayerItemNewErrorLogEntry, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemTimeJumped(_:)),
      name: .AVPlayerItemTimeJumped, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemPlaybackStalled(_:)),
      name: .AVPlayerItemPlaybackStalled, object: nil)
  }

  func setupBoundaryTimeObserver() {
    if let obs = boundaryTimeObserver, let p = player {
      p.removeTimeObserver(obs)
      boundaryTimeObserver = nil
    }

    guard let player, let currentItem = player.currentItem,
      currentItem.status == .readyToPlay else { return }

    let duration = currentItem.duration.seconds
    let interval: Double
    if duration > 0 && !duration.isNaN && !duration.isInfinite {
      if duration > Constants.twoHoursInSeconds { interval = Constants.boundaryIntervalLong }
      else if duration > Constants.oneHourInSeconds { interval = Constants.boundaryIntervalMedium }
      else { interval = Constants.boundaryIntervalDefault }
    } else {
      interval = Constants.boundaryIntervalDefault
    }

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Setting up periodic observer (interval: \(interval)s, duration: \(duration)s)")

    let cmInterval = CMTime(seconds: interval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    // Deliver on playerQueue (not main)
    boundaryTimeObserver = player.addPeriodicTimeObserver(
      forInterval: cmInterval, queue: playerQueue
    ) { [weak self] _ in
      self?.handleBoundaryTimeCrossed()
    }

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Periodic time observer setup complete")
  }

  func handleBoundaryTimeCrossed() {
    guard let player, let currentItem = player.currentItem else { return }
    guard player.rate > 0 else { return }

    // Self-heal stall recovery. A late stall notification processed after playback has
    // already resumed re-arms recovery with no further `.playing` transition to clear it,
    // which would leave stall waiting on (no gapless) for the rest of the session. Time is
    // advancing here, so playback is real.
    if player.timeControlStatus == .playing,
      isRecoveringFromStall || player.automaticallyWaitsToMinimizeStalling {
      clearStallRecovery()
      emitStateChange()
    }

    let position = currentItem.currentTime().seconds
    let rawDuration = currentItem.duration.seconds
    let duration = (rawDuration > 0 && !rawDuration.isNaN && !rawDuration.isInfinite) ? rawDuration : 0.0

    // Remember the position so we can resume here if the item has to be recreated.
    if position.isFinite && position >= 0 { lastKnownPosition = position }

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Boundary crossed - position: \(Int(position))s / duration: \(duration)s")

    notifyPlaybackProgress(position, duration, isManuallySeeked ? true : nil)
    isManuallySeeked = false

    // Only do remaining-time preload when duration is known
    if duration > 0 {
      let remaining = duration - position
      if remaining > 0 && remaining <= Constants.preferredForwardBufferDuration && !didRequestUrlsForCurrentItem {
        didRequestUrlsForCurrentItem = true
        NitroPlayerLogger.log("TrackPlayerCore",
          "⏳ \(Int(remaining))s remaining — proactively checking upcoming URLs")
        checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      }
    }
  }

  // MARK: - KVO — fires on main or internal thread, dispatch to playerQueue
  override func observeValue(
    forKeyPath keyPath: String?, of object: Any?,
    change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
  ) {
    playerQueue.async { [weak self] in
      guard let self, let player = self.player else { return }
      NitroPlayerLogger.log("TrackPlayerCore", "👀 KVO - keyPath: \(keyPath ?? "nil")")
      if keyPath == "status" {
        NitroPlayerLogger.log("TrackPlayerCore", "👀 Player status changed to: \(player.status.rawValue)")
        if player.status == .readyToPlay { self.emitStateChange() }
        else if player.status == .failed {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Player failed")
          self.notifyPlaybackStateChange(.stopped, .error)
        }
      } else if keyPath == "rate" {
        NitroPlayerLogger.log("TrackPlayerCore", "👀 Rate changed to: \(player.rate)")
        self.emitStateChange()
      } else if keyPath == "timeControlStatus" {
        NitroPlayerLogger.log("TrackPlayerCore", "👀 TimeControlStatus changed to: \(player.timeControlStatus.rawValue)")
        if player.timeControlStatus == .playing {
          // Audio is actually flowing, so the buffer has real data in it. Only now is it
          // safe to disable stall waiting for gapless inter-track transitions — doing it
          // at readyToPlay (header parsed, nothing buffered) starts playback on an empty
          // buffer, which stalls immediately.
          self.clearStallRecovery()
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
          self.intendedToPlay, !self.isCasting, let item = player.currentItem {
          // Waiting with stall waiting on (preroll, or after a stall) posts no stall
          // notification, so watch for a silent connection from here as well.
          self.armStallWatchdog(for: item)
        }
        self.emitStateChange()
      } else if keyPath == "currentItem" {
        NitroPlayerLogger.log("TrackPlayerCore", "👀 Current item changed")
        self.currentItemDidChange()
      }
    }
  }

  // MARK: - Notifications — fire on arbitrary thread, dispatch to playerQueue
  @objc func playerItemDidPlayToEndTime(_ notification: Notification) {
    playerQueue.async { [weak self] in self?.playerItemDidPlayToEndTimeInternal(notification) }
  }

  func playerItemDidPlayToEndTimeInternal(_ notification: Notification) {
    NitroPlayerLogger.log("TrackPlayerCore", "\n🏁 Track finished playing")
    guard let finishedItem = notification.object as? AVPlayerItem else { return }
    // Items without our trackId belong to another AVPlayer in the host app
    guard finishedItem.trackId != nil else { return }

    // A track removed from the playlist is finishing: it must play once, never loop.
    let finishedWasRemoved =
      finishedItem.trackId.map { id in !currentTracks.contains { $0.id == id } } ?? false

    // 1. TRACK repeat — handle FIRST, before any temp-track removal
    if currentRepeatMode == .track && !finishedWasRemoved {
      if player?.currentItem == nil || player?.currentItem === finishedItem {
        NitroPlayerLogger.log("TrackPlayerCore", "🔁 TRACK repeat — no queued copy, seeking to zero")
        player?.seek(to: .zero)
        player?.rate = Float(currentPlaybackSpeed)
      }
      return  // do not remove temp tracks, do not notify track change (same track looping)
    }

    // 2. Remove finished temp track from its list
    if let trackId = finishedItem.trackId {
      if let index = playNextStack.firstIndex(where: { $0.id == trackId }) {
        let track = playNextStack.remove(at: index)
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished playNext track: \(track.title) - removed from stack")
        notifyTemporaryQueueChange()
      } else if let index = upNextQueue.firstIndex(where: { $0.id == trackId }) {
        let track = upNextQueue.remove(at: index)
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished upNext track: \(track.title) - removed from queue")
        notifyTemporaryQueueChange()
      } else if let track = currentTracks.first(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished original track: \(track.title)")
      }
    }

    // 3. Normal advance via actionAtItemEnd = .advance
    if let player = player {
      NitroPlayerLogger.log("TrackPlayerCore", "📋 Remaining items in queue: \(player.items().count)")
    }
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  @objc func playerItemFailedToPlayToEndTime(_ notification: Notification) {
    guard (notification.object as? AVPlayerItem)?.trackId != nil else { return }
    guard let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
    else { return }
    playerQueue.async { [weak self] in
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Playback failed - \(error)")
      self?.notifyPlaybackStateChange(.stopped, .error)
    }
  }

  @objc func playerItemNewErrorLogEntry(_ notification: Notification) {
    guard let item = notification.object as? AVPlayerItem, item.trackId != nil,
      let errorLog = item.errorLog() else { return }
    for event in errorLog.events ?? [] {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Error log - \(event.errorComment ?? "Unknown error") - Code: \(event.errorStatusCode)")
    }
    if let error = item.error {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Item error - \(error.localizedDescription)")
    }
  }

  @objc func playerItemTimeJumped(_ notification: Notification) {
    playerQueue.async { [weak self] in
      guard let self, let player = self.player, let currentItem = player.currentItem else { return }
      guard (notification.object as? AVPlayerItem) === currentItem else { return }
      let position = currentItem.currentTime().seconds
      let duration = currentItem.duration.seconds
      NitroPlayerLogger.log("TrackPlayerCore", "🎯 Time jumped (seek detected) - position: \(Int(position))s")
      // Every seek lands here, including while waiting with time frozen (when the periodic
      // observer doesn't update it), so a stall recovery resumes at the seek target rather
      // than rewinding or jumping back to where the user seeked from.
      if position.isFinite && position >= 0 { self.lastKnownPosition = position }
      self.notifySeek(position, duration)
      self.isManuallySeeked = true
      self.handleBoundaryTimeCrossed()
    }
  }

  /// Fires when playback stalls because media did not arrive in time (buffer underrun).
  /// AVQueuePlayer runs with `automaticallyWaitsToMinimizeStalling = false` during playback
  /// (see the `timeControlStatus` KVO) so it will NOT resume on its own. We re-enable stall
  /// waiting and request playback, so AVPlayer resumes once the buffer is likely to keep up
  /// OR is full — the latter matters when throughput is below the bitrate (hi-res FLAC on
  /// cellular), where `isPlaybackLikelyToKeepUp` may never become true.
  @objc func playerItemPlaybackStalled(_ notification: Notification) {
    playerQueue.async { [weak self] in
      guard let self, let player = self.player, let currentItem = player.currentItem else { return }
      guard (notification.object as? AVPlayerItem) === currentItem else { return }
      // A stall only matters if we actually want playback ongoing. If the user has
      // paused (or a stall notification is racing a pause), do NOT arm the recovery
      // flag — the `isPlaybackLikelyToKeepUp` observer fires only on change, so a flag
      // set here while paused could never be cleared and would wedge state on .buffering.
      // Never resume into an active audio-session interruption either, nor restart the
      // local player while a Cast device is playing (casting pauses it but keeps the intent).
      guard self.intendedToPlay, !self.isInterrupted, !self.isCasting else { return }
      // Deliberately not gated on `timeControlStatus`: the notification and the status
      // change are separate events, so the status may still read `.playing` here for a
      // real stall. If a late notification re-arms recovery while already playing, the
      // periodic time observer (handleBoundaryTimeCrossed, every 1–5 s on playerQueue)
      // clears it on its next tick.
      self.isRecoveringFromStall = true
      // The buffer may have already refilled before this notification was
      // processed. `isPlaybackLikelyToKeepUp` fires only on change, so its
      // observer would not fire again — resume here instead of waiting forever.
      if currentItem.isPlaybackLikelyToKeepUp,
        self.intendedToPlay, player.timeControlStatus != .playing {
        NitroPlayerLogger.log("TrackPlayerCore",
          "⚠️ Playback stalled but buffer already refilled — resuming now")
        self.isRecoveringFromStall = false
        player.playImmediately(atRate: Float(self.currentPlaybackSpeed))
      } else {
        NitroPlayerLogger.log("TrackPlayerCore",
          "⚠️ Playback stalled (buffer underrun) — will auto-resume once the buffer refills")
        // AVPlayer drops the rate to 0 on a stall and, while paused, stops loading once its
        // buffer is full. Without stall waiting nothing would ever restart it if
        // `isPlaybackLikelyToKeepUp` stays false, so let AVPlayer wait and resume itself.
        player.automaticallyWaitsToMinimizeStalling = true
        player.rate = Float(self.currentPlaybackSpeed)
        NitroPlayerLogger.log("TrackPlayerCore",
          "⏳ Stall waiting re-enabled — timeControlStatus: \(player.timeControlStatus.rawValue)")
        self.armStallWatchdog(for: currentItem)
      }
      self.emitStateChange()
    }
  }

  /// Clears stall-recovery state once playback is actually flowing: disables stall waiting
  /// for gapless inter-track transitions and drops the recovery flag. Must be called on
  /// `playerQueue`.
  func clearStallRecovery() {
    player?.automaticallyWaitsToMinimizeStalling = false
    isRecoveringFromStall = false
    stallWatchdogRecoveries = 0
  }

  /// Watches an item that should be playing but is waiting on data (after a stall, or while
  /// prerolling with stall waiting on). If no media arrives for a whole `stallWatchdogDelay`
  /// window — the connection went silent without an error — recreate it on a fresh connection
  /// via `recoverFailedItem`, which resumes at the last position. A slow but progressing
  /// download just re-arms, so it is never thrown away. After `maxFailedItemRetries`
  /// recreations without playback resuming, playback stops with an error. Must be called on
  /// `playerQueue`.
  func armStallWatchdog(for item: AVPlayerItem) {
    stallWatchdog?.cancel()
    let bufferedAtArm = bufferedRanges(of: item)
    let watchdog = DispatchWorkItem { [weak self] in
      guard let self, let player = self.player,
        self.intendedToPlay, !self.isInterrupted, !self.isCasting,
        player.currentItem === item, player.timeControlStatus != .playing,
        // A failed item is already being recreated by its status observer.
        item.status != .failed
      else { return }
      let buffered = self.bufferedRanges(of: item)
      // Media arrived (the loaded ranges moved), or none has arrived yet: a slow first byte,
      // such as a server starting a transcode, is not a silent connection, and the request
      // fails on its own if the server never answers.
      if buffered != bufferedAtArm || buffered.isEmpty {
        self.armStallWatchdog(for: item)
        return
      }
      guard self.stallWatchdogRecoveries < Constants.maxFailedItemRetries else {
        NitroPlayerLogger.log("TrackPlayerCore",
          "❌ No buffer progress after \(self.stallWatchdogRecoveries) recreations — giving up")
        self.stallWatchdogRecoveries = 0
        self.isRecoveringFromStall = false
        self.intendedToPlay = false
        // The item hasn't failed, so stop it from starting later if media does arrive. Queue
        // the error after the pause's own KVO state emits so `.stopped` is the final state.
        player.pause()
        self.playerQueue.async { [weak self] in self?.notifyPlaybackStateChange(.stopped, .error) }
        return
      }
      self.stallWatchdogRecoveries += 1
      NitroPlayerLogger.log("TrackPlayerCore",
        "⏱️ No buffer progress for \(Int(Constants.stallWatchdogDelay))s — recreating item")
      self.recoverFailedItem(item, countsAgainstRetryBudget: false)
    }
    stallWatchdog = watchdog
    playerQueue.asyncAfter(deadline: .now() + Constants.stallWatchdogDelay, execute: watchdog)
  }

  /// Loaded time ranges as start/end seconds; they change whenever media arrives.
  private func bufferedRanges(of item: AVPlayerItem) -> [Double] {
    item.loadedTimeRanges
      .flatMap { value -> [Double] in
        let range = value.timeRangeValue
        return [range.start.seconds, CMTimeRangeGetEnd(range).seconds]
      }
      .filter { $0.isFinite }
  }

  func currentItemDidChange() {
    // Clear old item observers
    currentItemObservers.removeAll()

    // Reset proactive URL check debounce for the new track
    didRequestUrlsForCurrentItem = false

    // A recovery replace (recoverFailedItem) swaps the current item in place for the
    // SAME track. It must not look like a track change: don't emit onChangeTrack and
    // don't reset per-track state that recovery still depends on.
    let isRecoveryReplace = suppressTrackChangeEmit
    suppressTrackChangeEmit = false

    if !isRecoveryReplace {
      // Genuine new track — reset per-track state.
      // Resume position is per-track; recovery captured what it needs before the swap.
      lastKnownPosition = 0
      // A new track is not a stall recovery — drop any stale flag from the old item.
      isRecoveringFromStall = false
      // Fresh failure-retry and stall-watchdog budgets for the new track.
      failedItemRetryCounts.removeAll()
      stallWatchdogRecoveries = 0
    }

    guard let player, let currentItem = player.currentItem else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Current item changed to nil")
      detachMetadataOutput()
      lastCurrentItemTrackId = nil
      // Queue exhausted — handle PLAYLIST repeat
      if currentRepeatMode == .playlist && !currentTracks.isEmpty, let player = self.player {
        NitroPlayerLogger.log("TrackPlayerCore", "🔁 PLAYLIST repeat — rebuilding original queue and restarting")
        playNextStack.removeAll()
        upNextQueue.removeAll()
        currentTemporaryType = .none

        let windowed = currentTracks.prefix(1 + Constants.queueWindowSize)
        let allItems = windowed.compactMap { createGaplessPlayerItem(for: $0, isPreload: false) }
        var lastItem: AVPlayerItem? = nil
        for item in allItems {
          player.insert(item, after: lastItem)
          lastItem = item
        }
        currentTrackIndex = 0
        player.rate = Float(currentPlaybackSpeed)

        if let firstTrack = currentTracks.first {
          notifyTrackChange(firstTrack, .repeat)
        }
        notifyTemporaryQueueChange()
      } else if let player = self.player, player.items().isEmpty, !hasUpcomingTrack() {
        // AVQueuePlayer leaves `rate` at 1 with no item left, so state would keep reading as
        // playing after the last track ends. Stop for real and tell JS.
        player.rate = 0
        intendedToPlay = false
        emitStateChange(reason: .end)
      }
      return
    }

    let isRepeatLoop =
      currentRepeatMode == .track && currentItem.trackId != nil
      && currentItem.trackId == lastCurrentItemTrackId
    let previousItemTrackId = lastCurrentItemTrackId
    lastCurrentItemTrackId = currentItem.trackId

    #if DEBUG
    NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "▶", count: Constants.separatorLineLength))
    NitroPlayerLogger.log("TrackPlayerCore", "🔄 CURRENT ITEM CHANGED")
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "▶", count: Constants.separatorLineLength))

    if let trackId = currentItem.trackId,
      let track = currentTracks.first(where: { $0.id == trackId })
    {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️  NOW PLAYING: \(track.title) - \(track.artist) (ID: \(track.id))")
    } else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️  NOW PLAYING: Unknown track (trackId: \(currentItem.trackId ?? "nil"))")
    }

    let remainingItems = player.items()
    NitroPlayerLogger.log("TrackPlayerCore", "\n📋 REMAINING ITEMS IN QUEUE: \(remainingItems.count)")
    for (index, item) in remainingItems.enumerated() {
      if let trackId = item.trackId, let track = currentTracks.first(where: { $0.id == trackId }) {
        let marker = item == currentItem ? "▶️" : "  "
        NitroPlayerLogger.log("TrackPlayerCore", "\(marker) [\(index + 1)] \(track.title) - \(track.artist)")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   [\(index + 1)] ⚠️ Unknown track")
      }
    }

    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "▶", count: Constants.separatorLineLength) + "\n")
    #endif

    NitroPlayerLogger.log("TrackPlayerCore", "📱 Item status: \(currentItem.status.rawValue)")

    if let error = currentItem.error {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Current item has error - \(error.localizedDescription)")
    }

    // Setup KVO observers for current item
    setupCurrentItemObservers(item: currentItem)

    // An item that takes over while the player is already waiting (a recovery replace, a
    // skip while buffering) produces no new `.waitingToPlayAtSpecifiedRate` KVO edge, and the
    // previous item's watchdog no longer applies, so watch the new item from here.
    if intendedToPlay, !isCasting, player.timeControlStatus != .playing {
      armStallWatchdog(for: currentItem)
    }

    // A Cast disconnect rebuilds around the receiver's track; none of those transitions is a change.
    let isBackendTransfer = backendTransferTargetId != nil
    if let target = backendTransferTargetId, currentItem.trackId == target {
      backendTransferTargetId = nil
    }

    // Update track index and determine temporary type
    if let trackId = currentItem.trackId {
      NitroPlayerLogger.log("TrackPlayerCore", "🔍 Looking up trackId '\(trackId)' in currentTracks...")
      NitroPlayerLogger.log("TrackPlayerCore", "   Current index BEFORE lookup: \(currentTrackIndex)")

      let previousTemporaryType = currentTemporaryType
      currentTemporaryType = determineCurrentTemporaryType()
      NitroPlayerLogger.log("TrackPlayerCore", "   🎯 Track type: \(currentTemporaryType)")

      // A repeated track resolves to the copy playback reached, not its first one. An item
      // that already matches the index (a jump, a replace, a repeat loop) keeps it; moving on
      // through the queue, including onto a back-to-back copy, searches past it.
      let matchesIndex = currentTracks[safe: currentTrackIndex]?.id == trackId
      let ontoNextCopy = currentTracks[safe: currentTrackIndex + 1]?.id == trackId
        && !(isRecoveryReplace || isRepeatLoop || isBackendTransfer)
        && (previousItemTrackId == trackId || previousTemporaryType != .none)
      let indexHint = matchesIndex && !ontoNextCopy ? currentTrackIndex : currentTrackIndex + 1

      if currentTemporaryType != .none {
        var tempTrack: TrackItem?
        if currentTemporaryType == .playNext { tempTrack = playNextStack.first(where: { $0.id == trackId }) }
        else if currentTemporaryType == .upNext { tempTrack = upNextQueue.first(where: { $0.id == trackId }) }
        if let track = tempTrack {
          if isRecoveryReplace || isRepeatLoop || isBackendTransfer {
            NitroPlayerLogger.log("TrackPlayerCore",
              "   ♻️ Same-track transition for '\(track.title)' — suppressing onChangeTrack")
          } else {
            NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Temporary track: \(track.title) - \(track.artist)")
            NitroPlayerLogger.log("TrackPlayerCore", "   📢 Emitting onChangeTrack for temporary track")
            notifyTrackChange(track, .skip)
          }
        }
      } else if let index = currentTrackIndexOf(trackId, from: indexHint) {
        NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Found track at index: \(index)")
        NitroPlayerLogger.log("TrackPlayerCore", "   Setting currentTrackIndex from \(currentTrackIndex) to \(index)")

        let oldIndex = currentTrackIndex
        currentTrackIndex = index

        if let track = currentTracks[safe: index] {
          NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Track: \(track.title) - \(track.artist)")
          if oldIndex != index && !isBackendTransfer {
            NitroPlayerLogger.log("TrackPlayerCore", "   📢 Emitting onChangeTrack (index changed from \(oldIndex) to \(index))")
            let wrappedToStart =
              currentRepeatMode == .playlist && index == 0 && oldIndex == currentTracks.count - 1
            notifyTrackChange(track, wrappedToStart ? .repeat : .skip)
          } else {
            NitroPlayerLogger.log("TrackPlayerCore", "   ⏭️ Skipping onChangeTrack emission (index unchanged)")
          }
        }
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   ⚠️ Track ID '\(trackId)' NOT FOUND in currentTracks!")
        #if DEBUG
        NitroPlayerLogger.log("TrackPlayerCore", "   Current tracks:")
        for (idx, track) in currentTracks.enumerated() {
          NitroPlayerLogger.log("TrackPlayerCore", "      [\(idx)] \(track.id) - \(track.title)")
        }
        #endif
      }
    }

    // Setup boundary observers when item is ready
    if currentItem.status == .readyToPlay {
      setupBoundaryTimeObserver()
    }

    // Top up the windowed AVQueuePlayer — the item we just consumed freed a slot.
    // Only when it is actually short: rebuildAVQueueFromCurrentPosition can fall into
    // rebuildQueueFromPlaylistIndex (current track no longer in the playlist), which
    // replaces the current item and re-enters this callback. The length check makes any
    // such re-entry a no-op and terminate.
    if currentRepeatMode == .track || player.items().count - 1 < Constants.queueWindowSize {
      rebuildAVQueueFromCurrentPosition()
    }

    // Preload upcoming tracks for gapless playback
    preloadUpcomingTracks(from: currentTrackIndex + 1)
    cleanupPreloadedAssets(keepingFrom: currentTrackIndex)
  }

  /// Attaches an `AVPlayerItemMetadataOutput` to the current item so ICY/ID3
  /// metadata emitted mid-stream reaches JS. Detaches from the previous item first —
  /// an output may only be attached to one item at a time.
  func attachMetadataOutput(to item: AVPlayerItem) {
    detachMetadataOutput()
    let output = AVPlayerItemMetadataOutput(identifiers: nil)
    output.setDelegate(self, queue: playerQueue)
    item.add(output)
    metadataOutput = output
    metadataOutputItem = item
  }

  /// Clears the metadata output so a detached one can no longer pass the identity
  /// check in the delegate and emit metadata for an item that is no longer playing.
  func detachMetadataOutput() {
    if let output = metadataOutput, let item = metadataOutputItem {
      item.remove(output)
    }
    metadataOutput = nil
    metadataOutputItem = nil
  }

  func setupCurrentItemObservers(item: AVPlayerItem) {
    NitroPlayerLogger.log("TrackPlayerCore", "📱 Setting up item observers")

    attachMetadataOutput(to: item)

    let statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      self?.playerQueue.async {
        if item.status == .readyToPlay {
          NitroPlayerLogger.log("TrackPlayerCore", "✅ Item ready, setting up boundaries")
          // Note: the failure-retry budget is intentionally NOT cleared here. Reaching
          // .readyToPlay momentarily must not refund retries — otherwise an item that
          // flaps ready↔failed would bypass `maxFailedItemRetries`. The budget is reset
          // only on a genuine track change (currentItemDidChange) or a real network
          // restore (handleNetworkRestored).
          self?.setupBoundaryTimeObserver()
          // Update now playing info now that duration is available (captured on playerQueue)
          self?.refreshMediaSession()
        } else if item.status == .failed {
          NitroPlayerLogger.log("TrackPlayerCore",
            "❌ Item failed — \(item.error?.localizedDescription ?? "unknown error")")
          self?.recoverFailedItem(item)
        }
      }
    }
    currentItemObservers.append(statusObserver)

    let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
      guard item.isPlaybackBufferEmpty else { return }
      // KVO fires on an arbitrary thread — emitStateChange reads playerQueue-owned
      // state (currentTracks, temp queues, isRecoveringFromStall), so hop first.
      self?.playerQueue.async {
        guard let self, self.player?.currentItem === item else { return }
        NitroPlayerLogger.log("TrackPlayerCore", "⏸️ Buffer empty (buffering)")
        self.emitStateChange()
      }
    }
    currentItemObservers.append(bufferEmptyObserver)

    let bufferKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
      guard item.isPlaybackLikelyToKeepUp else { return }
      self?.playerQueue.async {
        guard let self, let player = self.player else { return }
        guard player.currentItem === item else { return }
        NitroPlayerLogger.log("TrackPlayerCore", "▶️ Buffer likely to keep up")
        // Recover from a stall. The stall handler re-enabled stall waiting, so AVPlayer would
        // resume by itself; play() now just skips its remaining wait. Never while casting:
        // the local player stays silent then.
        if self.isRecoveringFromStall {
          self.isRecoveringFromStall = false
          if self.intendedToPlay && !self.isCasting && player.timeControlStatus != .playing {
            NitroPlayerLogger.log("TrackPlayerCore", "🔁 Buffer refilled — resuming playback after stall")
            player.playImmediately(atRate: Float(self.currentPlaybackSpeed))
          }
        }
        self.emitStateChange()
      }
    }
    currentItemObservers.append(bufferKeepUpObserver)
  }

  func handleTimedMetadataGroups(_ groups: [AVTimedMetadataGroup]) {
    var title: String?
    var artist: String?
    var album: String?
    var url: String?
    var artworkUrl: String?

    for group in groups {
      for item in group.items {
        guard let value = item.stringValue, !value.isEmpty else { continue }
        switch item.commonKey {
        case .some(.commonKeyTitle): title = value
        case .some(.commonKeyArtist): artist = value
        case .some(.commonKeyAlbumName): album = value
        case .some(.commonKeyArtwork): artworkUrl = value
        default:
          // ICY/Shoutcast streams carry no common keys — match on the identifier.
          // StreamUrl is where radio providers put the current track's artwork.
          switch item.identifier {
          case .some(.icyMetadataStreamTitle): title = value
          case .some(.icyMetadataStreamURL): url = value
          case .some(.id3MetadataOfficialAudioSourceWebpage),
               .some(.id3MetadataOfficialAudioFileWebpage):
            if url == nil { url = value }
          default: break
          }
        }
      }
    }

    (artist, title) = splitStreamTitle(artist: artist, title: title)

    guard title != nil || artist != nil || album != nil || url != nil || artworkUrl != nil else { return }
    NitroPlayerLogger.log("TrackPlayerCore", "🏷️ Timed metadata - \(title ?? "-") / \(artist ?? "-")")
    notifyTimedMetadata(
      TimedMetadata(title: title, artist: artist, album: album, url: url, artworkUrl: artworkUrl))
  }

  /// ICY streams pack both fields into one `"Artist - Title"` string. Split it when
  /// the stream gave no separate artist, leaving an explicit artist untouched.
  func splitStreamTitle(artist: String?, title: String?) -> (String?, String?) {
    guard artist == nil, let title, let separator = title.range(of: " - ") else {
      return (artist, title)
    }
    let left = String(title[title.startIndex..<separator.lowerBound])
    let right = String(title[separator.upperBound...])
    guard !left.isEmpty, !right.isEmpty else { return (artist, title) }
    return (left, right)
  }

  func emitStateChange(reason: Reason? = nil) {
    guard let player else { return }
    let state: TrackPlayerState
    if player.timeControlStatus == .playing {
      state = .playing
    } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
      state = .buffering
    } else if isRecoveringFromStall {
      // Stalled with automaticallyWaitsToMinimizeStalling == false: timeControlStatus
      // reads .paused, but we are buffering, not user-paused — report it as such.
      state = .buffering
    } else if player.rate == 0 {
      state = .paused
    } else {
      state = .stopped
    }
    NitroPlayerLogger.log("TrackPlayerCore", "🔔 Emitting state change: \(state)")
    notifyPlaybackStateChange(state, reason)
  }
}

extension TrackPlayerCore: AVPlayerItemMetadataOutputPushDelegate {
  // Delivered on playerQueue (set in attachMetadataOutput)
  func metadataOutput(
    _ output: AVPlayerItemMetadataOutput,
    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
    from track: AVPlayerItemTrack?
  ) {
    // A detached output can still flush metadata it had already buffered — ignore it,
    // it belongs to an item that is no longer current.
    guard output === metadataOutput else { return }
    handleTimedMetadataGroups(groups)
  }
}
