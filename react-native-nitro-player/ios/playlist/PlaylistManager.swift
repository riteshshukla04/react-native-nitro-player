//
//  PlaylistManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import Foundation
import NitroModules

/// Manages multiple playlists using AVPlayer's native playlist functionality
class PlaylistManager {
  private var playlists: [String: PlaylistModel] = [:]
  private var listeners: [(String, ([PlaylistModel], QueueOperation?) -> Void)] = []
  private var playlistListeners: [String: [(String, (PlaylistModel, QueueOperation?) -> Void)]] =
    [:]
  private var currentPlaylistId: String?
  private let queue = DispatchQueue(label: "com.margelo.nitro.nitroplayer.playlist")
  private var saveDebounceWorkItem: DispatchWorkItem?

  static let shared = PlaylistManager()

  private init() {
    loadFromFile()
  }

  /**
   * Create a new playlist
   */
  func createPlaylist(name: String, description: String? = nil, artwork: String? = nil) -> String {
    let id = UUID().uuidString
    let playlist = PlaylistModel(id: id, name: name, description: description, artwork: artwork)

    queue.sync {
      playlists[id] = playlist
    }

    scheduleSave()
    notifyPlaylistsChanged(.add)

    return id
  }

  /**
   * Delete a playlist
   */
  func deletePlaylist(playlistId: String) -> Bool {
    let removed = queue.sync {
      return playlists.removeValue(forKey: playlistId) != nil
    }

    if removed {
      if currentPlaylistId == playlistId {
        currentPlaylistId = nil
      }
      playlistListeners.removeValue(forKey: playlistId)
      scheduleSave()
      notifyPlaylistsChanged(.remove)
      return true
    }

    return false
  }

  /**
   * Update playlist metadata
   */
  func updatePlaylist(
    playlistId: String, name: String? = nil, description: String? = nil, artwork: String? = nil
  ) -> Bool {
    guard let playlist = queue.sync(execute: { playlists[playlistId] }) else {
      return false
    }

    queue.sync {
      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: name ?? playlist.name,
        description: description ?? playlist.description,
        artwork: artwork ?? playlist.artwork,
        tracks: playlist.tracks
      )
    }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .update)
    notifyPlaylistsChanged(.update)

    return true
  }

  /**
   * Get a playlist by ID
   */
  func getPlaylist(playlistId: String) -> PlaylistModel? {
    return queue.sync {
      return playlists[playlistId]
    }
  }

  /**
   * Get all playlists
   */
  func getAllPlaylists() -> [PlaylistModel] {
    return queue.sync {
      return Array(playlists.values)
    }
  }

  /**
   * Add a track to a playlist
   */
  func addTrackToPlaylist(playlistId: String, track: TrackItem, index: Int? = nil) -> Bool {
    guard let playlist = queue.sync(execute: { playlists[playlistId] }) else {
      return false
    }

    queue.sync {
      var tracks = playlist.tracks
      if let index = index, index >= 0 && index <= tracks.count {
        tracks.insert(track, at: index)
      } else {
        tracks.append(track)
      }
      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        artwork: playlist.artwork,
        tracks: tracks
      )
    }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .add)

    // Update TrackPlayerCore if this is the current playlist
    if currentPlaylistId == playlistId {
      TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
    }

    return true
  }

  /**
   * Add multiple tracks to a playlist at once
   */
  func addTracksToPlaylist(playlistId: String, tracks: [TrackItem], index: Int? = nil) -> Bool {
    guard let playlist = queue.sync(execute: { playlists[playlistId] }) else {
      return false
    }

    queue.sync {
      var currentTracks = playlist.tracks
      if let index = index, index >= 0 && index <= currentTracks.count {
        currentTracks.insert(contentsOf: tracks, at: index)
      } else {
        currentTracks.append(contentsOf: tracks)
      }
      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        artwork: playlist.artwork,
        tracks: currentTracks
      )
    }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .add)

    // Update TrackPlayerCore if this is the current playlist
    if currentPlaylistId == playlistId {
      TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
    }

    return true
  }

  /**
   * Remove a track from a playlist
   */
  func removeTrackFromPlaylist(playlistId: String, trackId: String) -> Bool {
    guard let playlist = queue.sync(execute: { playlists[playlistId] }) else {
      return false
    }

    let removed = queue.sync {
      var tracks = playlist.tracks
      let initialCount = tracks.count
      tracks.removeAll { $0.id == trackId }
      let wasRemoved = tracks.count < initialCount

      if wasRemoved {
        playlists[playlistId] = PlaylistModel(
          id: playlist.id,
          name: playlist.name,
          description: playlist.description,
          artwork: playlist.artwork,
          tracks: tracks
        )
      }

      return wasRemoved
    }

    if removed {
      scheduleSave()
      notifyPlaylistChanged(playlistId, .remove)

      // Update TrackPlayerCore if this is the current playlist
      if currentPlaylistId == playlistId {
        TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
      }
    }

    return removed
  }

  /**
   * Reorder a track in a playlist
   */
  func reorderTrackInPlaylist(playlistId: String, trackId: String, newIndex: Int) -> Bool {
    guard let playlist = queue.sync(execute: { playlists[playlistId] }) else {
      return false
    }

    let tracks = playlist.tracks
    guard let oldIndex = tracks.firstIndex(where: { $0.id == trackId }),
      newIndex >= 0 && newIndex < tracks.count
    else {
      return false
    }

    queue.sync {
      var reorderedTracks = tracks
      let track = reorderedTracks.remove(at: oldIndex)
      reorderedTracks.insert(track, at: newIndex)

      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        artwork: playlist.artwork,
        tracks: reorderedTracks
      )
    }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .update)

    // Update TrackPlayerCore if this is the current playlist
    if currentPlaylistId == playlistId {
      TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
    }

    return true
  }

  /**
   * Load a playlist for playback (sets it as current)
   */
  func loadPlaylist(playlistId: String) -> Bool {
    let exists = queue.sync { playlists[playlistId] != nil }
    guard exists else {
      return false
    }

    currentPlaylistId = playlistId

    // Update TrackPlayerCore
    TrackPlayerCore.shared.loadPlaylist(playlistId: playlistId)

    return true
  }

  /**
   * Get the current playlist ID
   */
  func getCurrentPlaylistId() -> String? {
    return currentPlaylistId
  }

  /**
   * Get the current playlist
   */
  func getCurrentPlaylist() -> PlaylistModel? {
    return currentPlaylistId.flatMap { id in queue.sync { playlists[id] } }
  }

  /**
   * Add a listener for playlist changes
   */
  func addPlaylistsChangeListener(listener: @escaping ([PlaylistModel], QueueOperation?) -> Void)
    -> () -> Void
  {
    let listenerId = UUID().uuidString
    queue.sync {
      listeners.append((listenerId, listener))
    }

    return {
      self.queue.sync {
        self.listeners.removeAll { $0.0 == listenerId }
      }
    }
  }

  /**
   * Add a listener for a specific playlist changes
   */
  func addPlaylistChangeListener(
    playlistId: String, listener: @escaping (PlaylistModel, QueueOperation?) -> Void
  ) -> () -> Void {
    let listenerId = UUID().uuidString
    queue.sync {
      if playlistListeners[playlistId] == nil {
        playlistListeners[playlistId] = []
      }
      playlistListeners[playlistId]?.append((listenerId, listener))
    }

    return {
      self.queue.sync {
        self.playlistListeners[playlistId]?.removeAll { $0.0 == listenerId }
      }
    }
  }

  private func notifyPlaylistsChanged(_ operation: QueueOperation?) {
    let (allPlaylists, currentListeners) = queue.sync {
      (Array(playlists.values), listeners)
    }
    DispatchQueue.main.async {
      currentListeners.forEach { $0.1(allPlaylists, operation) }
    }
  }

  private func notifyPlaylistChanged(_ playlistId: String, _ operation: QueueOperation?) {
    let result: (PlaylistModel, [(String, (PlaylistModel, QueueOperation?) -> Void)])? = queue.sync
    {
      guard let p = playlists[playlistId] else { return nil }
      return (p, playlistListeners[playlistId] ?? [])
    }

    guard let (playlist, currentListeners) = result else { return }

    DispatchQueue.main.async {
      currentListeners.forEach { $0.1(playlist, operation) }
    }
  }

  private func scheduleSave() {
    saveDebounceWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.saveToFile() }
    saveDebounceWorkItem = work
    // Use global background queue — saveToFile calls queue.sync internally,
    // which would deadlock if scheduled on queue itself.
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  // MARK: - Persistence

  private func saveToFile() {
    do {
      let playlistsArray = queue.sync { Array(playlists.values) }
      let playlistsData = playlistsArray.map { playlist -> [String: Any] in
        return [
          "id": playlist.id,
          "name": playlist.name,
          "description": playlist.description ?? "",
          "artwork": playlist.artwork ?? "",
          "tracks": playlist.tracks.map { track -> [String: Any] in
            var trackDict: [String: Any] = [
              "id": track.id,
              "title": track.title,
              "artist": track.artist,
              "album": track.album,
              "duration": track.duration,
              "url": track.url,
            ]
            if let artwork = track.artwork, case .second(let artworkUrl) = artwork {
              trackDict["artwork"] = artworkUrl
            } else {
              trackDict["artwork"] = ""
            }
            if let extraPayload = track.extraPayload {
              trackDict["extraPayload"] = extraPayload.toDictionary()
            }
            return trackDict
          },
        ]
      }
      let wrapper: [String: Any] = [
        "playlists": playlistsData,
        "currentPlaylistId": currentPlaylistId as Any,
      ]
      let data = try JSONSerialization.data(withJSONObject: wrapper, options: [])
      try NitroPlayerStorage.write(filename: "playlists.json", data: data)
    } catch {
      NitroPlayerLogger.log("PlaylistManager", "❌ Error saving playlists - \(error)")
    }
  }

  private func loadFromFile() {
    // 1. Try new JSON file (post-migration)
    if let data = NitroPlayerStorage.read(filename: "playlists.json") {
      do {
        if let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          let playlistsDict = wrapper["playlists"] as? [[String: Any]] ?? []
          parsePlaylists(from: playlistsDict)
          currentPlaylistId = wrapper["currentPlaylistId"] as? String
        }
      } catch {
        NitroPlayerLogger.log("PlaylistManager", "❌ Error loading playlists - \(error)")
      }
      return
    }

    // 2. Migrate from UserDefaults (one-time, existing installs)
    if let data = UserDefaults.standard.data(forKey: "NitroPlayerPlaylists") {
      do {
        let playlistsDict = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        parsePlaylists(from: playlistsDict)
        currentPlaylistId = UserDefaults.standard.string(forKey: "NitroPlayerCurrentPlaylistId")
        // Remove old keys to free UserDefaults space
        UserDefaults.standard.removeObject(forKey: "NitroPlayerPlaylists")
        UserDefaults.standard.removeObject(forKey: "NitroPlayerCurrentPlaylistId")
        // Persist in new format
        saveToFile()
      } catch {
        NitroPlayerLogger.log("PlaylistManager", "❌ Error migrating playlists - \(error)")
      }
      return
    }

    // 3. Fresh install — nothing to load
  }

  private func parsePlaylists(from playlistsDict: [[String: Any]]) {
    queue.sync {
      playlists.removeAll()
      for playlistDict in playlistsDict {
        guard let id = playlistDict["id"] as? String,
          let name = playlistDict["name"] as? String
        else {
          continue
        }

        let description = playlistDict["description"] as? String
        let artwork = playlistDict["artwork"] as? String
        let tracksArray = playlistDict["tracks"] as? [[String: Any]] ?? []

        let tracks = tracksArray.compactMap { trackDict -> TrackItem? in
          guard let id = trackDict["id"] as? String,
            let title = trackDict["title"] as? String,
            let artist = trackDict["artist"] as? String,
            let album = trackDict["album"] as? String,
            let duration = trackDict["duration"] as? Double,
            let url = trackDict["url"] as? String
          else {
            return nil
          }

          let artworkString = trackDict["artwork"] as? String
          let artwork = artworkString.flatMap {
            !$0.isEmpty ? Variant_NullType_String.second($0) : nil
          }

          var extraPayload: AnyMap? = nil
          if let extraPayloadDict = trackDict["extraPayload"] as? [String: Any] {
            extraPayload = AnyMap()
            for (key, value) in extraPayloadDict {
              if let stringValue = value as? String {
                extraPayload?.setString(key: key, value: stringValue)
              } else if let doubleValue = value as? Double {
                extraPayload?.setDouble(key: key, value: doubleValue)
              } else if let intValue = value as? Int {
                extraPayload?.setDouble(key: key, value: Double(intValue))
              } else if let boolValue = value as? Bool {
                extraPayload?.setBoolean(key: key, value: boolValue)
              }
            }
          }

          return TrackItem(
            id: id,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            url: url,
            artwork: artwork,
            extraPayload: extraPayload
          )
        }

        playlists[id] = PlaylistModel(
          id: id,
          name: name,
          description: description,
          artwork: artwork,
          tracks: tracks
        )
      }
    }
  }
}
