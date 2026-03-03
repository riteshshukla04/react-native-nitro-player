//
//  HybridDownloadManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 2026-01-23..
//

import Foundation
import NitroModules

/// Hybrid implementation of DownloadManagerSpec for iOS
/// Bridges Nitro modules with the native DownloadManagerCore implementation
final class HybridDownloadManager: HybridDownloadManagerSpec {

  // MARK: - Properties

  private let core: DownloadManagerCore

  // MARK: - Initialization

  override init() {
    core = DownloadManagerCore.shared
    super.init()
  }

  // MARK: - Configuration

  func configure(config: DownloadConfig) throws {
    core.configure(config)
  }

  func getConfig() throws -> DownloadConfig {
    return core.getConfig()
  }

  // MARK: - Download Operations

  func downloadTrack(track: TrackItem, playlistId: String?) throws -> Promise<String> {
    return Promise.async {
      return self.core.downloadTrack(track: track, playlistId: playlistId)
    }
  }

  func downloadPlaylist(playlistId: String, tracks: [TrackItem]) throws -> Promise<[String]> {
    return Promise.async {
      return self.core.downloadPlaylist(playlistId: playlistId, tracks: tracks)
    }
  }

  // MARK: - Download Control

  func pauseDownload(downloadId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.pauseDownload(downloadId: downloadId)
    }
  }

  func resumeDownload(downloadId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.resumeDownload(downloadId: downloadId)
    }
  }

  func cancelDownload(downloadId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.cancelDownload(downloadId: downloadId)
    }
  }

  func retryDownload(downloadId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.retryDownload(downloadId: downloadId)
    }
  }

  func pauseAllDownloads() throws -> Promise<Void> {
    return Promise.async {
      self.core.pauseAllDownloads()
    }
  }

  func resumeAllDownloads() throws -> Promise<Void> {
    return Promise.async {
      self.core.resumeAllDownloads()
    }
  }

  func cancelAllDownloads() throws -> Promise<Void> {
    return Promise.async {
      self.core.cancelAllDownloads()
    }
  }

  // MARK: - Download Status

  func getDownloadTask(downloadId: String) throws -> Variant_NullType_DownloadTask {
    if let task = core.getDownloadTask(downloadId: downloadId) {
      return Variant_NullType_DownloadTask.second(task)
    }
    return Variant_NullType_DownloadTask.first(NullType.null)
  }

  func getActiveDownloads() throws -> [DownloadTask] {
    return core.getActiveDownloads()
  }

  func getQueueStatus() throws -> DownloadQueueStatus {
    return core.getQueueStatus()
  }

  func isDownloading(trackId: String) throws -> Bool {
    return core.isDownloading(trackId: trackId)
  }

  func getDownloadState(trackId: String) throws -> DownloadState {
    return core.getDownloadState(trackId: trackId) ?? .pending
  }

  // MARK: - Downloaded Content Queries

  func isTrackDownloaded(trackId: String) throws -> Bool {
    return core.isTrackDownloaded(trackId: trackId)
  }

  func isPlaylistDownloaded(playlistId: String) throws -> Bool {
    return core.isPlaylistDownloaded(playlistId: playlistId)
  }

  func isPlaylistPartiallyDownloaded(playlistId: String) throws -> Bool {
    return core.isPlaylistPartiallyDownloaded(playlistId: playlistId)
  }

  func getDownloadedTrack(trackId: String) throws -> Variant_NullType_DownloadedTrack {
    if let track = core.getDownloadedTrack(trackId: trackId) {
      return Variant_NullType_DownloadedTrack.second(track)
    }
    return Variant_NullType_DownloadedTrack.first(NullType.null)
  }

  func getAllDownloadedTracks() throws -> [DownloadedTrack] {
    return core.getAllDownloadedTracks()
  }

  func getDownloadedPlaylist(playlistId: String) throws -> Variant_NullType_DownloadedPlaylist {
    if let playlist = core.getDownloadedPlaylist(playlistId: playlistId) {
      return Variant_NullType_DownloadedPlaylist.second(playlist)
    }
    return Variant_NullType_DownloadedPlaylist.first(NullType.null)
  }

  func getAllDownloadedPlaylists() throws -> [DownloadedPlaylist] {
    return core.getAllDownloadedPlaylists()
  }

  func getLocalPath(trackId: String) throws -> Variant_NullType_String {
    if let path = core.getLocalPath(trackId: trackId) {
      return Variant_NullType_String.second(path)
    }
    return Variant_NullType_String.first(NullType.null)
  }

  // MARK: - Deletion

  func deleteDownloadedTrack(trackId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.deleteDownloadedTrack(trackId: trackId)
    }
  }

  func deleteDownloadedPlaylist(playlistId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.deleteDownloadedPlaylist(playlistId: playlistId)
    }
  }

  func deleteAllDownloads() throws -> Promise<Void> {
    return Promise.async {
      self.core.deleteAllDownloads()
    }
  }

  // MARK: - Storage Management

  func getStorageInfo() throws -> Promise<DownloadStorageInfo> {
    return Promise.async {
      return self.core.getStorageInfo()
    }
  }

  func syncDownloads() throws -> Double {
    return Double(core.syncDownloads())
  }

  // MARK: - Playback Source Preference

  func setPlaybackSourcePreference(preference: PlaybackSource) throws {
    core.setPlaybackSourcePreference(preference)
  }

  func getPlaybackSourcePreference() throws -> PlaybackSource {
    return core.getPlaybackSourcePreference()
  }

  func getEffectiveUrl(track: TrackItem) throws -> String {
    return core.getEffectiveUrl(track: track)
  }

  // MARK: - Event Callbacks

  func onDownloadProgress(callback: @escaping (DownloadProgress) -> Void) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadProgress callback registered")
    core.addProgressCallback(callback)
  }

  func onDownloadStateChange(
    callback: @escaping (String, String, DownloadState, DownloadError?) -> Void
  ) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadStateChange callback registered")
    core.addStateChangeCallback(callback)
  }

  func onDownloadComplete(callback: @escaping (DownloadedTrack) -> Void) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadComplete callback registered")
    core.addCompleteCallback(callback)
  }
}
