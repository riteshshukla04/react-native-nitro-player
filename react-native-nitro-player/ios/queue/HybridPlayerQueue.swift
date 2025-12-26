//
//  HybridPlayerQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 24/11/25.
//

import NitroModules

final class HybridPlayerQueue: HybridPlayerQueueSpec {
  private let playlistManager = PlaylistManager.shared
  private var playlistsChangeListener: (() -> Void)?
  private var playlistChangeListeners: [String: () -> Void] = [:]

  func createPlaylist(name: String, description: String?, artwork: String?) throws -> String {
    return playlistManager.createPlaylist(name: name, description: description, artwork: artwork)
  }

  func deletePlaylist(playlistId: String) throws {
    _ = playlistManager.deletePlaylist(playlistId: playlistId)
  }

  func updatePlaylist(playlistId: String, name: String?, description: String?, artwork: String?)
    throws
  {
    _ = playlistManager.updatePlaylist(
      playlistId: playlistId, name: name, description: description, artwork: artwork)
  }

  func getPlaylist(playlistId: String) throws -> Variant_NullType_Playlist {
    if let playlist = playlistManager.getPlaylist(playlistId: playlistId) {
      return Variant_NullType_Playlist.second(playlist.toGeneratedPlaylist())
    } else {
      return Variant_NullType_Playlist.first(NullType.null)
    }
  }

  func getAllPlaylists() throws -> [Playlist] {
    return playlistManager.getAllPlaylists().map { $0.toGeneratedPlaylist() }
  }

  func addTrackToPlaylist(playlistId: String, track: TrackItem, index: Double?) throws {
    let insertIndex = index.map { Int($0) }
    _ = playlistManager.addTrackToPlaylist(playlistId: playlistId, track: track, index: insertIndex)
  }

  func addTracksToPlaylist(playlistId: String, tracks: [TrackItem], index: Double?) throws {
    let insertIndex = index.map { Int($0) }
    _ = playlistManager.addTracksToPlaylist(
      playlistId: playlistId, tracks: tracks, index: insertIndex)
  }

  func removeTrackFromPlaylist(playlistId: String, trackId: String) throws {
    _ = playlistManager.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
  }

  func reorderTrackInPlaylist(playlistId: String, trackId: String, newIndex: Double) throws {
    _ = playlistManager.reorderTrackInPlaylist(
      playlistId: playlistId, trackId: trackId, newIndex: Int(newIndex))
  }

  func loadPlaylist(playlistId: String) throws {
    _ = playlistManager.loadPlaylist(playlistId: playlistId)
  }

  func getCurrentPlaylistId() throws -> Variant_NullType_String {
    if let playlistId = playlistManager.getCurrentPlaylistId() {
      return Variant_NullType_String.second(playlistId)
    } else {
      return Variant_NullType_String.first(NullType.null)
    }
  }

  func onPlaylistsChanged(callback: @escaping ([Playlist], QueueOperation?) -> Void) throws {
    // Remove previous listener if exists
    playlistsChangeListener?()

    // Add new listener
    playlistsChangeListener = playlistManager.addPlaylistsChangeListener { playlists, operation in
      callback(playlists.map { $0.toGeneratedPlaylist() }, operation)
    }
  }

  func onPlaylistChanged(callback: @escaping (String, Playlist, QueueOperation?) -> Void) throws {
    // Listen to all playlists
    let allPlaylists = playlistManager.getAllPlaylists()
    for playlist in allPlaylists {
      let removeListener = playlistManager.addPlaylistChangeListener(playlistId: playlist.id) {
        updatedPlaylist, operation in
        callback(updatedPlaylist.id, updatedPlaylist.toGeneratedPlaylist(), operation)
      }
      playlistChangeListeners[playlist.id] = removeListener
    }
  }
}
