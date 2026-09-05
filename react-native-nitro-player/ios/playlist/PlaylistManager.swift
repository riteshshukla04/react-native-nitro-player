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
  private var anyPlaylistListeners: [(String, (PlaylistModel, QueueOperation?) -> Void)] = []
  // Backing store must only be touched inside `queue`; every current use of the
  // computed property is outside a queue.sync block, so the accessors can sync.
  private var _currentPlaylistId: String?
  private var currentPlaylistId: String? {
    get { queue.sync { _currentPlaylistId } }
    set { queue.sync { _currentPlaylistId = newValue } }
  }
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
    let removed = queue.sync { () -> Bool in
      guard playlists.removeValue(forKey: playlistId) != nil else { return false }
      if _currentPlaylistId == playlistId {
        _currentPlaylistId = nil
      }
      playlistListeners.removeValue(forKey: playlistId)
      return true
    }

    if removed {
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
    // Single sync: a separate fetch-then-store loses one of two concurrent edits
    let updated = queue.sync { () -> Bool in
      guard let playlist = playlists[playlistId] else { return false }
      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: name ?? playlist.name,
        description: description ?? playlist.description,
        artwork: artwork ?? playlist.artwork,
        tracks: playlist.tracks
      )
      return true
    }
    guard updated else { return false }

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
    let added = queue.sync { () -> Bool in
      guard let playlist = playlists[playlistId] else { return false }
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
      return true
    }
    guard added else { return false }

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
    let added = queue.sync { () -> Bool in
      guard let playlist = playlists[playlistId] else { return false }
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
      return true
    }
    guard added else { return false }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .add)

    // Update TrackPlayerCore if this is the current playlist
    if currentPlaylistId == playlistId {
      TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
      TrackPlayerCore.shared.checkUpcomingTracksForUrls(lookahead: TrackPlayerCore.shared.lookaheadCount)
    }

    return true
  }

  /**
   * Remove a track from a playlist
   */
  func removeTrackFromPlaylist(playlistId: String, trackId: String) -> Bool {
    let removed = queue.sync { () -> Bool in
      guard let playlist = playlists[playlistId] else { return false }
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
    let reordered = queue.sync { () -> Bool in
      guard let playlist = playlists[playlistId] else { return false }
      var tracks = playlist.tracks
      guard let oldIndex = tracks.firstIndex(where: { $0.id == trackId }),
        newIndex >= 0 && newIndex < tracks.count
      else {
        return false
      }
      let track = tracks.remove(at: oldIndex)
      tracks.insert(track, at: newIndex)

      playlists[playlistId] = PlaylistModel(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        artwork: playlist.artwork,
        tracks: tracks
      )
      return true
    }
    guard reordered else { return false }

    scheduleSave()
    notifyPlaylistChanged(playlistId, .update)

    // Update TrackPlayerCore if this is the current playlist
    if currentPlaylistId == playlistId {
      TrackPlayerCore.shared.updatePlaylist(playlistId: playlistId)
    }

    return true
  }

  /// Removed count; nil when the playlist does not exist. Unknown ids are ignored.
  func removeTracksFromPlaylist(playlistId: String, trackIds: [String]) -> Int? {
    let ids = Set(trackIds)
    let removed: Int? = queue.sync {
      guard let playlist = playlists[playlistId] else { return nil }
      let tracks = playlist.tracks.filter { !ids.contains($0.id) }
      let count = playlist.tracks.count - tracks.count
      if count > 0 {
        playlists[playlistId] = PlaylistModel(
          id: playlist.id, name: playlist.name, description: playlist.description,
          artwork: playlist.artwork, tracks: tracks)
      }
      return count
    }
    if let removed, removed > 0 {
      scheduleSave()
      notifyPlaylistChanged(playlistId, .remove)
    }
    return removed
  }

  /// Fisher-Yates; `firstTrackId` is pinned at index 0. Nil when the playlist does not exist.
  func shufflePlaylist(playlistId: String, firstTrackId: String?) -> Bool? {
    let changed: Bool? = queue.sync {
      guard let playlist = playlists[playlistId] else { return nil }
      var tracks = playlist.tracks
      let pinned = tracks.firstIndex { $0.id == firstTrackId }.map { tracks.remove(at: $0) }
      tracks.shuffle()
      if let pinned { tracks.insert(pinned, at: 0) }
      guard tracks.map(\.id) != playlist.tracks.map(\.id) else { return false }
      playlists[playlistId] = PlaylistModel(
        id: playlist.id, name: playlist.name, description: playlist.description,
        artwork: playlist.artwork, tracks: tracks)
      return true
    }
    if changed == true {
      scheduleSave()
      notifyPlaylistChanged(playlistId, .update)
    }
    return changed
  }

  /**
   * Load a playlist for playback (sets it as current)
   */
  func loadPlaylist(playlistId: String, index: Int? = nil) -> Bool {
    let isValid = queue.sync {
      guard let playlist = playlists[playlistId] else { return false }
      guard let index else { return true }
      return index >= 0 && index < playlist.tracks.count
    }
    guard isValid else {
      return false
    }

    currentPlaylistId = playlistId

    return true
  }

  /**
   * Update entire track objects across all playlists
   * Matches by track.id and replaces the entire track object
   * @param tracks Array of full TrackItem objects to update
   * @return Dictionary of playlistId -> count of tracks updated
   */
  func updateTracks(tracks: [TrackItem]) -> [String: Int] {
    let tracksMap = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    var affectedPlaylists: [String: Int] = [:]

    queue.sync {
      for (playlistId, playlist) in playlists {
        var updateCount = 0
        let newTracks = playlist.tracks.map { track -> TrackItem in
          if let updatedTrack = tracksMap[track.id] {
            updateCount += 1
            return updatedTrack
          }
          return track
        }

        if updateCount > 0 {
          affectedPlaylists[playlistId] = updateCount
          playlists[playlistId] = PlaylistModel(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            artwork: playlist.artwork,
            tracks: newTracks
          )
        }
      }
    }

    if !affectedPlaylists.isEmpty {
      scheduleSave()
      affectedPlaylists.keys.forEach { playlistId in
        notifyPlaylistChanged(playlistId, .update)
      }
      notifyPlaylistsChanged(.update)
    }

    return affectedPlaylists
  }

  /**
   * Get tracks by IDs from all playlists
   * @param trackIds Array of track IDs to fetch
   * @return Array of matching TrackItem objects
   */
  func getTracksById(trackIds: [String]) -> [TrackItem] {
    let trackIdSet = Set(trackIds)
    var foundTracks: [String: TrackItem] = [:]

    queue.sync {
      for playlist in playlists.values {
        for track in playlist.tracks {
          if trackIdSet.contains(track.id) && foundTracks[track.id] == nil {
            foundTracks[track.id] = track
          }
        }
      }
    }

    // Return in same order as requested
    return trackIds.compactMap { foundTracks[$0] }
  }

  /// Mirrors the core's current playlist; playSong bypasses loadPlaylist.
  func setCurrentPlaylistId(_ playlistId: String?) {
    currentPlaylistId = playlistId
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
    currentListeners.forEach { $0.1(allPlaylists, operation) }
  }

  /// Fires for ANY playlist, including ones created after registration.
  func addAnyPlaylistChangeListener(
    listener: @escaping (PlaylistModel, QueueOperation?) -> Void
  ) -> () -> Void {
    let listenerId = UUID().uuidString
    queue.sync { anyPlaylistListeners.append((listenerId, listener)) }
    return {
      self.queue.sync { self.anyPlaylistListeners.removeAll { $0.0 == listenerId } }
    }
  }

  private func notifyPlaylistChanged(_ playlistId: String, _ operation: QueueOperation?) {
    let result: (PlaylistModel, [(String, (PlaylistModel, QueueOperation?) -> Void)])? = queue.sync
    {
      guard let p = playlists[playlistId] else { return nil }
      return (p, (playlistListeners[playlistId] ?? []) + anyPlaylistListeners)
    }

    guard let (playlist, currentListeners) = result else { return }

    currentListeners.forEach { $0.1(playlist, operation) }
  }

  private func scheduleSave() {
    let work = DispatchWorkItem { [weak self] in self?.saveToFile() }
    queue.sync {
      saveDebounceWorkItem?.cancel()
      saveDebounceWorkItem = work
    }
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
        "currentPlaylistId": queue.sync { _currentPlaylistId } as Any,
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
