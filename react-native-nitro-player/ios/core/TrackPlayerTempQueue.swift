//
//  TrackPlayerTempQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//
import Foundation

extension TrackPlayerCore {

  func loadPlaylist(playlistId: String, startIndex: Int? = nil) async {
    await withPlayerQueueNoThrow { self.loadPlaylistOnQueue(playlistId: playlistId, startIndex: startIndex) }
  }

  func loadPlaylistOnQueue(playlistId: String, startIndex: Int? = nil) {
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

      let targetIndex: Int
      if let startIndex {
        guard startIndex >= 0 && startIndex < playlist.tracks.count else {
          NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Invalid start index: \(startIndex) (track count: \(playlist.tracks.count))")
          return
        }
        targetIndex = startIndex
      } else {
        targetIndex = 0
      }

      self.currentPlaylistId = playlistId
      if targetIndex == 0 {
        self.updatePlayerQueue(tracks: playlist.tracks)
      } else {
        // Bypass updatePlayerQueue to avoid emitting a spurious onTrackChange for index 0.
        // Set currentTracks directly so rebuildQueueFromPlaylistIndex can use them.
        self.currentTracks = playlist.tracks
        self.preloadedAssets.values.forEach { $0.cancelLoading() }
        self.preloadedAssets.removeAll()
        _ = self.rebuildQueueFromPlaylistIndex(index: targetIndex)
      }
      self.emitStateChange()
      self.checkUpcomingTracksForUrls(lookahead: self.lookaheadCount)
      self.notifyTemporaryQueueChange()
  }

  /// Callable from any thread (PlaylistManager runs on its own queue) — all state
  /// access happens on playerQueue.
  func updatePlaylist(playlistId: String) {
    playerQueue.async { [weak self] in
      guard let self, self.currentPlaylistId == playlistId else { return }

      self.playlistUpdateGeneration &+= 1
      let generation = self.playlistUpdateGeneration

      // Run at the tail of the current burst; stale generations drop out.
      self.playerQueue.async { [weak self] in
        guard let self, generation == self.playlistUpdateGeneration,
          self.currentPlaylistId == playlistId,
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
    }
  }

  func playNextOnQueue(trackId: String) throws {
    guard let track = findTrackById(trackId) else {
      throw NSError(domain: "NitroPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track \(trackId) not found"])
    }
    NitroPlayerLogger.log("TrackPlayerCore", "⏭️ playNext(\(trackId))")
    playNextStack.insert(track, at: 0)
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
  }
  func playNext(trackId: String) async throws {
    try await withPlayerQueue { try self.playNextOnQueue(trackId: trackId) }
  }

  func addToUpNextOnQueue(trackId: String) throws {
    guard let track = findTrackById(trackId) else {
      throw NSError(domain: "NitroPlayer", code: 404, userInfo: [NSLocalizedDescriptionKey: "Track \(trackId) not found"])
    }
    NitroPlayerLogger.log("TrackPlayerCore", "📋 addToUpNext(\(trackId))")
    upNextQueue.append(track)
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
  }
  func addToUpNext(trackId: String) async throws {
    try await withPlayerQueue { try self.addToUpNextOnQueue(trackId: trackId) }
  }

  func removeFromPlayNextOnQueue(trackId: String) -> Bool {
    guard let idx = playNextStack.firstIndex(where: { $0.id == trackId }) else { return false }
    playNextStack.remove(at: idx)
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
    return true
  }
  func removeFromPlayNext(trackId: String) async -> Bool {
    await withPlayerQueueNoThrow { self.removeFromPlayNextOnQueue(trackId: trackId) }
  }

  func removeFromUpNextOnQueue(trackId: String) -> Bool {
    guard let idx = upNextQueue.firstIndex(where: { $0.id == trackId }) else { return false }
    upNextQueue.remove(at: idx)
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
    return true
  }
  func removeFromUpNext(trackId: String) async -> Bool {
    await withPlayerQueueNoThrow { self.removeFromUpNextOnQueue(trackId: trackId) }
  }

  func clearPlayNextOnQueue() {
    playNextStack.removeAll()
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
  }
  func clearPlayNext() async { await withPlayerQueueNoThrow { self.clearPlayNextOnQueue() } }

  func clearUpNextOnQueue() {
    upNextQueue.removeAll()
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
  }
  func clearUpNext() async { await withPlayerQueueNoThrow { self.clearUpNextOnQueue() } }

  func reorderTemporaryTrackOnQueue(trackId: String, newIndex: Int) -> Bool {
    var combined = playNextStack + upNextQueue
    guard let fromIdx = combined.firstIndex(where: { $0.id == trackId }) else { return false }
    let track = combined.remove(at: fromIdx)
    let clamped = newIndex.clamped(to: 0...combined.count)
    combined.insert(track, at: clamped)
    let pnSize = playNextStack.count
    playNextStack = Array(combined.prefix(pnSize))
    upNextQueue = Array(combined.dropFirst(pnSize))
    if player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    notifyTemporaryQueueChange()
    return true
  }
  func reorderTemporaryTrack(trackId: String, newIndex: Int) async -> Bool {
    await withPlayerQueueNoThrow { self.reorderTemporaryTrackOnQueue(trackId: trackId, newIndex: newIndex) }
  }

  func getPlayNextQueue() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.playNextStack }
  }

  func getUpNextQueue() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.upNextQueue }
  }

  func findTrackById(_ trackId: String) -> TrackItem? {
    if let t = currentTracks.first(where: { $0.id == trackId }) { return t }
    // Temporary-queue tracks need not exist in any playlist — search the temp
    // stacks too so a failed playNext/upNext track is still recoverable.
    if let t = playNextStack.first(where: { $0.id == trackId }) { return t }
    if let t = upNextQueue.first(where: { $0.id == trackId }) { return t }
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
