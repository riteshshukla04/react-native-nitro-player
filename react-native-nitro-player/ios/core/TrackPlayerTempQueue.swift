//
//  TrackPlayerTempQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//
import Foundation

extension TrackPlayerCore {

  func loadPlaylist(playlistId: String) async {
    await withPlayerQueueNoThrow {
      self.playNextStack.removeAll()
      self.upNextQueue.removeAll()
      self.currentTemporaryType = .none

      NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "🎼", count: Constants.playlistSeparatorLength))
      NitroPlayerLogger.log("TrackPlayerCore", "📂 LOAD PLAYLIST REQUEST")
      NitroPlayerLogger.log("TrackPlayerCore", "   Playlist ID: \(playlistId)")
      NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

      guard let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) else {
        NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Playlist NOT FOUND")
        NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")
        return
      }

      NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Found playlist: \(playlist.name)")
      NitroPlayerLogger.log("TrackPlayerCore", "   📋 Contains \(playlist.tracks.count) tracks:")
      for (index, track) in playlist.tracks.enumerated() {
        NitroPlayerLogger.log("TrackPlayerCore", "      [\(index + 1)] \(track.title) - \(track.artist)")
      }
      NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")

      self.currentPlaylistId = playlistId
      self.updatePlayerQueue(tracks: playlist.tracks)
      self.emitStateChange()
      self.checkUpcomingTracksForUrls(lookahead: self.lookaheadCount)
      self.notifyTemporaryQueueChange()
    }
  }

  func updatePlaylist(playlistId: String) {
    guard currentPlaylistId == playlistId else { return }

    // Cancel any pending rebuild so back-to-back calls collapse into a single rebuild.
    pendingPlaylistUpdateWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.currentPlaylistId == playlistId,
        let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) else { return }

      // If nothing is playing yet, do a full load
      guard self.player?.currentItem != nil else {
        self.updatePlayerQueue(tracks: playlist.tracks)
        self.checkUpcomingTracksForUrls(lookahead: self.lookaheadCount)
        return
      }

      // Update tracks list without interrupting playback
      self.currentTracks = playlist.tracks
      self.rebuildAVQueueFromCurrentPosition()
      self.checkUpcomingTracksForUrls(lookahead: self.lookaheadCount)
    }

    pendingPlaylistUpdateWorkItem = workItem
    playerQueue.async(execute: workItem)
  }

  func playNext(trackId: String) async throws {
    try await withPlayerQueue {
      guard let track = self.findTrackById(trackId) else {
        throw NSError(domain: "NitroPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track \(trackId) not found"])
      }
      NitroPlayerLogger.log("TrackPlayerCore", "⏭️ playNext(\(trackId))")
      self.playNextStack.insert(track, at: 0)
      NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Added '\(track.title)' to playNext stack (position: 1)")
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
    }
  }

  func addToUpNext(trackId: String) async throws {
    try await withPlayerQueue {
      guard let track = self.findTrackById(trackId) else {
        throw NSError(domain: "NitroPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track \(trackId) not found"])
      }
      NitroPlayerLogger.log("TrackPlayerCore", "📋 addToUpNext(\(trackId))")
      self.upNextQueue.append(track)
      NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Added '\(track.title)' to upNext queue (position: \(self.upNextQueue.count))")
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
    }
  }

  func removeFromPlayNext(trackId: String) async -> Bool {
    await withPlayerQueueNoThrow {
      guard let idx = self.playNextStack.firstIndex(where: { $0.id == trackId }) else { return false }
      self.playNextStack.remove(at: idx)
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
      return true
    }
  }

  func removeFromUpNext(trackId: String) async -> Bool {
    await withPlayerQueueNoThrow {
      guard let idx = self.upNextQueue.firstIndex(where: { $0.id == trackId }) else { return false }
      self.upNextQueue.remove(at: idx)
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
      return true
    }
  }

  func clearPlayNext() async {
    await withPlayerQueueNoThrow {
      self.playNextStack.removeAll()
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
    }
  }

  func clearUpNext() async {
    await withPlayerQueueNoThrow {
      self.upNextQueue.removeAll()
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
    }
  }

  func reorderTemporaryTrack(trackId: String, newIndex: Int) async -> Bool {
    await withPlayerQueueNoThrow {
      var combined = self.playNextStack + self.upNextQueue
      guard let fromIdx = combined.firstIndex(where: { $0.id == trackId }) else { return false }
      let track = combined.remove(at: fromIdx)
      let clamped = newIndex.clamped(to: 0...combined.count)
      combined.insert(track, at: clamped)
      let pnSize = self.playNextStack.count
      self.playNextStack = Array(combined.prefix(pnSize))
      self.upNextQueue = Array(combined.dropFirst(pnSize))
      if self.player?.currentItem != nil { self.rebuildAVQueueFromCurrentPosition() }
      self.notifyTemporaryQueueChange()
      return true
    }
  }

  func getPlayNextQueue() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.playNextStack }
  }

  func getUpNextQueue() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.upNextQueue }
  }

  func findTrackById(_ trackId: String) -> TrackItem? {
    if let t = currentTracks.first(where: { $0.id == trackId }) { return t }
    for playlist in playlistManager.getAllPlaylists() {
      if let t = playlist.tracks.first(where: { $0.id == trackId }) { return t }
    }
    return nil
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
