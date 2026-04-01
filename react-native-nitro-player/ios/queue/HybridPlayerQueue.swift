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

  func createPlaylist(name: String, description: String?, artwork: String?) throws -> Promise<String> {
    Promise.async { self.playlistManager.createPlaylist(name: name, description: description, artwork: artwork) }
  }

  func deletePlaylist(playlistId: String) throws -> Promise<Void> {
    Promise.async { _ = self.playlistManager.deletePlaylist(playlistId: playlistId) }
  }

  func updatePlaylist(playlistId: String, name: String?, description: String?, artwork: String?) throws -> Promise<Void> {
    Promise.async {
      _ = self.playlistManager.updatePlaylist(
        playlistId: playlistId, name: name, description: description, artwork: artwork)
      self.core.updatePlaylist(playlistId: playlistId)
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

  func addTrackToPlaylist(playlistId: String, track: TrackItem, index: Double?) throws -> Promise<Void> {
    Promise.async {
      _ = self.playlistManager.addTrackToPlaylist(playlistId: playlistId, track: track, index: index.map { Int($0) })
      self.core.updatePlaylist(playlistId: playlistId)
    }
  }

  func addTracksToPlaylist(playlistId: String, tracks: [TrackItem], index: Double?) throws -> Promise<Void> {
    Promise.async {
      _ = self.playlistManager.addTracksToPlaylist(playlistId: playlistId, tracks: tracks, index: index.map { Int($0) })
      self.core.updatePlaylist(playlistId: playlistId)
    }
  }

  func removeTrackFromPlaylist(playlistId: String, trackId: String) throws -> Promise<Void> {
    Promise.async {
      _ = self.playlistManager.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
      self.core.updatePlaylist(playlistId: playlistId)
    }
  }

  func reorderTrackInPlaylist(playlistId: String, trackId: String, newIndex: Double) throws -> Promise<Void> {
    Promise.async {
      _ = self.playlistManager.reorderTrackInPlaylist(
        playlistId: playlistId, trackId: trackId, newIndex: Int(newIndex))
      self.core.updatePlaylist(playlistId: playlistId)
    }
  }

  // MARK: - Playback control

  func loadPlaylist(playlistId: String) throws -> Promise<Void> {
    Promise.async {
      // Update PlaylistManager.currentPlaylistId so getCurrentPlaylistId() returns correctly
      _ = self.playlistManager.loadPlaylist(playlistId: playlistId)
      await self.core.loadPlaylist(playlistId: playlistId)
    }
  }

  func getCurrentPlaylistId() throws -> Variant_NullType_String {
    if let id = playlistManager.getCurrentPlaylistId() {
      return Variant_NullType_String.second(id)
    }
    return Variant_NullType_String.first(NullType.null)
  }

  // MARK: - Events (per-instance listener storage)

  func onPlaylistsChanged(callback: @escaping (_ playlists: [Playlist], _ operation: QueueOperation?) -> Void) throws {
    let remover = playlistManager.addPlaylistsChangeListener { playlists, operation in
      callback(playlists.map { $0.toGeneratedPlaylist() }, operation)
    }
    playlistsChangeRemover = remover
  }

  func onPlaylistChanged(callback: @escaping (_ playlistId: String, _ playlist: Playlist, _ operation: QueueOperation?) -> Void) throws {
    let allPlaylists = playlistManager.getAllPlaylists()
    for playlist in allPlaylists {
      let remover = playlistManager.addPlaylistChangeListener(playlistId: playlist.id) { updated, operation in
        callback(updated.id, updated.toGeneratedPlaylist(), operation)
      }
      playlistChangeRemovers.append(remover)
    }
  }

  // MARK: - Cleanup

  deinit {
    playlistsChangeRemover?()
    playlistChangeRemovers.forEach { $0() }
  }
}
