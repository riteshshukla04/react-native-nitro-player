//
//  HybridPlayerQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 24/11/25.
//

import NitroModules

final class HybridPlayerQueue: HybridPlayerQueueSpec {
  private let playlistManager = PlaylistManager.shared
  private let core = TrackPlayerCore.shared

  // Per-instance listener removers (no static storage)
  private var playlistsChangeRemover: (() -> Void)?
  private var playlistChangeRemovers: [() -> Void] = []

  // MARK: - Playlist CRUD

  func createPlaylist(name: String, description: String?, artwork: String?) throws -> any Promise<String> {
    .async { [playlistManager] in playlistManager.createPlaylist(name: name, description: description, artwork: artwork) }
  }

  func deletePlaylist(playlistId: String) throws -> any Promise<Void> {
    .async { [playlistManager] in
      guard playlistManager.deletePlaylist(playlistId: playlistId) else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
    }
  }

  func updatePlaylist(playlistId: String, name: String?, description: String?, artwork: String?) throws -> any Promise<Void> {
    .async { [playlistManager, core] in
      guard playlistManager.updatePlaylist(
        playlistId: playlistId, name: name, description: description, artwork: artwork)
      else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
      core.updatePlaylist(playlistId: playlistId)
    }
  }

  func getPlaylist(playlistId: String) throws -> Variant_NullType_Playlist {
    if let playlist = playlistManager.getPlaylist(playlistId: playlistId) {
      return Variant_NullType_Playlist.second(playlist.toGeneratedPlaylist())
    }
    return Variant_NullType_Playlist.first(NullType.null)
  }

  func getAllPlaylists() throws -> [Playlist] {
    playlistManager.getAllPlaylists().map { $0.toGeneratedPlaylist() }
  }

  // MARK: - Track mutations

  func addTrackToPlaylist(playlistId: String, track: TrackItem, index: Double?) throws -> any Promise<Void> {
    .async { [playlistManager, core] in
      guard playlistManager.addTrackToPlaylist(playlistId: playlistId, track: track, index: index.map { Int($0) })
      else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
      core.updatePlaylist(playlistId: playlistId)
    }
  }

  func addTracksToPlaylist(playlistId: String, tracks: [TrackItem], index: Double?) throws -> any Promise<Void> {
    .async { [playlistManager, core] in
      guard playlistManager.addTracksToPlaylist(playlistId: playlistId, tracks: tracks, index: index.map { Int($0) })
      else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
      core.updatePlaylist(playlistId: playlistId)
    }
  }

  /// Same semantics as the batch form: unknown ids are skipped, only a missing playlist rejects.
  func removeTrackFromPlaylist(playlistId: String, trackId: String) throws -> any Promise<Void> {
    try removeTracksFromPlaylist(playlistId: playlistId, trackIds: [trackId])
  }

  func reorderTrackInPlaylist(playlistId: String, trackId: String, newIndex: Double) throws -> any Promise<Void> {
    .async { [playlistManager, core] in
      guard playlistManager.reorderTrackInPlaylist(
        playlistId: playlistId, trackId: trackId, newIndex: Int(newIndex))
      else {
        throw RuntimeError("Invalid reorder for track \(trackId) in playlist \(playlistId)")
      }
      core.updatePlaylist(playlistId: playlistId)
    }
  }

  /// On the player queue: the live queue must reflect the removal before the promise resolves.
  func removeTracksFromPlaylist(playlistId: String, trackIds: [String]) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [playlistManager, core] in
      guard let removed = playlistManager.removeTracksFromPlaylist(playlistId: playlistId, trackIds: trackIds) else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
      if removed > 0, core.currentPlaylistId == playlistId {
        core.syncCurrentPlaylistOnQueue(playlistId: playlistId)
      }
    }
  }

  /// On the player queue: the anchor id is player-queue state.
  func shufflePlaylist(playlistId: String, options: ShufflePlaylistOptions?) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [playlistManager, core] in
      let isCurrent = core.currentPlaylistId == playlistId
      let pin: String? =
        (isCurrent && options?.keepCurrentTrackFirst != false)
        ? core.currentTracks[safe: core.currentTrackIndex]?.id : nil
      guard let changed = playlistManager.shufflePlaylist(playlistId: playlistId, firstTrackId: pin) else {
        throw RuntimeError("Playlist not found: \(playlistId)")
      }
      if changed, isCurrent { core.syncCurrentPlaylistOnQueue(playlistId: playlistId) }
    }
  }

  // MARK: - Playback control

  /// Enqueued synchronously on the player queue so a `loadPlaylist()` followed by
  /// `play()` from JS cannot be reordered (see "Ordered dispatch" in HybridTrackPlayer).
  func loadPlaylist(playlistId: String, index: Double?) throws -> any Promise<Void> {
    let startIndex = index.map { Int($0) }
    return .parallel(core.playerQueue) { [playlistManager, core] in
      // Update PlaylistManager.currentPlaylistId so getCurrentPlaylistId() returns correctly
      guard playlistManager.loadPlaylist(playlistId: playlistId, index: startIndex) else {
        throw RuntimeError("Invalid playlist or index: \(playlistId)")
      }
      core.loadPlaylistOnQueue(playlistId: playlistId, startIndex: startIndex)
    }
  }

  func getCurrentPlaylistId() throws -> Variant_NullType_String {
    if let id = playlistManager.getCurrentPlaylistId() {
      return Variant_NullType_String.second(id)
    }
    return Variant_NullType_String.first(NullType.null)
  }

  // MARK: - Events (per-instance listener storage)

  func onPlaylistsChanged(callback: any Callback<([Playlist], QueueOperation?), Void>) throws {
    let remover = playlistManager.addPlaylistsChangeListener { playlists, operation in
      callback(playlists.map { $0.toGeneratedPlaylist() }, operation)
    }
    playlistsChangeRemover = remover
  }

  func onPlaylistChanged(callback: any Callback<(String, Playlist, QueueOperation?), Void>) throws {
    // Manager-level listener: covers playlists created after registration.
    let remover = playlistManager.addAnyPlaylistChangeListener { updated, operation in
      callback(updated.id, updated.toGeneratedPlaylist(), operation)
    }
    playlistChangeRemovers.append(remover)
  }

  // MARK: - Cleanup

  deinit {
    playlistsChangeRemover?()
    playlistChangeRemovers.forEach { $0() }
  }
}
