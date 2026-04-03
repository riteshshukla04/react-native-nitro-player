//
//  TrackPlayerQueueBuild.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation

import Foundation

extension TrackPlayerCore {

  func updatePlayerQueue(tracks: [TrackItem]) {
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
    preloadedAssets.removeAll()

    guard let existingPlayer = self.player else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player available")
      return
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🔄 Removing \(existingPlayer.items().count) old items from player")
    existingPlayer.removeAllItems()

    // Lazy-load mode: if any track has no URL AND is not downloaded locally,
    // we can't create an AVPlayerItem for it and the queue order would be wrong.
    let isLazyLoad = tracks.contains {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }
    if isLazyLoad {
      NitroPlayerLogger.log("TrackPlayerCore", "⏳ Lazy-load mode — player cleared, awaiting URL resolution")
      return
    }

    let items = tracks.enumerated().compactMap { (index, track) -> AVPlayerItem? in
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
      self.currentTracks = fullPlaylist
      if let track = self.currentTracks[safe: index] {
        notifyTrackChange(track, .skip)
      }
      return true
    }

    let tracksToPlay = Array(fullPlaylist[index...])
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

    player.removeAllItems()
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

    if wasPlaying { player.play() }
    return true
  }

  /// Rebuilds the AVQueuePlayer from the current position with temporary tracks.
  /// Order: [current] + [playNext stack] + [upNext queue] + [remaining original]
  ///
  /// - Parameter changedTrackIds: When non-nil, performs a surgical update:
  ///   only AVPlayerItems whose track ID is in this set are removed and re-created.
  func rebuildAVQueueFromCurrentPosition(changedTrackIds: Set<String>? = nil) {
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

    // Full rebuild path (no changedTrackIds — skip, reorder, etc.)
    for item in playingItems where item != currentItem {
      player.remove(item)
    }

    var lastItem = currentItem
    for (offset, track) in newQueueTracks.enumerated() {
      let isPreload = offset < Constants.gaplessPreloadCount
      if let item = createGaplessPlayerItem(for: track, isPreload: isPreload) {
        player.insert(item, after: lastItem)
        lastItem = item
      }
    }
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
      asset = AVURLAsset(url: url, options: [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
      ])
    }

    let item = AVPlayerItem(asset: asset)

    // Let the system choose the optimal forward buffer size (0 = automatic).
    item.preferredForwardBufferDuration = 0

    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    item.trackId = track.id

    if isPreload {
      asset.loadValuesAsynchronously(forKeys: Constants.preloadAssetKeys) {
        var allKeysLoaded = true
        for key in Constants.preloadAssetKeys {
          var error: NSError?
          let status = asset.statusOfValue(forKey: key, error: &error)
          if status == .failed {
            NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Failed to load key '\(key)' for \(track.title): \(error?.localizedDescription ?? "unknown")")
            allKeysLoaded = false
          }
        }
        if allKeysLoaded {
          NitroPlayerLogger.log("TrackPlayerCore", "✅ All asset keys preloaded for \(track.title)")
        }
        // "tracks" key is now loaded — EQ tap attaches synchronously
        EqualizerCore.shared.applyAudioMix(to: item)
      }
    } else {
      EqualizerCore.shared.applyAudioMix(to: item)
    }

    return item
  }

  /// Preloads assets for upcoming tracks to enable gapless playback
  func preloadUpcomingTracks(from startIndex: Int) {
    // Capture the set of track IDs that already have AVPlayerItems in the queue.
    let queuedTrackIds = Set(player?.items().compactMap { $0.trackId } ?? [])

    preloadQueue.async { [weak self] in
      guard let self else { return }

      let tracks = self.currentTracks
      let endIndex = min(startIndex + Constants.gaplessPreloadCount, tracks.count)

      for i in startIndex..<endIndex {
        guard i < tracks.count else { break }
        let track = tracks[i]

        if self.preloadedAssets[track.id] != nil || queuedTrackIds.contains(track.id) {
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

        let asset = AVURLAsset(url: url, options: [
          AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

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
              self?.preloadedAssets[track.id] = asset
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
    let keepRange =
      currentIndex..<min(
        currentIndex + Constants.gaplessPreloadCount + 1, self.currentTracks.count)
    let keepIds = Set(keepRange.compactMap { self.currentTracks[safe: $0]?.id })

    let assetsToRemove = self.preloadedAssets.keys.filter { !keepIds.contains($0) }
    for id in assetsToRemove {
      self.preloadedAssets.removeValue(forKey: id)
    }

    if !assetsToRemove.isEmpty {
      NitroPlayerLogger.log("TrackPlayerCore", "🧹 Cleaned up \(assetsToRemove.count) preloaded assets")
    }
  }

  func getAllPlaylists() -> [Playlist] {
    playlistManager.getAllPlaylists().map { $0.toGeneratedPlaylist() }
  }
}
