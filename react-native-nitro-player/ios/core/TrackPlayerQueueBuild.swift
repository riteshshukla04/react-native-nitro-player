//
//  TrackPlayerQueueBuild.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation

import Foundation

extension TrackPlayerCore {

  /// Cancels an item's outstanding asset loading before it is released.
  ///
  /// `AVURLAsset.dealloc` blocks the deallocating thread inside `URLAssetFinalize`
  /// until any in-flight `loadValuesAsynchronously` / resource-loader work finishes —
  /// and AVPlayer tears removed items down on the MAIN thread. Dropping items without
  /// cancelling first therefore stalls the main run loop (and with it RCTTiming, so
  /// JS timers stop firing) for as long as the pending loads take.
  /// `cancelLoading()` itself waits for in-flight work to unwind, so it is only worth
  /// paying on a full teardown (playlist switch / jump), never on the incremental
  /// window rebuild that runs on every playNext / addToUpNext.
  ///
  /// A cancelled asset must never be handed back out: `createGaplessPlayerItem` reuses
  /// `preloadedAssets`, and reusing a cancelled one yields an item that fails and then
  /// burns the failed-item retry budget. Evict it instead.
  func cancelLoading(of item: AVPlayerItem) {
    guard let asset = item.asset as? AVURLAsset else { return }
    if let trackId = item.trackId, preloadedAssets[trackId] === asset {
      preloadedAssets.removeValue(forKey: trackId)
    }
    asset.cancelLoading()
  }

  /// Removes every item from the player, cancelling their asset loads first.
  func removeAllItemsCancellingLoads(_ player: AVQueuePlayer) {
    for item in player.items() { cancelLoading(of: item) }
    player.removeAllItems()
  }

  func updatePlayerQueue(tracks: [TrackItem]) {
    // While casting, mirror the new queue to the Cast device instead of building
    // the local AVQueuePlayer (which would start local audio).
    if isCasting {
      currentTracks = tracks
      currentTrackIndex = 0
      if let first = tracks.first { emitCastTrackChange(first) }
      loadCastQueue(autoplay: intendedToPlay, position: 0)
      return
    }

    NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "=", count: Constants.separatorLineLength))
    NitroPlayerLogger.log("TrackPlayerCore", "📋 UPDATE PLAYER QUEUE - Received \(tracks.count) tracks")
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength))

    #if DEBUG
    for (index, track) in tracks.enumerated() {
      let isDownloaded = DownloadManagerCore.shared.isTrackDownloaded(trackId: track.id)
      let downloadStatus = isDownloaded ? "📥 DOWNLOADED" : "🌐 REMOTE"
      NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] 🎵 \(track.title) - \(track.artist) (ID: \(track.id)) - \(downloadStatus)")
      if isDownloaded {
        if let localPath = DownloadManagerCore.shared.getLocalPath(trackId: track.id) {
          NitroPlayerLogger.log("TrackPlayerCore", "      Local path: \(localPath)")
        }
      }
    }
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength) + "\n")
    #endif

    // Store tracks for index tracking
    currentTracks = tracks
    currentTrackIndex = 0
    NitroPlayerLogger.log("TrackPlayerCore", "🔢 Reset currentTrackIndex to 0 (will be updated by KVO observer)")

    // Remove old boundary observer if exists
    if let boundaryObserver = boundaryTimeObserver, let currentPlayer = player {
      currentPlayer.removeTimeObserver(boundaryObserver)
      boundaryTimeObserver = nil
    }

    // Re-enable stall waiting for the new first track
    player?.automaticallyWaitsToMinimizeStalling = true

    // Clear old preloaded assets when loading new queue
    for asset in preloadedAssets.values { asset.cancelLoading() }
    preloadedAssets.removeAll()
    preloadGeneration += 1

    guard let existingPlayer = self.player else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player available")
      return
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🔄 Removing \(existingPlayer.items().count) old items from player")
    removeAllItemsCancellingLoads(existingPlayer)

    // Lazy-load mode if the first track needs a URL. Tracks further in the queue with
    // empty URLs are dropped safely by compactMap below and resolved via onTracksNeedUpdate.
    let isLazyLoad = tracks.first.map {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    } ?? false
    if isLazyLoad {
      NitroPlayerLogger.log("TrackPlayerCore", "⏳ Lazy-load mode — player cleared, awaiting URL resolution")
      return
    }

    // Only materialize a window of items — the rest are added as playback advances.
    let windowed = tracks.prefix(1 + Constants.queueWindowSize)
    let items = windowed.enumerated().compactMap { (index, track) -> AVPlayerItem? in
      let isPreload = index < Constants.gaplessPreloadCount
      return createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🎵 Created \(items.count) gapless-optimized player items")

    guard !items.isEmpty else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No valid items to play")
      return
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🔄 Adding \(items.count) new items to player")

    var lastItem: AVPlayerItem? = nil
    for (index, item) in items.enumerated() {
      existingPlayer.insert(item, after: lastItem)
      lastItem = item

      #if DEBUG
      if let trackId = item.trackId, let track = tracks.first(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "  ➕ Added to player queue [\(index + 1)]: \(track.title)")
      }
      #endif
    }

    #if DEBUG
    let trackById = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    NitroPlayerLogger.log("TrackPlayerCore", "\n🔍 VERIFICATION - Player now has \(existingPlayer.items().count) items:")
    for (index, item) in existingPlayer.items().enumerated() {
      if let trackId = item.trackId, let track = trackById[trackId] {
        NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] ✓ \(track.title) - \(track.artist) (ID: \(track.id))")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] ⚠️ Unknown item (no trackId)")
      }
    }
    if let currentItem = existingPlayer.currentItem,
      let trackId = currentItem.trackId,
      let track = trackById[trackId]
    {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️  Current item: \(track.title)")
    }
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength) + "\n")
    #endif

    // Notify track change
    if let firstTrack = tracks.first {
      NitroPlayerLogger.log("TrackPlayerCore", "🎵 Emitting track change: \(firstTrack.title)")
      notifyTrackChange(firstTrack, nil)
    }

    // Start preloading upcoming tracks for gapless playback
    preloadUpcomingTracks(from: 1)

    NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue updated with \(items.count) gapless-optimized tracks")
  }

  /// Clears temporary tracks, rebuilds AVQueuePlayer from `index` in the original playlist,
  /// and resumes playback only if the player was already playing (preserves paused state).
  @discardableResult
  func rebuildQueueFromPlaylistIndex(index: Int) -> Bool {
    guard index >= 0 && index < self.currentTracks.count else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ rebuildQueueFromPlaylistIndex - invalid index \(index), currentTracks.count = \(self.currentTracks.count)")
      return false
    }

    NitroPlayerLogger.log("TrackPlayerCore", "\n🎯 REBUILD QUEUE FROM PLAYLIST INDEX \(index)")
    NitroPlayerLogger.log("TrackPlayerCore", "   Total tracks in playlist: \(self.currentTracks.count)")
    NitroPlayerLogger.log("TrackPlayerCore", "   Current index: \(self.currentTrackIndex), target index: \(index)")

    // While casting, jump on the Cast device instead of rebuilding the local queue.
    if isCasting {
      self.playNextStack.removeAll()
      self.upNextQueue.removeAll()
      self.currentTemporaryType = .none
      self.currentTrackIndex = index
      if let track = self.getCurrentTrack() { self.emitCastTrackChange(track) }
      self.loadCastQueue(autoplay: self.intendedToPlay, position: 0)
      return true
    }

    // Preserve playback state — only resume if already playing.
    let wasPlaying = self.player?.rate ?? 0 > 0

    // Clear temporary tracks when jumping to specific index
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

    let fullPlaylist = self.currentTracks

    // Update currentTrackIndex BEFORE updating queue
    self.currentTrackIndex = index

    // Lazy-load guard: if the target track has no URL AND is not downloaded locally,
    // the queue can't be built. Defer to updateTracks once URL resolution completes.
    let targetTrack = fullPlaylist[index]
    let isLazyLoad = targetTrack.url.isEmpty
      && !DownloadManagerCore.shared.isTrackDownloaded(trackId: targetTrack.id)
    if isLazyLoad {
      NitroPlayerLogger.log("TrackPlayerCore", "   ⏳ Lazy-load — deferring AVQueuePlayer setup; emitting track change for index \(index)")
      // Clear old items immediately so the previous track stops while waiting for the URL to resolve
      if let boundaryObserver = self.boundaryTimeObserver {
        player?.removeTimeObserver(boundaryObserver)
        self.boundaryTimeObserver = nil
      }
      if let p = player { removeAllItemsCancellingLoads(p) }
      self.currentTracks = fullPlaylist
      if let track = self.currentTracks[safe: index] {
        notifyTrackChange(track, .skip)
      }
      return true
    }

    let windowEnd = min(index + 1 + Constants.queueWindowSize, fullPlaylist.count)
    let tracksToPlay = Array(fullPlaylist[index..<windowEnd])
    NitroPlayerLogger.log("TrackPlayerCore", "   🔄 Creating gapless queue with \(tracksToPlay.count) tracks starting from index \(index)")

    let items = tracksToPlay.enumerated().compactMap { (offset, track) -> AVPlayerItem? in
      let isPreload = offset < Constants.gaplessPreloadCount
      return self.createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    guard let player = self.player, !items.isEmpty else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player or no items to play")
      return false
    }

    // Remove old boundary observer
    if let boundaryObserver = self.boundaryTimeObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryTimeObserver = nil
    }

    // Re-enable stall waiting for the new first track
    player.automaticallyWaitsToMinimizeStalling = true

    removeAllItemsCancellingLoads(player)
    var lastItem: AVPlayerItem? = nil
    for item in items {
      player.insert(item, after: lastItem)
      lastItem = item
    }

    // Restore the full playlist reference (don't slice it!)
    self.currentTracks = fullPlaylist

    NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Gapless queue recreated. Now at index: \(self.currentTrackIndex)")
    if let track = self.getCurrentTrack() {
      NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Playing: \(track.title)")
      notifyTrackChange(track, .skip)
    }

    self.preloadUpcomingTracks(from: index + 1)

    if wasPlaying { player.rate = Float(currentPlaybackSpeed) }
    return true
  }

  /// Rebuilds the AVQueuePlayer from the current position with temporary tracks.
  /// Order: [current] + [playNext stack] + [upNext queue] + [remaining original]
  ///
  /// - Parameter changedTrackIds: When non-nil, performs a surgical update:
  ///   only AVPlayerItems whose track ID is in this set are removed and re-created.
  func rebuildAVQueueFromCurrentPosition(changedTrackIds: Set<String>? = nil) {
    // While casting, queue changes are applied to the receiver — the local AVQueuePlayer is dormant.
    if isCasting {
      syncCastQueueAfterCurrent()
      return
    }

    guard let player = self.player else { return }

    let currentItem = player.currentItem

    guard let playingTrackId = currentItem?.trackId else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No current item or track ID found during queue rebuild")
      return
    }

    let playingItems = player.items()

    // If the currently playing AVPlayerItem is no longer in currentTracks,
    // delegate to rebuildQueueFromPlaylistIndex so the player immediately
    // starts what is now at currentTrackIndex in the updated list.
    if !currentTracks.contains(where: { $0.id == playingTrackId }) &&
      currentTemporaryType == .none {
      let targetIndex = currentTrackIndex < currentTracks.count
        ? currentTrackIndex : currentTracks.count - 1
      if targetIndex >= 0 {
        _ = rebuildQueueFromPlaylistIndex(index: targetIndex)
      }
      return
    }

    // Sync currentTrackIndex to the track's actual position after a playlist mutation
    // (e.g. reorder). Without this, the remaining-tracks slice uses the stale index,
    // causing wrong tracks to play after skip/next.
    if currentTemporaryType == .none,
      let newIndex = currentTracks.firstIndex(where: { $0.id == playingTrackId }) {
      currentTrackIndex = newIndex
    }

    // Build the desired upcoming track list
    var newQueueTracks: [TrackItem] = []
    let currentId = currentItem?.trackId

    // PlayNext stack: skip the currently playing track by ID (not position)
    if currentTemporaryType == .playNext, let currentId = currentId {
      var skipped = false
      for track in playNextStack {
        if !skipped && track.id == currentId { skipped = true; continue }
        newQueueTracks.append(track)
      }
    } else if currentTemporaryType != .playNext {
      newQueueTracks.append(contentsOf: playNextStack)
    }

    // UpNext queue: skip the currently playing track by ID (not position)
    if currentTemporaryType == .upNext, let currentId = currentId {
      var skipped = false
      for track in upNextQueue {
        if !skipped && track.id == currentId { skipped = true; continue }
        newQueueTracks.append(track)
      }
    } else if currentTemporaryType != .upNext {
      newQueueTracks.append(contentsOf: upNextQueue)
    }

    if currentTrackIndex + 1 < currentTracks.count {
      newQueueTracks.append(contentsOf: currentTracks[(currentTrackIndex + 1)...])
    }

    if currentRepeatMode == .playlist, currentTrackIndex > 0, currentTrackIndex <= currentTracks.count {
      newQueueTracks.append(contentsOf: currentTracks[0..<currentTrackIndex])
    }

    // Window the materialized queue — currentItemDidChange tops it up on every transition.
    if newQueueTracks.count > Constants.queueWindowSize {
      newQueueTracks.removeSubrange(Constants.queueWindowSize...)
    }

    // Collect existing upcoming AVPlayerItems
    let upcomingItems: [AVPlayerItem]
    if let ci = currentItem, let ciIndex = playingItems.firstIndex(of: ci) {
      upcomingItems = Array(playingItems.suffix(from: playingItems.index(after: ciIndex)))
    } else {
      upcomingItems = []
    }

    let existingIds = upcomingItems.compactMap { $0.trackId }
    let desiredIds = newQueueTracks.map { $0.id }

    // Fast-path: nothing to do if queue already matches
    if existingIds == desiredIds {
      if let changedIds = changedTrackIds {
        if Set(existingIds).isDisjoint(with: changedIds) {
          NitroPlayerLogger.log("TrackPlayerCore",
            "✅ Queue matches & no buffered URLs changed — preserving \(existingIds.count) items for gapless")
          return
        }
      } else {
        NitroPlayerLogger.log("TrackPlayerCore",
          "✅ Queue already matches desired order — preserving \(existingIds.count) items for gapless")
        return
      }
    }

    // Surgical path (changedTrackIds provided, e.g. from updateTracks)
    if let changedIds = changedTrackIds {
      var reusableByTrackId: [String: AVPlayerItem] = [:]
      for item in upcomingItems {
        if let trackId = item.trackId, !changedIds.contains(trackId) {
          reusableByTrackId[trackId] = item
        }
      }

      let desiredIdSet = Set(desiredIds)
      for item in upcomingItems {
        guard let trackId = item.trackId else { continue }
        if changedIds.contains(trackId) || !desiredIdSet.contains(trackId) {
          player.remove(item)
        }
      }

      var lastAnchor: AVPlayerItem? = currentItem
      for (offset, trackId) in desiredIds.enumerated() {
        if let reusable = reusableByTrackId[trackId] {
          lastAnchor = reusable
        } else if let track = newQueueTracks.first(where: { $0.id == trackId }),
          let newItem = createGaplessPlayerItem(for: track, isPreload: offset < Constants.gaplessPreloadCount)
        {
          player.insert(newItem, after: lastAnchor)
          lastAnchor = newItem
        }
      }

      let preserved = reusableByTrackId.count
      let inserted = desiredIds.count - preserved
      NitroPlayerLogger.log("TrackPlayerCore",
        "🔄 Surgical rebuild: preserved \(preserved) buffered items, inserted \(inserted) new items")
      return
    }

    // Incremental path (no changedTrackIds — skip, reorder, window top-up).
    // Keep the longest matching prefix of already-buffered items and only rebuild
    // from the first divergence. A pure append (the common window top-up) therefore
    // touches nothing that is already buffered, preserving gapless transitions.
    var commonPrefix = 0
    while commonPrefix < upcomingItems.count,
      commonPrefix < newQueueTracks.count,
      upcomingItems[commonPrefix].trackId == newQueueTracks[commonPrefix].id
    {
      commonPrefix += 1
    }

    for item in upcomingItems[commonPrefix...] {
      player.remove(item)
    }

    var lastItem: AVPlayerItem? = commonPrefix > 0 ? upcomingItems[commonPrefix - 1] : currentItem
    for offset in commonPrefix..<newQueueTracks.count {
      let isPreload = offset < Constants.gaplessPreloadCount
      if let item = createGaplessPlayerItem(for: newQueueTracks[offset], isPreload: isPreload) {
        player.insert(item, after: lastItem)
        lastItem = item
      }
    }

    let created = newQueueTracks.count - commonPrefix
    NitroPlayerLogger.log(
      "TrackPlayerCore",
      "🔄 Incremental rebuild: kept \(commonPrefix) buffered items, created \(created)")
  }

  /// True when the logical queue has a track after the current one, regardless of
  /// how much of it is currently materialized into the AVQueuePlayer.
  func hasUpcomingTrack() -> Bool {
    let pendingPlayNext =
      currentTemporaryType == .playNext ? max(0, playNextStack.count - 1) : playNextStack.count
    if pendingPlayNext > 0 { return true }
    let pendingUpNext =
      currentTemporaryType == .upNext ? max(0, upNextQueue.count - 1) : upNextQueue.count
    if pendingUpNext > 0 { return true }
    return currentTrackIndex + 1 < currentTracks.count
  }

  /// Extracts custom HTTP headers (e.g. `Authorization`) from `extraPayload.headers`.
  /// These are passed to AVURLAsset so authenticated remote streams can be played.
  /// Returns nil when no string headers are present.
  func httpHeaders(for track: TrackItem) -> [String: String]? {
    // AnyMap.toDictionary() returns nested objects as [String: Any?] (optional values),
    // so cast to that and unwrap each value rather than [String: Any].
    guard let payload = track.extraPayload?.toDictionary(),
      let headersValue = payload["headers"],
      let raw = headersValue as? [String: Any?]
    else { return nil }

    var headers: [String: String] = [:]
    for (key, value) in raw {
      if let stringValue = value as? String {
        headers[key] = stringValue
      }
    }
    return headers.isEmpty ? nil : headers
  }

  /// Builds AVURLAsset options, attaching custom HTTP headers for remote (non-local) tracks.
  private func assetOptions(for track: TrackItem, isLocal: Bool) -> [String: Any] {
    var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    if !isLocal, let headers = httpHeaders(for: track) {
      // AVURLAssetHTTPHeaderFieldsKey is the de-facto mechanism for per-asset request
      // headers (also used by react-native-track-player). Applies to non-DRM HTTP(S).
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    return options
  }

  /// Builds the AVURLAsset for a track URL. Cleartext-`http` remote URLs are routed through
  /// `redirectResolver` so AVFoundation follows http→https redirects it would otherwise drop
  /// (issue #111). HTTPS and local URLs load natively, unchanged.
  func makeAsset(for track: TrackItem, url: URL, isLocal: Bool) -> AVURLAsset {
    let options = assetOptions(for: track, isLocal: isLocal)
    guard !isLocal, let wrappedURL = TrackPlayerRedirectResolver.wrap(url) else {
      return AVURLAsset(url: url, options: options)
    }
    redirectResolver.registerHeaders(httpHeaders(for: track), for: wrappedURL)
    let asset = AVURLAsset(url: wrappedURL, options: options)
    asset.resourceLoader.setDelegate(redirectResolver, queue: redirectResolver.queue)
    return asset
  }

  /// Creates a gapless-optimized AVPlayerItem with proper buffering configuration
  func createGaplessPlayerItem(for track: TrackItem, isPreload: Bool = false) -> AVPlayerItem? {
    let effectiveUrlString = DownloadManagerCore.shared.getEffectiveUrl(track: track)

    let url: URL
    let isLocal = effectiveUrlString.hasPrefix("/")

    if isLocal {
      NitroPlayerLogger.log("TrackPlayerCore", "📥 Using DOWNLOADED version for \(track.title)")
      NitroPlayerLogger.log("TrackPlayerCore", "   Local path: \(effectiveUrlString)")

      if FileManager.default.fileExists(atPath: effectiveUrlString) {
        url = URL(fileURLWithPath: effectiveUrlString)
        NitroPlayerLogger.log("TrackPlayerCore", "   File URL: \(url.absoluteString)")
        NitroPlayerLogger.log("TrackPlayerCore", "   ✅ File verified to exist")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Downloaded file does NOT exist at path!")
        NitroPlayerLogger.log("TrackPlayerCore", "   Falling back to remote URL: \(track.url)")
        guard let remoteUrl = URL(string: track.url) else {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Invalid remote URL: \(track.url)")
          return nil
        }
        url = remoteUrl
      }
    } else {
      guard let remoteUrl = URL(string: effectiveUrlString) else {
        NitroPlayerLogger.log("TrackPlayerCore", "❌ Invalid URL for track: \(track.title) - \(effectiveUrlString)")
        return nil
      }
      url = remoteUrl
      NitroPlayerLogger.log("TrackPlayerCore", "🌐 Using REMOTE version for \(track.title)")
    }

    let asset: AVURLAsset
    if let preloadedAsset = preloadedAssets[track.id] {
      asset = preloadedAsset
      NitroPlayerLogger.log("TrackPlayerCore", "🚀 Using preloaded asset for \(track.title)")
    } else {
      asset = makeAsset(for: track, url: url, isLocal: isLocal)
    }

    let item = AVPlayerItem(asset: asset)

    // Let the system choose the optimal forward buffer size (0 = automatic).
    item.preferredForwardBufferDuration = 0

    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    item.trackId = track.id

    // Deliberately NOT calling loadValuesAsynchronously here.
    //
    // AVURLAsset.dealloc blocks its thread inside URLAssetFinalize until any in-flight
    // key load finishes — and AVPlayer tears removed items down on the MAIN thread, so
    // an item discarded mid-load stalls the main run loop (and RCTTiming with it, which
    // stops JS timers). Asset warm-up still happens in preloadUpcomingTracks, which only
    // publishes assets into `preloadedAssets` once every key has finished loading, so a
    // reused preloaded asset has nothing in flight either.
    //
    // Caveat: with the equalizer ENABLED, applyAudioMix still loads the "tracks" key
    // asynchronously for assets that don't have it yet, so a small window remains. That
    // is unchanged from before (it was already the non-preload path) and is strictly
    // less in-flight work than the previous 4-key preload on every queued item.
    EqualizerCore.shared.applyAudioMix(to: item)

    return item
  }

  /// Preloads assets for upcoming tracks to enable gapless playback
  func preloadUpcomingTracks(from startIndex: Int) {
    // Snapshot every piece of playerQueue-owned state HERE (we are on playerQueue).
    // `preloadQueue` must never touch currentTracks / preloadedAssets directly —
    // Swift Array/Dictionary are not safe for concurrent access.
    let queuedTrackIds = Set(player?.items().compactMap { $0.trackId } ?? [])
    let alreadyPreloaded = Set(preloadedAssets.keys)
    let generation = preloadGeneration
    let wraps = currentRepeatMode == .playlist && !currentTracks.isEmpty
    let available =
      wraps
      ? min(Constants.gaplessPreloadCount, currentTracks.count)
      : max(0, min(startIndex + Constants.gaplessPreloadCount, currentTracks.count) - startIndex)
    guard startIndex >= 0, available > 0 else { return }
    let candidates = (0..<available).map { currentTracks[(startIndex + $0) % currentTracks.count] }

    preloadQueue.async { [weak self] in
      guard let self else { return }

      for track in candidates {
        if alreadyPreloaded.contains(track.id) || queuedTrackIds.contains(track.id) {
          continue
        }

        let effectiveUrlString = DownloadManagerCore.shared.getEffectiveUrl(track: track)
        let isLocal = effectiveUrlString.hasPrefix("/")

        let url: URL
        if isLocal {
          url = URL(fileURLWithPath: effectiveUrlString)
        } else {
          guard let remoteUrl = URL(string: effectiveUrlString) else { continue }
          url = remoteUrl
        }

        let asset = self.makeAsset(for: track, url: url, isLocal: isLocal)

        asset.loadValuesAsynchronously(forKeys: Constants.preloadAssetKeys) { [weak self] in
          var allKeysLoaded = true
          for key in Constants.preloadAssetKeys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            if status != .loaded {
              allKeysLoaded = false
              break
            }
          }

          if allKeysLoaded {
            self?.playerQueue.async {
              guard let self else { return }
              // Stale completion: the queue was torn down (or this track left it)
              // while the asset was still loading — publishing would hand a dead
              // or wrong-URL asset to createGaplessPlayerItem
              guard self.preloadGeneration == generation,
                self.currentTracks.contains(where: { $0.id == track.id })
              else {
                asset.cancelLoading()
                return
              }
              self.preloadedAssets[track.id] = asset
              NitroPlayerLogger.log("TrackPlayerCore", "🎯 Preloaded asset for upcoming track: \(track.title)")
            }
          }
        }
      }
    }
  }

  /// Clears preloaded assets that are no longer needed
  func cleanupPreloadedAssets(keepingFrom currentIndex: Int) {
    // Already on playerQueue — access preloadedAssets directly
    let keepIds: Set<String>
    if currentRepeatMode == .playlist, !self.currentTracks.isEmpty {
      let start = max(0, currentIndex)
      let keepCount = min(Constants.gaplessPreloadCount + 1, self.currentTracks.count)
      keepIds = Set(
        (0..<keepCount).compactMap {
          self.currentTracks[safe: (start + $0) % self.currentTracks.count]?.id
        })
    } else {
      let keepRange =
        currentIndex..<min(
          currentIndex + Constants.gaplessPreloadCount + 1, self.currentTracks.count)
      keepIds = Set(keepRange.compactMap { self.currentTracks[safe: $0]?.id })
    }

    let assetsToRemove = self.preloadedAssets.keys.filter { !keepIds.contains($0) }
    for id in assetsToRemove {
      // Cancel before dropping the last reference — see cancelLoading(of:).
      self.preloadedAssets.removeValue(forKey: id)?.cancelLoading()
    }

    if !assetsToRemove.isEmpty {
      NitroPlayerLogger.log("TrackPlayerCore", "🧹 Cleaned up \(assetsToRemove.count) preloaded assets")
    }
  }

  func getAllPlaylists() -> [Playlist] {
    playlistManager.getAllPlaylists().map { $0.toGeneratedPlaylist() }
  }
}
