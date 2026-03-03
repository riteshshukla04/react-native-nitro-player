//
//  TrackPlayerCore+LazyURLLoading.swift
//  NitroPlayer
//

import AVFoundation
import Foundation

// MARK: - Lazy URL Loading Support

extension TrackPlayerCore {

  typealias OnTracksNeedUpdateCallback = ([TrackItem], Int) -> Void

  /**
   * Update entire track objects and rebuild queue if needed
   * Skips currently playing track to preserve gapless playback
   * CRITICAL: Invalidates preloaded assets and re-preloads for gapless
   */
  func updateTracks(tracks: [TrackItem]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      NitroPlayerLogger.log("TrackPlayerCore", "🔄 updateTracks: \(tracks.count) updates")

      // Get current track to check if it has a URL yet (lazy-loaded initial state)
      let currentTrack = self.getCurrentTrack()
      let currentTrackId = currentTrack?.id
      let currentTrackNeedsUrl = currentTrack?.url.isEmpty ?? false

      // Filter out current track only if it already has a valid URL (preserves gapless playback).
      // If the current track has an empty URL it was never loadable - allow the update so
      // the player can actually start.
      let safeTracks = tracks.filter { track in
        switch true {
        case track.id == currentTrackId && !currentTrackNeedsUrl:
          NitroPlayerLogger.log(
            "TrackPlayerCore",
            "⚠️ Skipping update for currently playing track: \(track.id) (preserves gapless)")
          return false
        case track.url.isEmpty:
          NitroPlayerLogger.log(
            "TrackPlayerCore", "⚠️ Skipping track with empty URL: \(track.id)")
          return false
        default:
          return true
        }
      }

      guard !safeTracks.isEmpty else {
        NitroPlayerLogger.log("TrackPlayerCore", "✅ No valid updates to apply")
        return
      }

      // Invalidate preloaded assets for tracks with updated data
      // This is CRITICAL for gapless playback - old assets might use old URLs
      let updatedTrackIds = Set(safeTracks.map { $0.id })
      for trackId in updatedTrackIds {
        if self.preloadedAssets[trackId] != nil {
          NitroPlayerLogger.log(
            "TrackPlayerCore", "🗑️ Invalidating preloaded asset for track: \(trackId)")
          self.preloadedAssets.removeValue(forKey: trackId)
        }
      }

      // Update in PlaylistManager
      let affectedPlaylists = self.playlistManager.updateTracks(tracks: safeTracks)

      // Rebuild queue if current playlist was affected
      if let currentId = self.currentPlaylistId,
        let updateCount = affectedPlaylists[currentId]
      {
        NitroPlayerLogger.log(
          "TrackPlayerCore",
          "🔄 Rebuilding queue - \(updateCount) tracks updated in current playlist")

        // Sync in-memory currentTracks with the playlist manager's updated data so that
        // rebuildAVQueueFromCurrentPosition uses the fresh URLs
        if let updatedPlaylist = self.playlistManager.getPlaylist(playlistId: currentId) {
          self.currentTracks = updatedPlaylist.tracks
        }

        if self.player?.currentItem == nil, let player = self.player {
          // No AVPlayerItem exists at all — the track's URL was empty when the queue was
          // first loaded (lazy URL case, NOT a download). Rebuild from currentTrackIndex
          // using removeAllItems so we don't disturb an index that skipToIndex already set.
          NitroPlayerLogger.log(
            "TrackPlayerCore",
            "🔄 No current item - rebuilding from currentTrackIndex \(self.currentTrackIndex)")

          player.removeAllItems()

          // Insert tracks starting from currentTrackIndex, preserving that index
          var lastItem: AVPlayerItem? = nil
          for (offset, track) in self.currentTracks[self.currentTrackIndex...].enumerated() {
            let isPreload = offset < Constants.gaplessPreloadCount
            if let newItem = self.createGaplessPlayerItem(for: track, isPreload: isPreload) {
              player.insert(newItem, after: lastItem)
              lastItem = newItem
            }
          }

          self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
        } else {
          // A current AVPlayerItem already exists (stream that was mid-play, or a downloaded
          // track whose local-file item is valid even though TrackItem.url is empty).
          // Preserve it and only rebuild the upcoming items.
          self.rebuildAVQueueFromCurrentPosition()

          // Re-preload upcoming tracks for gapless playback
          // CRITICAL: This restores gapless buffering after queue rebuild
          self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
        }

        NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue rebuilt, gapless playback preserved")
      }

      NitroPlayerLogger.log(
        "TrackPlayerCore",
        "✅ Track updates complete - \(affectedPlaylists.count) playlists affected")
    }
  }

  /**
   * Get tracks by IDs from all playlists
   */
  func getTracksById(trackIds: [String]) -> [TrackItem] {
    if Thread.isMainThread {
      return playlistManager.getTracksById(trackIds: trackIds)
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.playlistManager.getTracksById(trackIds: trackIds) ?? []
      }
      return tracks
    }
  }

  /**
   * Get tracks needing URLs from current playlist
   */
  func getTracksNeedingUrls() -> [TrackItem] {
    if Thread.isMainThread {
      return getTracksNeedingUrlsInternal()
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.getTracksNeedingUrlsInternal() ?? []
      }
      return tracks
    }
  }

  private func getTracksNeedingUrlsInternal() -> [TrackItem] {
    guard let currentId = currentPlaylistId,
      let playlist = playlistManager.getPlaylist(playlistId: currentId)
    else {
      return []
    }

    return playlist.tracks.filter { $0.url.isEmpty }
  }

  /**
   * Get next N tracks from current position
   */
  func getNextTracks(count: Int) -> [TrackItem] {
    if Thread.isMainThread {
      return getNextTracksInternal(count: count)
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.getNextTracksInternal(count: count) ?? []
      }
      return tracks
    }
  }

  func getNextTracksInternal(count: Int) -> [TrackItem] {
    let actualQueue = getActualQueueInternal()
    guard !actualQueue.isEmpty else { return [] }

    guard let currentTrack = getCurrentTrack(),
      let currentIndex = actualQueue.firstIndex(where: { $0.id == currentTrack.id })
    else {
      return []
    }

    let startIndex = currentIndex + 1
    let endIndex = min(startIndex + count, actualQueue.count)

    return startIndex < actualQueue.count ? Array(actualQueue[startIndex..<endIndex]) : []
  }

  /**
   * Get current track index in playlist
   */
  func getCurrentTrackIndex() -> Int {
    if Thread.isMainThread {
      return currentTrackIndex
    } else {
      var index = -1
      DispatchQueue.main.sync { [weak self] in
        index = self?.currentTrackIndex ?? -1
      }
      return index
    }
  }

  /**
   * Register listener for when tracks need update
   */
  func addOnTracksNeedUpdateListener(callback: @escaping OnTracksNeedUpdateCallback) {
    tracksNeedUpdateQueue.async(flags: .barrier) { [weak self] in
      self?.onTracksNeedUpdateListeners.append((callback: callback, isAlive: true))
    }
  }

  /**
   * Notify listeners that tracks need updating
   */
  func notifyTracksNeedUpdate(tracks: [TrackItem], lookahead: Int) {
    tracksNeedUpdateQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      // Clean up dead listeners
      self.onTracksNeedUpdateListeners.removeAll { !$0.isAlive }
      let liveCallbacks = self.onTracksNeedUpdateListeners.map { $0.callback }

      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(tracks, lookahead)
          }
        }
      }
    }
  }

  /**
   * Check if upcoming tracks need URLs and notify listeners
   * Call this in playerItemDidPlayToEndTime or after skip operations
   */
  func checkUpcomingTracksForUrls(lookahead: Int = 5) {
    var tracksNeedingUrls: [TrackItem] = []

    // Also check the current track - if it has no URL it must be populated before playback can begin
    if let currentTrack = getCurrentTrack(), currentTrack.url.isEmpty {
      NitroPlayerLogger.log(
        "TrackPlayerCore", "⚠️ Current track needs a URL: \(currentTrack.title)")
      tracksNeedingUrls.append(currentTrack)
    }

    let nextTracks = getNextTracksInternal(count: lookahead)
    tracksNeedingUrls += nextTracks.filter { $0.url.isEmpty }

    if !tracksNeedingUrls.isEmpty {
      NitroPlayerLogger.log(
        "TrackPlayerCore", "⚠️ \(tracksNeedingUrls.count) upcoming tracks need URLs")
      notifyTracksNeedUpdate(tracks: tracksNeedingUrls, lookahead: lookahead)
    }
  }
}
