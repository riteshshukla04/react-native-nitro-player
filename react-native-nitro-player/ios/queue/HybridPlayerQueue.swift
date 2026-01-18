//
//  HybridPlayerQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 24/11/25.
//

import NitroModules

final class HybridPlayerQueue: HybridPlayerQueueSpec {
  private let playlistManager = PlaylistManager.shared

  // Static storage for callbacks to ensure they persist across HybridPlayerQueue instances
  private static var playlistsChangeCallbacks: [([Playlist], QueueOperation?) -> Void] = []
  private static var playlistChangeCallbacks: [(String, Playlist, QueueOperation?) -> Void] = []
  private static var isPlaylistsListenerRegistered = false
  private static var playlistListenerIds: Set<String> = []

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
    // Store callback in static storage so it persists across HybridPlayerQueue instances
    HybridPlayerQueue.playlistsChangeCallbacks.append(callback)

    // Register a single listener with PlaylistManager that dispatches to all callbacks
    if !HybridPlayerQueue.isPlaylistsListenerRegistered {
      HybridPlayerQueue.isPlaylistsListenerRegistered = true
      _ = playlistManager.addPlaylistsChangeListener { playlists, operation in
        let generatedPlaylists = playlists.map { $0.toGeneratedPlaylist() }
        // Call all registered callbacks
        for cb in HybridPlayerQueue.playlistsChangeCallbacks {
          cb(generatedPlaylists, operation)
        }
      }
    }
  }

  func onPlaylistChanged(callback: @escaping (String, Playlist, QueueOperation?) -> Void) throws {
    // Store callback in static storage so it persists across HybridPlayerQueue instances
    HybridPlayerQueue.playlistChangeCallbacks.append(callback)

    // Register listeners for all existing playlists (only once per playlist)
    let allPlaylists = playlistManager.getAllPlaylists()
    for playlist in allPlaylists {
      if !HybridPlayerQueue.playlistListenerIds.contains(playlist.id) {
        HybridPlayerQueue.playlistListenerIds.insert(playlist.id)
        _ = playlistManager.addPlaylistChangeListener(playlistId: playlist.id) {
          updatedPlaylist, operation in
          let generatedPlaylist = updatedPlaylist.toGeneratedPlaylist()
          // Call all registered callbacks
          for cb in HybridPlayerQueue.playlistChangeCallbacks {
            cb(updatedPlaylist.id, generatedPlaylist, operation)
          }
        }
      }
    }
  }
}
