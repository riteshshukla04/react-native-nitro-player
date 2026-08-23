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
    // Once the first item is ready (readyToPlay), this is flipped to false for
    // gapless inter-track transitions (see setupCurrentItemObservers).
    player?.automaticallyWaitsToMinimizeStalling = true

    // Set action at item end to advance for gapless playback
    player?.actionAtItemEnd = .advance

    // Configure for high-quality audio playback with minimal latency
    if #available(iOS 15.0, *) {
      player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🎵 Gapless playback configured - automaticallyWaitsToMinimizeStalling=true (flipped to false on first readyToPlay)")

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

    // 1. TRACK repeat — handle FIRST, before any temp-track removal
    if currentRepeatMode == .track {
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
      self.notifySeek(position, duration)
      self.isManuallySeeked = true
      self.handleBoundaryTimeCrossed()
    }
  }

  /// Fires when playback stalls because media did not arrive in time (buffer underrun).
  /// AVQueuePlayer runs with `automaticallyWaitsToMinimizeStalling = false` during playback
  /// (see `setupCurrentItemObservers`) so it will NOT resume on its own — we mark a recovery
  /// flag and re-issue play() once `isPlaybackLikelyToKeepUp` flips back to true.
  @objc func playerItemPlaybackStalled(_ notification: Notification) {
    playerQueue.async { [weak self] in
      guard let self, let player = self.player, let currentItem = player.currentItem else { return }
      guard (notification.object as? AVPlayerItem) === currentItem else { return }
      // A stall only matters if we actually want playback ongoing. If the user has
      // paused (or a stall notification is racing a pause), do NOT arm the recovery
      // flag — the `isPlaybackLikelyToKeepUp` observer fires only on change, so a flag
      // set here while paused could never be cleared and would wedge state on .buffering.
      guard self.intendedToPlay else { return }
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
      }
      self.emitStateChange()
    }
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
      // Fresh failure-retry budget for the new track.
      failedItemRetryCounts.removeAll()
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
      }
      return
    }

    let isRepeatLoop =
      currentRepeatMode == .track && currentItem.trackId != nil
      && currentItem.trackId == lastCurrentItemTrackId
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

    // Update track index and determine temporary type
    if let trackId = currentItem.trackId {
      NitroPlayerLogger.log("TrackPlayerCore", "🔍 Looking up trackId '\(trackId)' in currentTracks...")
      NitroPlayerLogger.log("TrackPlayerCore", "   Current index BEFORE lookup: \(currentTrackIndex)")

      currentTemporaryType = determineCurrentTemporaryType()
      NitroPlayerLogger.log("TrackPlayerCore", "   🎯 Track type: \(currentTemporaryType)")

      if currentTemporaryType != .none {
        var tempTrack: TrackItem?
        if currentTemporaryType == .playNext { tempTrack = playNextStack.first(where: { $0.id == trackId }) }
        else if currentTemporaryType == .upNext { tempTrack = upNextQueue.first(where: { $0.id == trackId }) }
        if let track = tempTrack {
          if isRecoveryReplace || isRepeatLoop {
            NitroPlayerLogger.log("TrackPlayerCore",
              "   ♻️ Same-track transition for '\(track.title)' — suppressing onChangeTrack")
          } else {
            NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Temporary track: \(track.title) - \(track.artist)")
            NitroPlayerLogger.log("TrackPlayerCore", "   📢 Emitting onChangeTrack for temporary track")
            notifyTrackChange(track, .skip)
          }
        }
      } else if let index = currentTracks.firstIndex(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Found track at index: \(index)")
        NitroPlayerLogger.log("TrackPlayerCore", "   Setting currentTrackIndex from \(currentTrackIndex) to \(index)")

        let oldIndex = currentTrackIndex
        currentTrackIndex = index

        if let track = currentTracks[safe: index] {
          NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Track: \(track.title) - \(track.artist)")
          if oldIndex != index {
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
          // First item is buffered and ready — disable stall waiting for gapless inter-track transitions
          self?.player?.automaticallyWaitsToMinimizeStalling = false
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
        // Recover from a stall: AVPlayer will NOT auto-resume because
        // automaticallyWaitsToMinimizeStalling is false — re-issue play() ourselves.
        if self.isRecoveringFromStall {
          self.isRecoveringFromStall = false
          if self.intendedToPlay && player.timeControlStatus != .playing {
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
