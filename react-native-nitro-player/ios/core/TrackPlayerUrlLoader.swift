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
    // The current track's player item has failed (e.g. an expired streaming URL).
    // Unlike a healthy current track, a failed one MUST accept a fresh URL so that
    // recoverFailedItem can rebuild it from updated track data.
    let currentItemFailed = self.player?.currentItem?.status == .failed
      && self.player?.currentItem?.trackId == currentTrackId

    let safeTracks = tracks.filter { track in
      switch true {
      case track.id == currentTrackId && (currentTrackIsEmpty || currentItemFailed):
        NitroPlayerLogger.log("TrackPlayerCore",
          "🔄 Updating current track (\(currentItemFailed ? "failed item" : "no URL")): \(track.id)")
        return !track.url.isEmpty
      case track.id == currentTrackId:
        NitroPlayerLogger.log("TrackPlayerCore",
          "⚠️ Skipping update for currently playing track: \(track.id) (preserves gapless)")
        return false
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
        self.preloadedAssets.removeValue(forKey: trackId)?.cancelLoading()
      }
    }

    // Update in PlaylistManager
    let affectedPlaylists = self.playlistManager.updateTracks(tracks: safeTracks)

    // Replace the current AVPlayerItem when its URL just resolved (local only — cast reloads below instead).
    // Look up the FRESH track — the pre-update snapshot's URL is empty by definition here.
    if !self.isCasting, currentTrackIsEmpty,
      let update = safeTracks.first(where: { $0.id == currentTrackId }), !update.url.isEmpty {
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
        self.currentTracks = applyShuffleOrder(updatedPlaylist.tracks)
        NitroPlayerLogger.log("TrackPlayerCore",
          "📥 Synced currentTracks from PlaylistManager (\(self.currentTracks.count) tracks)")
      }

      if self.isCasting {
        // Resolved URLs are applied by (re)loading/extending the remote queue — never by touching the silent local player.
        let currentResolvedNow = currentTrackIsEmpty
          && currentTrackId.map { id in updatedTrackIds.contains(id) } ?? false
        let staleOnReceiver = !updatedTrackIds
          .isDisjoint(with: Set(self.castManager?.loadedTrackIds ?? []))

        if currentResolvedNow || !(self.castManager?.hasLoadedMedia ?? false) {
          // Parked track just became castable (or nothing loaded) — atomic load from current.
          self.loadCastQueue(autoplay: self.intendedToPlay, position: 0)
        } else if staleOnReceiver {
          // URLs changed for items already on the receiver — reload at position before stale ones fail.
          self.loadCastQueue(
            autoplay: self.intendedToPlay,
            position: self.castManager?.lastKnownRemotePosition ?? 0
          )
        } else {
          // Newly castable tracks extend the receiver queue without interrupting playback.
          self.syncCastQueueAfterCurrent()
        }
        NitroPlayerLogger.log("TrackPlayerCore", "✅ Cast queue synced after track updates")
        return
      }

      if self.player?.currentItem == nil, let player = self.player {
        // No AVPlayerItem exists yet — lazy-load mode: URLs were empty when the queue first loaded.
        NitroPlayerLogger.log("TrackPlayerCore",
          "🔄 No current item — full queue rebuild from currentTrackIndex \(self.currentTrackIndex)")
        self.removeAllItemsCancellingLoads(player)
        var lastItem: AVPlayerItem? = nil
        // Window like every other rebuild path — materializing the whole remaining
        // playlist builds thousands of AVPlayerItems on playerQueue at once.
        let windowed = self.currentTracks[max(0, self.currentTrackIndex)...]
          .prefix(1 + Constants.queueWindowSize)
        for (offset, track) in windowed.enumerated() {
          let isPreload = offset < Constants.gaplessPreloadCount
          if let newItem = self.createGaplessPlayerItem(for: track, isPreload: isPreload) {
            player.insert(newItem, after: lastItem)
            lastItem = newItem
          }
        }
        if self.intendedToPlay {
          player.rate = Float(self.currentPlaybackSpeed)
        }
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

  /// Walks the queue structure directly instead of materializing the whole queue —
  /// this runs on every skip and on the periodic boundary observer, so it must not
  /// be O(playlist) just to read the next few tracks.
  func getNextTracksInternal(count: Int) -> [TrackItem] {
    guard count > 0 else { return [] }
    var out: [TrackItem] = []
    out.reserveCapacity(count)
    let currentId = activeCurrentTrackId

    var skippedPlayNext = currentTemporaryType != .playNext
    for track in playNextStack {
      if !skippedPlayNext && track.id == currentId {
        skippedPlayNext = true
        continue
      }
      out.append(track)
      if out.count == count { return out }
    }

    var skippedUpNext = currentTemporaryType != .upNext
    for track in upNextQueue {
      if !skippedUpNext && track.id == currentId {
        skippedUpNext = true
        continue
      }
      out.append(track)
      if out.count == count { return out }
    }

    var index = currentTrackIndex + 1
    while index < currentTracks.count && out.count < count {
      out.append(currentTracks[index])
      index += 1
    }
    return out
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
