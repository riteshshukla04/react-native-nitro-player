//
//  DownloadManagerCore.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 2026-01-23..
//

import Foundation
import NitroModules

/// Core download manager using URLSession background transfers
final class DownloadManagerCore: NSObject {

  // MARK: - Singleton

  static let shared = DownloadManagerCore()

  // MARK: - Constants

  private static let backgroundSessionIdentifier = "com.nitroplayer.backgroundDownloads"
  // Legacy UserDefaults keys (migration only)
  private static let legacyTrackMetadataKey = "NitroPlayerTrackMetadata"
  private static let legacyPlaylistAssociationsKey = "NitroPlayerPlaylistAssociations"

  // MARK: - Properties

  private var config: DownloadConfig = DownloadConfig(
    storageLocation: .private,
    maxConcurrentDownloads: 3,
    autoRetry: true,
    maxRetryAttempts: 3,
    backgroundDownloadsEnabled: true,
    downloadArtwork: true,
    customDownloadPath: nil,
    wifiOnlyDownloads: false
  )

  private var playbackSourcePreference: PlaybackSource = .auto

  private lazy var backgroundSession: URLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: Self.backgroundSessionIdentifier)
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    configuration.allowsCellularAccess = !config.wifiOnlyDownloads!
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  /// Active download tasks mapped by downloadId
  private var activeTasks: [String: URLSessionDownloadTask] = [:]

  /// Download task metadata mapped by downloadId
  private var taskMetadata: [String: DownloadTaskMetadata] = [:]

  /// Track metadata for downloads (trackId -> TrackItem)
  private var trackMetadata: [String: TrackItem] = [:]

  /// Playlist associations (downloadId -> playlistId)
  private var playlistAssociations: [String: String] = [:]

  /// Background completion handler from AppDelegate
  var backgroundCompletionHandler: (() -> Void)?

  // MARK: - Callbacks

  private var progressCallbacks: [(DownloadProgress) -> Void] = []
  private var stateChangeCallbacks: [(String, String, DownloadState, DownloadError?) -> Void] = []
  private var completeCallbacks: [(DownloadedTrack) -> Void] = []

  // MARK: - Thread Safety

  private let queue = DispatchQueue(
    label: "com.nitroplayer.downloadManager", attributes: .concurrent)

  // MARK: - Initialization

  private override init() {
    super.init()
    // Load persisted metadata first (before restoring downloads)
    loadPersistedMetadata()
    // Restore any pending downloads
    restorePendingDownloads()
  }

  // MARK: - Configuration

  func configure(_ config: DownloadConfig) {
    queue.async(flags: .barrier) {
      self.config = config

      // Update session configuration if needed
      if let wifiOnly = config.wifiOnlyDownloads {
        // Note: We can't change session config after creation
        // User needs to restart app for this to take effect
      }
    }
  }

  func getConfig() -> DownloadConfig {
    return queue.sync { config }
  }

  // MARK: - Download Operations

  func downloadTrack(track: TrackItem, playlistId: String?) -> String {
    let downloadId = UUID().uuidString

    queue.async(flags: .barrier) {
      // Store track metadata
      self.trackMetadata[track.id] = track

      // Store playlist association if provided
      if let playlistId = playlistId {
        self.playlistAssociations[downloadId] = playlistId
      }

      // Persist metadata (survives app restart)
      self.savePersistedMetadata()

      // Create download task
      guard let url = URL(string: track.url) else {
        self.notifyStateChange(
          downloadId: downloadId, trackId: track.id, state: .failed,
          error: DownloadError(
            code: "INVALID_URL",
            message: "Invalid track URL: \(track.url)",
            reason: .invalidUrl,
            isRetryable: false
          ))
        return
      }

      let task = self.backgroundSession.downloadTask(with: url)
      task.taskDescription = "\(downloadId)|\(track.id)"

      self.activeTasks[downloadId] = task
      self.taskMetadata[downloadId] = DownloadTaskMetadata(
        downloadId: downloadId,
        trackId: track.id,
        playlistId: playlistId,
        state: .pending,
        createdAt: Date().timeIntervalSince1970,
        retryCount: 0
      )

      // Respect max concurrent downloads
      let activeCount = self.activeTasks.values.filter { $0.state == .running }.count
      if activeCount < Int(self.config.maxConcurrentDownloads ?? 3) {
        task.resume()
        self.taskMetadata[downloadId]?.state = .downloading
        self.taskMetadata[downloadId]?.startedAt = Date().timeIntervalSince1970
      }

      self.notifyStateChange(
        downloadId: downloadId, trackId: track.id,
        state: self.taskMetadata[downloadId]?.state ?? .pending, error: nil)
    }

    return downloadId
  }

  func downloadPlaylist(playlistId: String, tracks: [TrackItem]) -> [String] {
    var downloadIds: [String] = []

    for track in tracks {
      let downloadId = downloadTrack(track: track, playlistId: playlistId)
      downloadIds.append(downloadId)
    }

    return downloadIds
  }

  // MARK: - Download Control

  func pauseDownload(downloadId: String) {
    queue.async(flags: .barrier) {
      guard let task = self.activeTasks[downloadId] else { return }

      task.cancel(byProducingResumeData: { resumeData in
        // Store resume data for later
        self.taskMetadata[downloadId]?.resumeData = resumeData
      })

      self.taskMetadata[downloadId]?.state = .paused

      if let trackId = self.taskMetadata[downloadId]?.trackId {
        self.notifyStateChange(downloadId: downloadId, trackId: trackId, state: .paused, error: nil)
      }
    }
  }

  func resumeDownload(downloadId: String) {
    queue.async(flags: .barrier) {
      guard let metadata = self.taskMetadata[downloadId] else { return }

      var task: URLSessionDownloadTask

      if let resumeData = metadata.resumeData {
        task = self.backgroundSession.downloadTask(withResumeData: resumeData)
      } else if let track = self.trackMetadata[metadata.trackId],
        let url = URL(string: track.url)
      {
        task = self.backgroundSession.downloadTask(with: url)
      } else {
        return
      }

      task.taskDescription = "\(downloadId)|\(metadata.trackId)"
      self.activeTasks[downloadId] = task
      self.taskMetadata[downloadId]?.state = .downloading
      self.taskMetadata[downloadId]?.resumeData = nil

      task.resume()

      self.notifyStateChange(
        downloadId: downloadId, trackId: metadata.trackId, state: .downloading, error: nil)
    }
  }

  func cancelDownload(downloadId: String) {
    queue.async(flags: .barrier) {
      guard let task = self.activeTasks[downloadId] else { return }

      task.cancel()

      if let trackId = self.taskMetadata[downloadId]?.trackId {
        self.taskMetadata[downloadId]?.state = .cancelled
        self.notifyStateChange(
          downloadId: downloadId, trackId: trackId, state: .cancelled, error: nil)
        // Clean up persisted metadata
        self.cleanupPersistedMetadata(trackId: trackId, downloadId: downloadId)
      }

      self.activeTasks.removeValue(forKey: downloadId)
      self.taskMetadata.removeValue(forKey: downloadId)
    }
  }

  func retryDownload(downloadId: String) {
    queue.async(flags: .barrier) {
      guard let metadata = self.taskMetadata[downloadId],
        let track = self.trackMetadata[metadata.trackId],
        let url = URL(string: track.url)
      else { return }

      let task = self.backgroundSession.downloadTask(with: url)
      task.taskDescription = "\(downloadId)|\(metadata.trackId)"

      self.activeTasks[downloadId] = task
      self.taskMetadata[downloadId]?.state = .downloading
      self.taskMetadata[downloadId]?.retryCount += 1
      self.taskMetadata[downloadId]?.error = nil

      task.resume()

      self.notifyStateChange(
        downloadId: downloadId, trackId: metadata.trackId, state: .downloading, error: nil)
    }
  }

  func pauseAllDownloads() {
    queue.async(flags: .barrier) {
      for downloadId in self.activeTasks.keys {
        self.pauseDownload(downloadId: downloadId)
      }
    }
  }

  func resumeAllDownloads() {
    queue.async(flags: .barrier) {
      for downloadId in self.taskMetadata.keys where self.taskMetadata[downloadId]?.state == .paused
      {
        self.resumeDownload(downloadId: downloadId)
      }
    }
  }

  func cancelAllDownloads() {
    queue.async(flags: .barrier) {
      for downloadId in self.activeTasks.keys {
        self.cancelDownload(downloadId: downloadId)
      }
    }
  }

  // MARK: - Download Status

  func getDownloadTask(downloadId: String) -> DownloadTask? {
    return queue.sync {
      guard let metadata = taskMetadata[downloadId] else { return nil }
      return metadata.toDownloadTask()
    }
  }

  func getActiveDownloads() -> [DownloadTask] {
    return queue.sync {
      return taskMetadata.values
        .filter { $0.state == .downloading || $0.state == .pending || $0.state == .paused }
        .map { $0.toDownloadTask() }
    }
  }

  func getQueueStatus() -> DownloadQueueStatus {
    return queue.sync {
      let metadata = Array(taskMetadata.values)

      let pendingCount = metadata.filter { $0.state == .pending }.count
      let activeCount = metadata.filter { $0.state == .downloading }.count
      let completedCount = DownloadDatabase.shared.getAllDownloadedTracks().count
      let failedCount = metadata.filter { $0.state == .failed }.count

      let totalBytes = metadata.reduce(0.0) { $0 + ($1.totalBytes ?? 0) }
      let downloadedBytes = metadata.reduce(0.0) { $0 + $1.bytesDownloaded }

      return DownloadQueueStatus(
        pendingCount: Double(pendingCount),
        activeCount: Double(activeCount),
        completedCount: Double(completedCount),
        failedCount: Double(failedCount),
        totalBytesToDownload: totalBytes,
        totalBytesDownloaded: downloadedBytes,
        overallProgress: totalBytes > 0 ? downloadedBytes / totalBytes : 0
      )
    }
  }

  func isDownloading(trackId: String) -> Bool {
    return queue.sync {
      return taskMetadata.values.contains { $0.trackId == trackId && $0.state == .downloading }
    }
  }

  func getDownloadState(trackId: String) -> DownloadState? {
    return queue.sync {
      if let metadata = taskMetadata.values.first(where: { $0.trackId == trackId }) {
        return metadata.state
      }
      if DownloadDatabase.shared.getDownloadedTrack(trackId: trackId) != nil {
        return .completed
      }
      return nil
    }
  }

  // MARK: - Downloaded Content Queries

  func isTrackDownloaded(trackId: String) -> Bool {
    return DownloadDatabase.shared.isTrackDownloaded(trackId: trackId)
  }

  func isPlaylistDownloaded(playlistId: String) -> Bool {
    return DownloadDatabase.shared.isPlaylistDownloaded(playlistId: playlistId)
  }

  func isPlaylistPartiallyDownloaded(playlistId: String) -> Bool {
    return DownloadDatabase.shared.isPlaylistPartiallyDownloaded(playlistId: playlistId)
  }

  func getDownloadedTrack(trackId: String) -> DownloadedTrack? {
    return DownloadDatabase.shared.getDownloadedTrack(trackId: trackId)
  }

  func getAllDownloadedTracks() -> [DownloadedTrack] {
    return DownloadDatabase.shared.getAllDownloadedTracks()
  }

  func getDownloadedPlaylist(playlistId: String) -> DownloadedPlaylist? {
    return DownloadDatabase.shared.getDownloadedPlaylist(playlistId: playlistId)
  }

  func getAllDownloadedPlaylists() -> [DownloadedPlaylist] {
    return DownloadDatabase.shared.getAllDownloadedPlaylists()
  }

  func getLocalPath(trackId: String) -> String? {
    NitroPlayerLogger.log("DownloadManagerCore", "🔍 getLocalPath() called for trackId: \(trackId)")
    if let downloadedTrack = DownloadDatabase.shared.getDownloadedTrack(trackId: trackId) {
      NitroPlayerLogger.log("DownloadManagerCore", "   ✅ Found downloaded track, localPath: \(downloadedTrack.localPath)")
      return downloadedTrack.localPath
    } else {
      NitroPlayerLogger.log("DownloadManagerCore", "   ❌ No downloaded track found for trackId: \(trackId)")
      return nil
    }
  }

  // MARK: - Deletion

  func deleteDownloadedTrack(trackId: String) {
    DownloadDatabase.shared.deleteDownloadedTrack(trackId: trackId)
  }

  func deleteDownloadedPlaylist(playlistId: String) {
    DownloadDatabase.shared.deleteDownloadedPlaylist(playlistId: playlistId)
  }

  func deleteAllDownloads() {
    DownloadDatabase.shared.deleteAllDownloads()
  }

  // MARK: - Storage

  func getStorageInfo() -> DownloadStorageInfo {
    return DownloadFileManager.shared.getStorageInfo()
  }

  /// Validates all downloads and cleans up orphaned records (files that were manually deleted)
  func syncDownloads() -> Int {
    let removedFromDb = DownloadDatabase.shared.syncDownloads()
    let bytesFreed = DownloadFileManager.shared.cleanupOrphanedFiles()
      NitroPlayerLogger.log("DownloadManagerCore", "🔄 syncDownloads completed - removed \(removedFromDb) orphaned records, freed \(bytesFreed) bytes")
    return removedFromDb
  }

  // MARK: - Playback Source Preference

  func setPlaybackSourcePreference(_ preference: PlaybackSource) {
    queue.async(flags: .barrier) {
      self.playbackSourcePreference = preference
    }
  }

  func getPlaybackSourcePreference() -> PlaybackSource {
    return queue.sync { playbackSourcePreference }
  }

  func getEffectiveUrl(track: TrackItem) -> String {
    let preference = getPlaybackSourcePreference()
    NitroPlayerLogger.log("DownloadManagerCore", "🔍 getEffectiveUrl() for track: \(track.id)")
    NitroPlayerLogger.log("DownloadManagerCore", "   Playback preference: \(preference)")

    switch preference {
    case .network:
      NitroPlayerLogger.log("DownloadManagerCore", "   → Using network URL (preference=network)")
      return track.url
    case .download:
      if let localPath = getLocalPath(trackId: track.id) {
        NitroPlayerLogger.log("DownloadManagerCore", "   → Using local path: \(localPath)")
        return localPath
      } else {
        NitroPlayerLogger.log("DownloadManagerCore", "   → Local path not found, falling back to network URL")
        return track.url
      }
    case .auto:
      if let localPath = getLocalPath(trackId: track.id) {
        NitroPlayerLogger.log("DownloadManagerCore", "   → Using local path: \(localPath)")
        return localPath
      } else {
        NitroPlayerLogger.log("DownloadManagerCore", "   → Local path not found, using network URL")
        return track.url
      }
    }
  }

  // MARK: - Callbacks

  func addProgressCallback(_ callback: @escaping (DownloadProgress) -> Void) {
    queue.async(flags: .barrier) {
      self.progressCallbacks.append(callback)
    }
  }

  func addStateChangeCallback(
    _ callback: @escaping (String, String, DownloadState, DownloadError?) -> Void
  ) {
    queue.async(flags: .barrier) {
      self.stateChangeCallbacks.append(callback)
    }
  }

  func addCompleteCallback(_ callback: @escaping (DownloadedTrack) -> Void) {
    queue.async(flags: .barrier) {
      self.completeCallbacks.append(callback)
    }
  }

  // MARK: - Private Helpers

  private func restorePendingDownloads() {
    backgroundSession.getTasksWithCompletionHandler { [weak self] _, _, downloadTasks in
      for task in downloadTasks {
        guard let description = task.taskDescription else { continue }
        let parts = description.split(separator: "|")
        guard parts.count == 2 else { continue }

        let downloadId = String(parts[0])
        let trackId = String(parts[1])

        self?.queue.async(flags: .barrier) {
          self?.activeTasks[downloadId] = task
          if self?.taskMetadata[downloadId] == nil {
            self?.taskMetadata[downloadId] = DownloadTaskMetadata(
              downloadId: downloadId,
              trackId: trackId,
              playlistId: nil,
              state: task.state == .running ? .downloading : .paused,
              createdAt: Date().timeIntervalSince1970,
              retryCount: 0
            )
          }
        }
      }
    }
  }

  // MARK: - Metadata Persistence

  /// Load persisted track metadata and playlist associations (survives app restart)
  private func loadPersistedMetadata() {
    NitroPlayerLogger.log("DownloadManagerCore", "📦 Loading persisted metadata...")

    // 1. Try new JSON file (post-migration)
    if let data = NitroPlayerStorage.read(filename: "download_metadata.json") {
      do {
        if let wrapper = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
          if let tracksObj = wrapper["trackMetadata"] as? [String: Any] {
            let tracksData = try JSONSerialization.data(withJSONObject: tracksObj)
            let records = try JSONDecoder().decode([String: TrackItemRecord].self, from: tracksData)
            for (trackId, record) in records {
              trackMetadata[trackId] = recordToTrackItem(record)
            }
            NitroPlayerLogger.log("DownloadManagerCore", "   ✅ Loaded \(trackMetadata.count) track metadata entries from file")
          }
          if let assocObj = wrapper["playlistAssociations"] as? [String: String] {
            playlistAssociations = assocObj
            NitroPlayerLogger.log("DownloadManagerCore", "   ✅ Loaded \(playlistAssociations.count) playlist associations from file")
          }
        }
      } catch {
        NitroPlayerLogger.log("DownloadManagerCore", "   ❌ Failed to load metadata from file: \(error)")
      }
      return
    }

    // 2. Migrate from UserDefaults (one-time, existing installs)
    var didMigrate = false

    if let data = UserDefaults.standard.data(forKey: Self.legacyTrackMetadataKey) {
      do {
        let records = try JSONDecoder().decode([String: TrackItemRecord].self, from: data)
        for (trackId, record) in records {
          trackMetadata[trackId] = recordToTrackItem(record)
        }
        NitroPlayerLogger.log("DownloadManagerCore", "   ✅ Migrated \(trackMetadata.count) track metadata entries from UserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.legacyTrackMetadataKey)
        didMigrate = true
      } catch {
        NitroPlayerLogger.log("DownloadManagerCore", "   ❌ Failed to migrate track metadata: \(error)")
      }
    } else {
      NitroPlayerLogger.log("DownloadManagerCore", "   ⚠️ No persisted track metadata found")
    }

    if let data = UserDefaults.standard.data(forKey: Self.legacyPlaylistAssociationsKey) {
      do {
        playlistAssociations = try JSONDecoder().decode([String: String].self, from: data)
        NitroPlayerLogger.log("DownloadManagerCore", "   ✅ Migrated \(playlistAssociations.count) playlist associations from UserDefaults")
        UserDefaults.standard.removeObject(forKey: Self.legacyPlaylistAssociationsKey)
        didMigrate = true
      } catch {
        NitroPlayerLogger.log("DownloadManagerCore", "   ❌ Failed to migrate playlist associations: \(error)")
      }
    } else {
      NitroPlayerLogger.log("DownloadManagerCore", "   ⚠️ No persisted playlist associations found")
    }

    if didMigrate {
      savePersistedMetadata()
    }
  }

  /// Persist track metadata and playlist associations to disk
  private func savePersistedMetadata() {
    var records: [String: TrackItemRecord] = [:]
    for (trackId, track) in trackMetadata {
      records[trackId] = trackItemToRecord(track)
    }

    do {
      let tracksData = try JSONEncoder().encode(records)
      let playlistData = try JSONEncoder().encode(playlistAssociations)

      guard let tracksJson = try JSONSerialization.jsonObject(with: tracksData) as? [String: Any],
            let assocJson = try JSONSerialization.jsonObject(with: playlistData) as? [String: Any]
      else { return }

      let wrapper: [String: Any] = [
        "trackMetadata": tracksJson,
        "playlistAssociations": assocJson,
      ]
      let data = try JSONSerialization.data(withJSONObject: wrapper, options: [])
      try NitroPlayerStorage.write(filename: "download_metadata.json", data: data)
    } catch {
      NitroPlayerLogger.log("DownloadManagerCore", "❌ Failed to save metadata: \(error)")
    }
  }

  /// Clean up persisted metadata for completed/cancelled downloads
  private func cleanupPersistedMetadata(trackId: String, downloadId: String) {
    trackMetadata.removeValue(forKey: trackId)
    playlistAssociations.removeValue(forKey: downloadId)
    savePersistedMetadata()
  }

  // MARK: - TrackItem Serialization

  private func trackItemToRecord(_ track: TrackItem) -> TrackItemRecord {
    var artworkString: String? = nil
    if let artwork = track.artwork {
      switch artwork {
      case .first(_):
        artworkString = nil
      case .second(let value):
        artworkString = value
      }
    }

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
      artwork: artworkString,
      extraPayload: extraPayloadDict
    )
  }

  private func recordToTrackItem(_ record: TrackItemRecord) -> TrackItem {
    let artwork: Variant_NullType_String? = record.artwork.map { .second($0) }

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
      artwork: artwork,
      extraPayload: extraPayload
    )
  }

  private func notifyProgress(_ progress: DownloadProgress) {
    DispatchQueue.main.async {
      for callback in self.progressCallbacks {
        callback(progress)
      }
    }
  }

  private func notifyStateChange(
    downloadId: String, trackId: String, state: DownloadState, error: DownloadError?
  ) {
    DispatchQueue.main.async {
      for callback in self.stateChangeCallbacks {
        callback(downloadId, trackId, state, error)
      }
    }
  }

  private func notifyComplete(_ downloadedTrack: DownloadedTrack) {
    DispatchQueue.main.async {
      for callback in self.completeCallbacks {
        callback(downloadedTrack)
      }
    }
  }

  private func startNextPendingDownload() {
    queue.async(flags: .barrier) {
      let activeCount = self.activeTasks.values.filter { $0.state == .running }.count
      let maxConcurrent = Int(self.config.maxConcurrentDownloads ?? 3)

      if activeCount >= maxConcurrent { return }

      if let pendingId = self.taskMetadata.first(where: { $0.value.state == .pending })?.key,
        let task = self.activeTasks[pendingId]
      {
        task.resume()
        self.taskMetadata[pendingId]?.state = .downloading
        self.taskMetadata[pendingId]?.startedAt = Date().timeIntervalSince1970

        if let trackId = self.taskMetadata[pendingId]?.trackId {
          self.notifyStateChange(
            downloadId: pendingId, trackId: trackId, state: .downloading, error: nil)
        }
      }
    }
  }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManagerCore: URLSessionDownloadDelegate {

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    NitroPlayerLogger.log("DownloadManagerCore", "🎯 didFinishDownloadingTo called")

    guard let description = downloadTask.taskDescription else {
      NitroPlayerLogger.log("DownloadManagerCore", "❌ No task description")
      return
    }
    let parts = description.split(separator: "|")
    guard parts.count == 2 else {
      NitroPlayerLogger.log("DownloadManagerCore", "❌ Invalid task description format: \(description)")
      return
    }

    let downloadId = String(parts[0])
    let trackId = String(parts[1])

      NitroPlayerLogger.log("DownloadManagerCore", "🎯 Processing completion for downloadId=\(downloadId), trackId=\(trackId)")

    // IMPORTANT: Move file SYNCHRONOUSLY - the temp file is deleted after this method returns!
    // Get storage location and original URL from track metadata
    let (storageLocation, originalURL) = queue.sync {
      (self.config.storageLocation ?? .private, self.trackMetadata[trackId]?.url)
    }

    // Get suggested filename and HTTP headers from response
    let suggestedFilename = downloadTask.response?.suggestedFilename
    let httpResponse = downloadTask.response as? HTTPURLResponse

    let destinationPath = DownloadFileManager.shared.saveDownloadedFile(
      from: location,
      trackId: trackId,
      storageLocation: storageLocation,
      originalURL: originalURL,
      suggestedFilename: suggestedFilename,
      httpResponse: httpResponse
    )

    // Now handle the rest asynchronously
    queue.async(flags: .barrier) {
      guard let destinationPath = destinationPath else {
        NitroPlayerLogger.log("DownloadManagerCore", "❌ Failed to save file for trackId=\(trackId)")
        self.taskMetadata[downloadId]?.state = .failed
        self.taskMetadata[downloadId]?.error = DownloadError(
          code: "FILE_MOVE_FAILED",
          message: "Failed to save downloaded file",
          reason: .unknown,
          isRetryable: true
        )
        self.notifyStateChange(
          downloadId: downloadId, trackId: trackId, state: .failed,
          error: self.taskMetadata[downloadId]?.error)
        return
      }

      NitroPlayerLogger.log("DownloadManagerCore", "✅ File saved to \(destinationPath)")

      guard let track = self.trackMetadata[trackId] else {
        NitroPlayerLogger.log("DownloadManagerCore", "❌ No track metadata for trackId=\(trackId)")
        NitroPlayerLogger.log("DownloadManagerCore", "   Available trackIds: \(Array(self.trackMetadata.keys))")

        // Still mark as completed even if we don't have metadata
        self.taskMetadata[downloadId]?.state = .completed
        self.taskMetadata[downloadId]?.completedAt = Date().timeIntervalSince1970
        self.activeTasks.removeValue(forKey: downloadId)
        self.notifyStateChange(
          downloadId: downloadId, trackId: trackId, state: .completed, error: nil)
        self.startNextPendingDownload()
        return
      }

      let playlistId = self.playlistAssociations[downloadId]

      // Get file size
      let fileSize = DownloadFileManager.shared.getFileSize(at: destinationPath)

      // Create downloaded track record
      let downloadedTrack = DownloadedTrack(
        trackId: trackId,
        originalTrack: track,
        localPath: destinationPath,
        localArtworkPath: nil,
        downloadedAt: Date().timeIntervalSince1970,
        fileSize: Double(fileSize),
        storageLocation: storageLocation
      )

      // Save to database
      DownloadDatabase.shared.saveDownloadedTrack(downloadedTrack, playlistId: playlistId)

      NitroPlayerLogger.log("DownloadManagerCore", "✅ Track saved to database")

      // Clean up persisted metadata (no longer needed after completion)
      self.cleanupPersistedMetadata(trackId: trackId, downloadId: downloadId)

      // Update state
      self.taskMetadata[downloadId]?.state = .completed
      self.taskMetadata[downloadId]?.completedAt = Date().timeIntervalSince1970

      // Clean up active task but keep metadata for state queries
      self.activeTasks.removeValue(forKey: downloadId)

      // Notify
      NitroPlayerLogger.log("DownloadManagerCore", "✅ Notifying completion for trackId=\(trackId)")
      self.notifyStateChange(
        downloadId: downloadId, trackId: trackId, state: .completed, error: nil)
      self.notifyComplete(downloadedTrack)

      // Start next download
      self.startNextPendingDownload()
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let description = downloadTask.taskDescription else { return }
    let parts = description.split(separator: "|")
    guard parts.count == 2 else { return }

    let downloadId = String(parts[0])
    let trackId = String(parts[1])

    queue.async(flags: .barrier) {
      self.taskMetadata[downloadId]?.bytesDownloaded = Double(totalBytesWritten)
      self.taskMetadata[downloadId]?.totalBytes =
        totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : nil

      let progress = DownloadProgress(
        trackId: trackId,
        downloadId: downloadId,
        bytesDownloaded: Double(totalBytesWritten),
        totalBytes: Double(totalBytesExpectedToWrite),
        progress: totalBytesExpectedToWrite > 0
          ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0,
        state: .downloading
      )

      self.notifyProgress(progress)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let downloadTask = task as? URLSessionDownloadTask,
      let description = downloadTask.taskDescription
    else { return }

    let parts = description.split(separator: "|")
    guard parts.count == 2 else { return }

    let downloadId = String(parts[0])
    let trackId = String(parts[1])

    guard let error = error else { return }  // Success case handled in didFinishDownloadingTo

    queue.async(flags: .barrier) {
      let nsError = error as NSError

      // Check if this is a cancellation
      if nsError.code == NSURLErrorCancelled {
        // Check if we have resume data (pause)
        if self.taskMetadata[downloadId]?.resumeData != nil {
          return  // Already handled in pauseDownload
        }
        // Otherwise it's a cancellation
        return
      }

      // Determine error reason
      let errorReason: DownloadErrorReason
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
        errorReason = .networkError
      case NSURLErrorTimedOut:
        errorReason = .timeout
      case NSURLErrorFileDoesNotExist:
        errorReason = .fileNotFound
      default:
        errorReason = .unknown
      }

      let downloadError = DownloadError(
        code: String(nsError.code),
        message: error.localizedDescription,
        reason: errorReason,
        isRetryable: errorReason == .networkError || errorReason == .timeout
      )

      self.taskMetadata[downloadId]?.state = .failed
      self.taskMetadata[downloadId]?.error = downloadError

      // Auto-retry if enabled
      if let autoRetry = self.config.autoRetry, autoRetry,
        downloadError.isRetryable,
        let retryCount = self.taskMetadata[downloadId]?.retryCount,
        retryCount < Int(self.config.maxRetryAttempts ?? 3)
      {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
          self.retryDownload(downloadId: downloadId)
        }
      } else {
        self.notifyStateChange(
          downloadId: downloadId, trackId: trackId, state: .failed, error: downloadError)
      }

      // Start next download
      self.startNextPendingDownload()
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      self.backgroundCompletionHandler?()
      self.backgroundCompletionHandler = nil
    }
  }
}

// MARK: - Download Task Metadata

private struct DownloadTaskMetadata {
  let downloadId: String
  let trackId: String
  let playlistId: String?
  var state: DownloadState
  let createdAt: Double
  var startedAt: Double?
  var completedAt: Double?
  var retryCount: Int
  var resumeData: Data?
  var bytesDownloaded: Double = 0
  var totalBytes: Double?
  var error: DownloadError?

  func toDownloadTask() -> DownloadTask {
    let progress = DownloadProgress(
      trackId: trackId,
      downloadId: downloadId,
      bytesDownloaded: bytesDownloaded,
      totalBytes: totalBytes ?? 0,
      progress: totalBytes != nil && totalBytes! > 0 ? bytesDownloaded / totalBytes! : 0,
      state: state
    )

    return DownloadTask(
      downloadId: downloadId,
      trackId: trackId,
      playlistId: playlistId.map { Variant_NullType_String.second($0) },
      state: state,
      progress: progress,
      createdAt: createdAt,
      startedAt: startedAt.map { Variant_NullType_Double.second($0) },
      completedAt: completedAt.map { Variant_NullType_Double.second($0) },
      error: error.map { Variant_NullType_DownloadError.second($0) },
      retryCount: Double(retryCount)
    )
  }
}

// MARK: - Track Item Record (for persistence)

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
