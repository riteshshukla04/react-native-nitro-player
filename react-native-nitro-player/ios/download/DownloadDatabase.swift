//
//  DownloadDatabase.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 2026-01-23..
//

import Foundation
import NitroModules

/// Manages persistence of downloaded track metadata using file storage
final class DownloadDatabase {

  // MARK: - Singleton

  static let shared = DownloadDatabase()

  // MARK: - Legacy UserDefaults Keys (migration only)

  private static let legacyDownloadedTracksKey = "NitroPlayerDownloadedTracks"
  private static let legacyPlaylistTracksKey = "NitroPlayerPlaylistTracks"

  // MARK: - Properties

  private var downloadedTracks: [String: DownloadedTrackRecord] = [:]
  private var playlistTracks: [String: Set<String>] = [:]  // playlistId -> Set of trackIds

  private let queue = DispatchQueue(
    label: "com.nitroplayer.downloadDatabase", attributes: .concurrent)

  // MARK: - Initialization

  private init() {
    loadFromDisk()
  }

  // MARK: - Save Operations

  func saveDownloadedTrack(_ track: DownloadedTrack, playlistId: String?) {
    queue.async(flags: .barrier) {
      let record = DownloadedTrackRecord(
        trackId: track.trackId,
        originalTrack: self.trackItemToRecord(track.originalTrack),
        localPath: URL(fileURLWithPath: track.localPath).lastPathComponent,
        localArtworkPath: self.variantToString(track.localArtworkPath),
        downloadedAt: track.downloadedAt,
        fileSize: track.fileSize,
        storageLocation: track.storageLocation == .private ? "private" : "public"
      )

      self.downloadedTracks[track.trackId] = record

      // Associate with playlist if provided
      if let playlistId = playlistId {
        if self.playlistTracks[playlistId] == nil {
          self.playlistTracks[playlistId] = Set()
        }
        self.playlistTracks[playlistId]?.insert(track.trackId)
      }

      self.saveToDisk()
    }
  }

  // MARK: - Query Operations

  func isTrackDownloaded(trackId: String) -> Bool {
    return queue.sync {
      guard let record = downloadedTracks[trackId] else {
        NitroPlayerLogger.log("DownloadDatabase", "🔍 Track \(trackId) NOT found in database")
        return false
      }
      // Verify file still exists
      let absolutePath = resolveAbsolutePath(for: record)
      let exists = FileManager.default.fileExists(atPath: absolutePath)
      if exists {
        NitroPlayerLogger.log("DownloadDatabase", "✅ Track \(trackId) IS downloaded at \(absolutePath)")
      } else {
        NitroPlayerLogger.log("DownloadDatabase", "❌ Track \(trackId) record exists but file NOT found at \(absolutePath)")
      }
      return exists
    }
  }

  func isPlaylistDownloaded(playlistId: String) -> Bool {
    return queue.sync {
      guard let trackIds = playlistTracks[playlistId], !trackIds.isEmpty else { return false }

      // Get original playlist to check all tracks
      guard let playlistModel = PlaylistManager.shared.getPlaylist(playlistId: playlistId) else {
        return false
      }

      // Check if all tracks are downloaded
      for track in playlistModel.tracks {
        if !isTrackDownloaded(trackId: track.id) {
          return false
        }
      }

      return true
    }
  }

  func isPlaylistPartiallyDownloaded(playlistId: String) -> Bool {
    return queue.sync {
      guard let trackIds = playlistTracks[playlistId], !trackIds.isEmpty else { return false }

      // Check if at least one track is downloaded
      for trackId in trackIds {
        if isTrackDownloaded(trackId: trackId) {
          return true
        }
      }

      return false
    }
  }

  func getDownloadedTrack(trackId: String) -> DownloadedTrack? {
    return queue.sync {
      NitroPlayerLogger.log("DownloadDatabase", "🔍 DownloadDatabase.getDownloadedTrack() for trackId: \(trackId)")
      NitroPlayerLogger.log("DownloadDatabase", "   Total records in memory: \(downloadedTracks.count)")
      NitroPlayerLogger.log("DownloadDatabase", "   Available trackIds: \(Array(downloadedTracks.keys))")

      guard let record = downloadedTracks[trackId] else {
        NitroPlayerLogger.log("DownloadDatabase", "   ❌ No record found for trackId: \(trackId)")
        return nil
      }

      let absolutePath = resolveAbsolutePath(for: record)
      NitroPlayerLogger.log("DownloadDatabase", "   Found record, checking file at: \(absolutePath)")

      // Verify file still exists
      guard FileManager.default.fileExists(atPath: absolutePath) else {
        NitroPlayerLogger.log("DownloadDatabase", "   ❌ File does NOT exist, cleaning up record")
        // File was deleted externally, clean up record
        queue.async(flags: .barrier) {
          self.downloadedTracks.removeValue(forKey: trackId)
          self.saveToDisk()
        }
        return nil
      }

      NitroPlayerLogger.log("DownloadDatabase", "   ✅ File exists, returning track")
      return recordToDownloadedTrack(record)
    }
  }

  func getAllDownloadedTracks() -> [DownloadedTrack] {
    return queue.sync {
      NitroPlayerLogger.log("DownloadDatabase", "🎯 getAllDownloadedTracks called, have \(downloadedTracks.count) records")

      var validTracks: [DownloadedTrack] = []
      var invalidTrackIds: [String] = []

      for (trackId, record) in downloadedTracks {
        let absolutePath = resolveAbsolutePath(for: record)
        NitroPlayerLogger.log("DownloadDatabase", "   Checking track \(trackId) at path: \(absolutePath)")
        if FileManager.default.fileExists(atPath: absolutePath) {
          NitroPlayerLogger.log("DownloadDatabase", "   ✅ File exists")
          validTracks.append(recordToDownloadedTrack(record))
        } else {
          NitroPlayerLogger.log("DownloadDatabase", "   ❌ File NOT found")
          invalidTrackIds.append(trackId)
        }
      }

      // Clean up invalid records
      if !invalidTrackIds.isEmpty {
        NitroPlayerLogger.log("DownloadDatabase", "   Cleaning up \(invalidTrackIds.count) invalid records")
        queue.async(flags: .barrier) {
          for trackId in invalidTrackIds {
            self.downloadedTracks.removeValue(forKey: trackId)
          }
          self.saveToDisk()
        }
      }

      NitroPlayerLogger.log("DownloadDatabase", "🎯 Returning \(validTracks.count) valid tracks")
      return validTracks
    }
  }

  func getDownloadedPlaylist(playlistId: String) -> DownloadedPlaylist? {
    return queue.sync { () -> DownloadedPlaylist? in
      guard let trackIds = playlistTracks[playlistId], !trackIds.isEmpty else { return nil }
      guard let playlistModel = PlaylistManager.shared.getPlaylist(playlistId: playlistId) else {
        return nil
      }

      var downloadedTracks: [DownloadedTrack] = []
      var totalSize: Double = 0

      for trackId in trackIds {
        if let track = getDownloadedTrack(trackId: trackId) {
          downloadedTracks.append(track)
          totalSize += track.fileSize
        }
      }

      guard !downloadedTracks.isEmpty else { return nil }

      let isComplete = downloadedTracks.count == playlistModel.tracks.count

      return DownloadedPlaylist(
        playlistId: playlistId,
        originalPlaylist: playlistModel.toGeneratedPlaylist(),
        downloadedTracks: downloadedTracks,
        totalSize: totalSize,
        downloadedAt: downloadedTracks.map { $0.downloadedAt }.min()
          ?? Date().timeIntervalSince1970,
        isComplete: isComplete
      )
    }
  }

  func getAllDownloadedPlaylists() -> [DownloadedPlaylist] {
    return queue.sync {
      var playlists: [DownloadedPlaylist] = []

      for playlistId in playlistTracks.keys {
        if let playlist = getDownloadedPlaylist(playlistId: playlistId) {
          playlists.append(playlist)
        }
      }

      return playlists
    }
  }

  // MARK: - Sync Operations

  /// Validates all downloads and removes records for missing files
  /// Returns the number of orphaned records that were cleaned up
  func syncDownloads() -> Int {
    return queue.sync(flags: .barrier) {
      NitroPlayerLogger.log("DownloadDatabase", "🔄 syncDownloads called")

      var removedCount = 0
      var trackIdsToRemove: [String] = []

      for (trackId, record) in downloadedTracks {
        let absolutePath = resolveAbsolutePath(for: record)
        if !FileManager.default.fileExists(atPath: absolutePath) {
          NitroPlayerLogger.log("DownloadDatabase", "   ❌ Missing file for track \(trackId): \(absolutePath)")
          trackIdsToRemove.append(trackId)
        }
      }

      // Remove invalid records
      for trackId in trackIdsToRemove {
        downloadedTracks.removeValue(forKey: trackId)

        // Also remove from playlist associations
        for (playlistId, var trackIds) in playlistTracks {
          if trackIds.remove(trackId) != nil {
            if trackIds.isEmpty {
              playlistTracks.removeValue(forKey: playlistId)
            } else {
              playlistTracks[playlistId] = trackIds
            }
          }
        }

        removedCount += 1
      }

      if removedCount > 0 {
        saveToDisk()
        NitroPlayerLogger.log("DownloadDatabase", "   ✅ Cleaned up \(removedCount) orphaned records")
      } else {
        NitroPlayerLogger.log("DownloadDatabase", "   ✅ All downloads are valid")
      }

      return removedCount
    }
  }

  // MARK: - Delete Operations

  func deleteDownloadedTrack(trackId: String) {
    queue.async(flags: .barrier) {
      guard let record = self.downloadedTracks[trackId] else { return }

      // Delete the file
      DownloadFileManager.shared.deleteFile(at: self.resolveAbsolutePath(for: record))

      // Delete artwork if exists
      if let artworkPath = record.localArtworkPath {
        DownloadFileManager.shared.deleteFile(at: artworkPath)
      }

      // Remove from records
      self.downloadedTracks.removeValue(forKey: trackId)

      // Remove from all playlist associations
      for (playlistId, var trackIds) in self.playlistTracks {
        trackIds.remove(trackId)
        if trackIds.isEmpty {
          self.playlistTracks.removeValue(forKey: playlistId)
        } else {
          self.playlistTracks[playlistId] = trackIds
        }
      }

      self.saveToDisk()
    }
  }

  func deleteDownloadedPlaylist(playlistId: String) {
    queue.async(flags: .barrier) {
      guard let trackIds = self.playlistTracks[playlistId] else { return }

      // Delete all tracks in the playlist
      for trackId in trackIds {
        if let record = self.downloadedTracks[trackId] {
          DownloadFileManager.shared.deleteFile(at: self.resolveAbsolutePath(for: record))
          if let artworkPath = record.localArtworkPath {
            DownloadFileManager.shared.deleteFile(at: artworkPath)
          }
          self.downloadedTracks.removeValue(forKey: trackId)
        }
      }

      // Remove playlist association
      self.playlistTracks.removeValue(forKey: playlistId)

      self.saveToDisk()
    }
  }

  func deleteAllDownloads() {
    queue.async(flags: .barrier) {
      // Delete all files
      for record in self.downloadedTracks.values {
        DownloadFileManager.shared.deleteFile(at: self.resolveAbsolutePath(for: record))
        if let artworkPath = record.localArtworkPath {
          DownloadFileManager.shared.deleteFile(at: artworkPath)
        }
      }

      // Clear all records
      self.downloadedTracks.removeAll()
      self.playlistTracks.removeAll()

      self.saveToDisk()
    }
  }

  // MARK: - Persistence

  private func saveToDisk() {
    do {
      let tracksData = try JSONEncoder().encode(downloadedTracks)
      // Convert Set to Array for encoding
      let playlistTracksDict = playlistTracks.mapValues { Array($0) }
      let playlistData = try JSONEncoder().encode(playlistTracksDict)

      // Combine both into a single JSON wrapper object
      guard let tracksJson = try JSONSerialization.jsonObject(with: tracksData) as? [String: Any],
            let playlistJson = try JSONSerialization.jsonObject(with: playlistData) as? [String: Any]
      else { return }

      let wrapper: [String: Any] = [
        "downloadedTracks": tracksJson,
        "playlistTracks": playlistJson,
      ]
      let data = try JSONSerialization.data(withJSONObject: wrapper, options: [])
      try NitroPlayerStorage.write(filename: "downloads.json", data: data)
    } catch {
      NitroPlayerLogger.log("DownloadDatabase", "Failed to save to disk: \(error)")
    }
  }

  private func loadFromDisk() {
    NitroPlayerLogger.log("DownloadDatabase", "\n" + String(repeating: "📀", count: 40))
    NitroPlayerLogger.log("DownloadDatabase", "📀 LOADING FROM DISK")
    NitroPlayerLogger.log("DownloadDatabase", String(repeating: "📀", count: 40))

    // 1. Try new JSON file (post-migration)
    if let data = NitroPlayerStorage.read(filename: "downloads.json") {
      do {
        if let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          if let tracksObj = wrapper["downloadedTracks"] as? [String: Any] {
            let tracksData = try JSONSerialization.data(withJSONObject: tracksObj)
            self.downloadedTracks = try JSONDecoder().decode(
              [String: DownloadedTrackRecord].self, from: tracksData)
            NitroPlayerLogger.log("DownloadDatabase", "✅ Loaded \(self.downloadedTracks.count) tracks from file")
          }
          if let playlistObj = wrapper["playlistTracks"] as? [String: Any] {
            let playlistData = try JSONSerialization.data(withJSONObject: playlistObj)
            let playlistTracksDict = try JSONDecoder().decode(
              [String: [String]].self, from: playlistData)
            self.playlistTracks = playlistTracksDict.mapValues { Set($0) }
            NitroPlayerLogger.log("DownloadDatabase", "✅ Loaded \(self.playlistTracks.count) playlist associations from file")
          }
        }
      } catch {
        NitroPlayerLogger.log("DownloadDatabase", "❌ Failed to load from file: \(error)")
      }
      NitroPlayerLogger.log("DownloadDatabase", String(repeating: "📀", count: 40) + "\n")
      return
    }

    // 2. Migrate from UserDefaults (one-time, existing installs)
    var didMigrate = false

    if let tracksData = UserDefaults.standard.data(forKey: Self.legacyDownloadedTracksKey) {
      do {
        self.downloadedTracks = try JSONDecoder().decode(
          [String: DownloadedTrackRecord].self, from: tracksData)
        NitroPlayerLogger.log("DownloadDatabase", "✅ Migrated \(self.downloadedTracks.count) tracks from UserDefaults")

        // Migrate absolute paths → filenames (pre-existing migration)
        var needsPathMigration = false
        for (trackId, record) in self.downloadedTracks {
          if record.localPath.contains("/") {
            let filename = URL(fileURLWithPath: record.localPath).lastPathComponent
            self.downloadedTracks[trackId] = DownloadedTrackRecord(
              trackId: record.trackId,
              originalTrack: record.originalTrack,
              localPath: filename,
              localArtworkPath: record.localArtworkPath,
              downloadedAt: record.downloadedAt,
              fileSize: record.fileSize,
              storageLocation: record.storageLocation
            )
            needsPathMigration = true
          }
        }
        if needsPathMigration {
          NitroPlayerLogger.log("DownloadDatabase", "✅ Migrated absolute paths to filenames")
        }

        UserDefaults.standard.removeObject(forKey: Self.legacyDownloadedTracksKey)
        didMigrate = true
      } catch {
        NitroPlayerLogger.log("DownloadDatabase", "❌ Failed to migrate tracks from UserDefaults: \(error)")
      }
    } else {
      NitroPlayerLogger.log("DownloadDatabase", "⚠️  No saved tracks found in UserDefaults")
    }

    if let playlistData = UserDefaults.standard.data(forKey: Self.legacyPlaylistTracksKey) {
      do {
        let playlistTracksDict = try JSONDecoder().decode(
          [String: [String]].self, from: playlistData)
        self.playlistTracks = playlistTracksDict.mapValues { Set($0) }
        NitroPlayerLogger.log("DownloadDatabase", "✅ Migrated \(self.playlistTracks.count) playlist associations from UserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.legacyPlaylistTracksKey)
        didMigrate = true
      } catch {
        NitroPlayerLogger.log("DownloadDatabase", "❌ Failed to migrate playlist tracks from UserDefaults: \(error)")
      }
    } else {
      NitroPlayerLogger.log("DownloadDatabase", "⚠️  No playlist associations found in UserDefaults")
    }

    if didMigrate {
      // Persist migrated data in new file format
      saveToDisk()
    }

    NitroPlayerLogger.log("DownloadDatabase", String(repeating: "📀", count: 40) + "\n")
  }

  // MARK: - Conversion Helpers

  private func resolveAbsolutePath(for record: DownloadedTrackRecord) -> String {
    let location: StorageLocation = record.storageLocation == "private" ? .private : .public
    return DownloadFileManager.shared.absolutePath(forFilename: record.localPath, storageLocation: location)
  }

  /// Convert Variant_NullType_String? to String?
  private func variantToString(_ variant: Variant_NullType_String?) -> String? {
    guard let variant = variant else { return nil }
    switch variant {
    case .first(_):
      return nil
    case .second(let value):
      return value
    }
  }

  /// Convert String? to Variant_NullType_String?
  private func stringToVariant(_ string: String?) -> Variant_NullType_String? {
    guard let string = string else { return nil }
    return .second(string)
  }

  private func trackItemToRecord(_ track: TrackItem) -> TrackItemRecord {
    var extraPayloadDict: [String: Any]? = nil
    if let extraPayload = track.extraPayload {
      extraPayloadDict = extraPayload.toDictionary()
    }

    return TrackItemRecord(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      url: track.url,
      artwork: variantToString(track.artwork),
      extraPayload: extraPayloadDict
    )
  }

  private func recordToTrackItem(_ record: TrackItemRecord) -> TrackItem {
    var extraPayload: AnyMap? = nil
    if let extraPayloadDict = record.extraPayload {
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
      id: record.id,
      title: record.title,
      artist: record.artist,
      album: record.album,
      duration: record.duration,
      url: record.url,
      artwork: stringToVariant(record.artwork),
      extraPayload: extraPayload
    )
  }

  private func recordToDownloadedTrack(_ record: DownloadedTrackRecord) -> DownloadedTrack {
    return DownloadedTrack(
      trackId: record.trackId,
      originalTrack: recordToTrackItem(record.originalTrack),
      localPath: resolveAbsolutePath(for: record),
      localArtworkPath: stringToVariant(record.localArtworkPath),
      downloadedAt: record.downloadedAt,
      fileSize: record.fileSize,
      storageLocation: record.storageLocation == "private" ? .private : .public
    )
  }
}

// MARK: - Codable Records

private struct DownloadedTrackRecord: Codable {
  let trackId: String
  let originalTrack: TrackItemRecord
  let localPath: String
  let localArtworkPath: String?
  let downloadedAt: Double
  let fileSize: Double
  let storageLocation: String
}

private struct TrackItemRecord: Codable {
  let id: String
  let title: String
  let artist: String
  let album: String
  let duration: Double
  let url: String
  let artwork: String?
  let extraPayload: [String: Any]?

  enum CodingKeys: String, CodingKey {
    case id, title, artist, album, duration, url, artwork, extraPayload
  }

  // Manual encoding to handle [String: Any]
  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(artist, forKey: .artist)
    try container.encode(album, forKey: .album)
    try container.encode(duration, forKey: .duration)
    try container.encode(url, forKey: .url)
    try container.encodeIfPresent(artwork, forKey: .artwork)

    if let extraPayload = extraPayload {
      let jsonData = try JSONSerialization.data(withJSONObject: extraPayload)
      if let jsonString = String(data: jsonData, encoding: .utf8) {
        try container.encode(jsonString, forKey: .extraPayload)
      }
    }
  }

  // Manual decoding to handle [String: Any]
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    artist = try container.decode(String.self, forKey: .artist)
    album = try container.decode(String.self, forKey: .album)
    duration = try container.decode(Double.self, forKey: .duration)
    url = try container.decode(String.self, forKey: .url)
    artwork = try container.decodeIfPresent(String.self, forKey: .artwork)

    if let jsonString = try? container.decodeIfPresent(String.self, forKey: .extraPayload),
       let jsonData = jsonString.data(using: .utf8) {
      extraPayload = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    } else {
      extraPayload = nil
    }
  }

  // Initializer for code creation
  init(id: String, title: String, artist: String, album: String, duration: Double, url: String, artwork: String?, extraPayload: [String: Any]?) {
    self.id = id
    self.title = title
    self.artist = artist
    self.album = album
    self.duration = duration
    self.url = url
    self.artwork = artwork
    self.extraPayload = extraPayload
  }
}
