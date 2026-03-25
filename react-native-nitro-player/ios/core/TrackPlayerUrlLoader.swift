//
//  TrackPlayerUrlLoader.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation
import Foundation

extension TrackPlayerCore {

  func updateTracks(tracks: [TrackItem]) async {
    await withPlayerQueueNoThrow { self.updateTracksInternal(tracks: tracks) }
  }

  func getTracksById(trackIds: [String]) async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.playlistManager.getTracksById(trackIds: trackIds) }
  }

  func getTracksNeedingUrls() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.getTracksNeedingUrlsInternal() }
  }

  func getNextTracks(count: Int) async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.getNextTracksInternal(count: count) }
  }

  // MARK: - Internal

  func updateTracksInternal(tracks: [TrackItem]) {
    NitroPlayerLogger.log("TrackPlayerCore", "🔄 updateTracks: \(tracks.count) updates")

    let currentTrack = self.getCurrentTrack()
    let currentTrackId = currentTrack?.id
    // A track is only "empty" if it has no remote URL AND is not downloaded.
    let currentTrackIsEmpty = currentTrack.map {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    } ?? false

    let safeTracks = tracks.filter { track in
      switch true {
      case track.id == currentTrackId && !currentTrackIsEmpty:
        NitroPlayerLogger.log("TrackPlayerCore",
          "⚠️ Skipping update for currently playing track: \(track.id) (preserves gapless)")
        return false
      case track.id == currentTrackId && currentTrackIsEmpty:
        NitroPlayerLogger.log("TrackPlayerCore",
          "🔄 Updating current track with no URL: \(track.id)")
        return !track.url.isEmpty
      case track.url.isEmpty:
        NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Skipping track with empty URL: \(track.id)")
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
    let updatedTrackIds = Set(safeTracks.map { $0.id })
    for trackId in updatedTrackIds {
      if self.preloadedAssets[trackId] != nil {
        NitroPlayerLogger.log("TrackPlayerCore", "🗑️ Invalidating preloaded asset for track: \(trackId)")
        self.preloadedAssets.removeValue(forKey: trackId)
      }
    }

    // Update in PlaylistManager
    let affectedPlaylists = self.playlistManager.updateTracks(tracks: safeTracks)

    // If the current track had no URL and now has one, replace the current AVPlayerItem
    if let update = currentTrack, currentTrackIsEmpty, !update.url.isEmpty {
      NitroPlayerLogger.log("TrackPlayerCore",
        "🔄 Replacing current AVPlayerItem for track with resolved URL: \(update.id)")
      if let newItem = self.createGaplessPlayerItem(for: update, isPreload: false) {
        self.player?.replaceCurrentItem(with: newItem)
      }
    }

    // Rebuild queue if current playlist was affected
    if let currentId = self.currentPlaylistId,
      let updateCount = affectedPlaylists[currentId]
    {
      NitroPlayerLogger.log("TrackPlayerCore",
        "🔄 Rebuilding queue - \(updateCount) tracks updated in current playlist")

      // Sync currentTracks from the freshly-updated PlaylistManager
      if let updatedPlaylist = self.playlistManager.getPlaylist(playlistId: currentId) {
        self.currentTracks = updatedPlaylist.tracks
        NitroPlayerLogger.log("TrackPlayerCore",
          "📥 Synced currentTracks from PlaylistManager (\(self.currentTracks.count) tracks)")
      }

      if self.player?.currentItem == nil, let player = self.player {
        // No AVPlayerItem exists yet — lazy-load mode: URLs were empty when the queue first loaded.
        NitroPlayerLogger.log("TrackPlayerCore",
          "🔄 No current item — full queue rebuild from currentTrackIndex \(self.currentTrackIndex)")
        player.removeAllItems()
        var lastItem: AVPlayerItem? = nil
        for (offset, track) in self.currentTracks[max(0, self.currentTrackIndex)...].enumerated() {
          let isPreload = offset < Constants.gaplessPreloadCount
          if let newItem = self.createGaplessPlayerItem(for: track, isPreload: isPreload) {
            player.insert(newItem, after: lastItem)
            lastItem = newItem
          }
        }
        player.play()
        self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
      } else {
        // A current AVPlayerItem already exists — preserve it and only rebuild upcoming items.
        self.rebuildAVQueueFromCurrentPosition(changedTrackIds: updatedTrackIds)
        self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
      }

      NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue rebuilt, gapless playback preserved")
    }

    NitroPlayerLogger.log("TrackPlayerCore",
      "✅ Track updates complete - \(affectedPlaylists.count) playlists affected")
  }

  func getTracksNeedingUrlsInternal() -> [TrackItem] {
    guard let currentId = currentPlaylistId,
      let playlist = playlistManager.getPlaylist(playlistId: currentId)
    else { return [] }

    // Only return tracks that truly can't play: empty remote URL AND not downloaded locally.
    return playlist.tracks.filter {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }
  }

  func getNextTracksInternal(count: Int) -> [TrackItem] {
    let actualQueue = getActualQueueInternal()
    guard !actualQueue.isEmpty else { return [] }

    guard let currentTrack = getCurrentTrack(),
      let currentIndex = actualQueue.firstIndex(where: { $0.id == currentTrack.id })
    else { return [] }

    let startIndex = currentIndex + 1
    let endIndex = min(startIndex + count, actualQueue.count)
    return startIndex < actualQueue.count ? Array(actualQueue[startIndex..<endIndex]) : []
  }

  func checkUpcomingTracksForUrls(lookahead: Int = 5) {
    let upcomingTracks = getNextTracksInternal(count: lookahead)

    let currentTrack = getCurrentTrack()
    let currentNeedsUrl = currentTrack.map {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    } ?? false
    let candidateTracks = currentNeedsUrl ? [currentTrack!] + upcomingTracks : upcomingTracks

    let tracksNeedingUrls = candidateTracks.filter {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }

    if !tracksNeedingUrls.isEmpty {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ \(tracksNeedingUrls.count) upcoming tracks need URLs")
      notifyTracksNeedUpdate(tracks: tracksNeedingUrls, lookahead: lookahead)
    }
  }
}
