//
//  DownloadDatabase.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 2026-01-23..
//

import Foundation
import NitroModules

/// Manages persistence of downloaded track metadata using UserDefaults
final class DownloadDatabase {

  // MARK: - Singleton

  static let shared = DownloadDatabase()

  // MARK: - Constants

  private static let downloadedTracksKey = "NitroPlayerDownloadedTracks"
  private static let playlistTracksKey = "NitroPlayerPlaylistTracks"

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
        localPath: track.localPath,
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
        print("🔍 DownloadDatabase: Track \(trackId) NOT found in database")
        return false
      }
      // Verify file still exists
      let exists = FileManager.default.fileExists(atPath: record.localPath)
      if exists {
        print("✅ DownloadDatabase: Track \(trackId) IS downloaded at \(record.localPath)")
      } else {
        print(
          "❌ DownloadDatabase: Track \(trackId) record exists but file NOT found at \(record.localPath)"
        )
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
      print("🔍 DownloadDatabase.getDownloadedTrack() for trackId: \(trackId)")
      print("   Total records in memory: \(downloadedTracks.count)")
      print("   Available trackIds: \(Array(downloadedTracks.keys))")

      guard let record = downloadedTracks[trackId] else {
        print("   ❌ No record found for trackId: \(trackId)")
        return nil
      }

      print("   Found record, checking file at: \(record.localPath)")

      // Verify file still exists
      guard FileManager.default.fileExists(atPath: record.localPath) else {
        print("   ❌ File does NOT exist, cleaning up record")
        // File was deleted externally, clean up record
        queue.async(flags: .barrier) {
          self.downloadedTracks.removeValue(forKey: trackId)
          self.saveToDisk()
        }
        return nil
      }

      print("   ✅ File exists, returning track")
      return recordToDownloadedTrack(record)
    }
  }

  func getAllDownloadedTracks() -> [DownloadedTrack] {
    return queue.sync {
      print(
        "🎯 DownloadDatabase: getAllDownloadedTracks called, have \(downloadedTracks.count) records")

      var validTracks: [DownloadedTrack] = []
      var invalidTrackIds: [String] = []

      for (trackId, record) in downloadedTracks {
        print("   Checking track \(trackId) at path: \(record.localPath)")
        if FileManager.default.fileExists(atPath: record.localPath) {
          print("   ✅ File exists")
          validTracks.append(recordToDownloadedTrack(record))
        } else {
          print("   ❌ File NOT found")
          invalidTrackIds.append(trackId)
        }
      }

      // Clean up invalid records
      if !invalidTrackIds.isEmpty {
        print("   Cleaning up \(invalidTrackIds.count) invalid records")
        queue.async(flags: .barrier) {
          for trackId in invalidTrackIds {
            self.downloadedTracks.removeValue(forKey: trackId)
          }
          self.saveToDisk()
        }
      }

      print("🎯 DownloadDatabase: Returning \(validTracks.count) valid tracks")
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
      print("🔄 DownloadDatabase: syncDownloads called")

      var removedCount = 0
      var trackIdsToRemove: [String] = []

      for (trackId, record) in downloadedTracks {
        if !FileManager.default.fileExists(atPath: record.localPath) {
          print("   ❌ Missing file for track \(trackId): \(record.localPath)")
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
        print("   ✅ Cleaned up \(removedCount) orphaned records")
      } else {
        print("   ✅ All downloads are valid")
      }

      return removedCount
    }
  }

  // MARK: - Delete Operations

  func deleteDownloadedTrack(trackId: String) {
    queue.async(flags: .barrier) {
      guard let record = self.downloadedTracks[trackId] else { return }

      // Delete the file
      DownloadFileManager.shared.deleteFile(at: record.localPath)

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
          DownloadFileManager.shared.deleteFile(at: record.localPath)
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
        DownloadFileManager.shared.deleteFile(at: record.localPath)
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
      UserDefaults.standard.set(tracksData, forKey: Self.downloadedTracksKey)

      // Convert Set to Array for encoding
      let playlistTracksDict = playlistTracks.mapValues { Array($0) }
      let playlistData = try JSONEncoder().encode(playlistTracksDict)
      UserDefaults.standard.set(playlistData, forKey: Self.playlistTracksKey)
    } catch {
      print("[DownloadDatabase] Failed to save to disk: \(error)")
    }
  }

  private func loadFromDisk() {
    print("\n" + String(repeating: "📀", count: 40))
    print("📀 DownloadDatabase: LOADING FROM DISK")
    print(String(repeating: "📀", count: 40))

    // Load synchronously to ensure data is available immediately
    // Load downloaded tracks
    if let tracksData = UserDefaults.standard.data(forKey: Self.downloadedTracksKey) {
      do {
        self.downloadedTracks = try JSONDecoder().decode(
          [String: DownloadedTrackRecord].self, from: tracksData)
        print("✅ DownloadDatabase: Loaded \(self.downloadedTracks.count) tracks from disk")

        // Log each downloaded track
        for (trackId, record) in self.downloadedTracks {
          print("   📥 \(trackId)")
          print("      Title: \(record.originalTrack.title)")
          print("      Path: \(record.localPath)")
          print("      Exists: \(FileManager.default.fileExists(atPath: record.localPath))")
        }
      } catch {
        print("❌ DownloadDatabase: Failed to load tracks from disk: \(error)")
      }
    } else {
      print("⚠️  DownloadDatabase: No saved tracks found in UserDefaults")
    }

    // Load playlist associations
    if let playlistData = UserDefaults.standard.data(forKey: Self.playlistTracksKey) {
      do {
        let playlistTracksDict = try JSONDecoder().decode(
          [String: [String]].self, from: playlistData)
        self.playlistTracks = playlistTracksDict.mapValues { Set($0) }
        print(
          "✅ DownloadDatabase: Loaded \(self.playlistTracks.count) playlist associations from disk")

        // Log playlist associations
        for (playlistId, trackIds) in self.playlistTracks {
          print("   📋 Playlist \(playlistId): \(trackIds.count) tracks")
        }
      } catch {
        print("❌ DownloadDatabase: Failed to load playlist tracks from disk: \(error)")
      }
    } else {
      print("⚠️  DownloadDatabase: No playlist associations found")
    }

    print(String(repeating: "📀", count: 40) + "\n")
  }

  // MARK: - Conversion Helpers

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
    return TrackItemRecord(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      url: track.url,
      artwork: variantToString(track.artwork)
    )
  }

  private func recordToTrackItem(_ record: TrackItemRecord) -> TrackItem {
    return TrackItem(
      id: record.id,
      title: record.title,
      artist: record.artist,
      album: record.album,
      duration: record.duration,
      url: record.url,
      artwork: stringToVariant(record.artwork),
      extraPayload: nil
    )
  }

  private func recordToDownloadedTrack(_ record: DownloadedTrackRecord) -> DownloadedTrack {
    return DownloadedTrack(
      trackId: record.trackId,
      originalTrack: recordToTrackItem(record.originalTrack),
      localPath: record.localPath,
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
}
