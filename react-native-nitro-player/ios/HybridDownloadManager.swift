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

  override init() throws {
    core = DownloadManagerCore.shared
    try super.init()
  }

  // MARK: - Configuration

  func configure(config: DownloadConfig) throws {
    core.configure(config)
  }

  func getConfig() throws -> DownloadConfig {
    return core.getConfig()
  }

  // MARK: - Download Operations

  func downloadTrack(track: TrackItem, playlistId: String?) throws -> any Promise<String> {
    return .async { [core] in
      return core.downloadTrack(track: track, playlistId: playlistId)
    }
  }

  func downloadPlaylist(playlistId: String, tracks: [TrackItem]) throws -> any Promise<[String]> {
    return .async { [core] in
      return core.downloadPlaylist(playlistId: playlistId, tracks: tracks)
    }
  }

  // MARK: - Download Control

  func pauseDownload(downloadId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.pauseDownload(downloadId: downloadId)
    }
  }

  func resumeDownload(downloadId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.resumeDownload(downloadId: downloadId)
    }
  }

  func cancelDownload(downloadId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.cancelDownload(downloadId: downloadId)
    }
  }

  func retryDownload(downloadId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.retryDownload(downloadId: downloadId)
    }
  }

  func pauseAllDownloads() throws -> any Promise<Void> {
    return .async { [core] in
      core.pauseAllDownloads()
    }
  }

  func resumeAllDownloads() throws -> any Promise<Void> {
    return .async { [core] in
      core.resumeAllDownloads()
    }
  }

  func cancelAllDownloads() throws -> any Promise<Void> {
    return .async { [core] in
      core.cancelAllDownloads()
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

  func isTrackDownloaded(trackId: String) throws -> any Promise<Bool> {
    .async { [core] in core.isTrackDownloaded(trackId: trackId) }
  }

  func isPlaylistDownloaded(playlistId: String) throws -> any Promise<Bool> {
    .async { [core] in core.isPlaylistDownloaded(playlistId: playlistId) }
  }

  func isPlaylistPartiallyDownloaded(playlistId: String) throws -> any Promise<Bool> {
    .async { [core] in core.isPlaylistPartiallyDownloaded(playlistId: playlistId) }
  }

  func getDownloadedTrack(trackId: String) throws -> any Promise<Variant_NullType_DownloadedTrack> {
    .async { [core] in
      if let track = core.getDownloadedTrack(trackId: trackId) {
        return Variant_NullType_DownloadedTrack.second(track)
      }
      return Variant_NullType_DownloadedTrack.first(NullType.null)
    }
  }

  func getAllDownloadedTracks() throws -> any Promise<[DownloadedTrack]> {
    .async { [core] in core.getAllDownloadedTracks() }
  }

  func getDownloadedPlaylist(playlistId: String) throws -> any Promise<Variant_NullType_DownloadedPlaylist> {
    .async { [core] in
      if let playlist = core.getDownloadedPlaylist(playlistId: playlistId) {
        return Variant_NullType_DownloadedPlaylist.second(playlist)
      }
      return Variant_NullType_DownloadedPlaylist.first(NullType.null)
    }
  }

  func getAllDownloadedPlaylists() throws -> any Promise<[DownloadedPlaylist]> {
    .async { [core] in core.getAllDownloadedPlaylists() }
  }

  func getLocalPath(trackId: String) throws -> any Promise<Variant_NullType_String> {
    .async { [core] in
      if let path = core.getLocalPath(trackId: trackId) {
        return Variant_NullType_String.second(path)
      }
      return Variant_NullType_String.first(NullType.null)
    }
  }

  // MARK: - Deletion

  func deleteDownloadedTrack(trackId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.deleteDownloadedTrack(trackId: trackId)
    }
  }

  func deleteDownloadedPlaylist(playlistId: String) throws -> any Promise<Void> {
    return .async { [core] in
      core.deleteDownloadedPlaylist(playlistId: playlistId)
    }
  }

  func deleteAllDownloads() throws -> any Promise<Void> {
    return .async { [core] in
      core.deleteAllDownloads()
    }
  }

  // MARK: - Storage Management

  func getStorageInfo() throws -> any Promise<DownloadStorageInfo> {
    return .async { [core] in
      return core.getStorageInfo()
    }
  }

  func syncDownloads() throws -> any Promise<Double> {
    .async { [core] in Double(core.syncDownloads()) }
  }

  // MARK: - Playback Source Preference

  func setPlaybackSourcePreference(preference: PlaybackSource) throws {
    core.setPlaybackSourcePreference(preference)
  }

  func getPlaybackSourcePreference() throws -> PlaybackSource {
    return core.getPlaybackSourcePreference()
  }

  func getEffectiveUrl(track: TrackItem) throws -> any Promise<String> {
    .async { [core] in core.getEffectiveUrl(track: track) }
  }

  // MARK: - Event Callbacks

  private var progressCallbackIds: [UUID] = []
  private var stateChangeCallbackIds: [UUID] = []
  private var completeCallbackIds: [UUID] = []

  func onDownloadProgress(callback: any Callback<(DownloadProgress), Void>) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadProgress callback registered")
    progressCallbackIds.append(core.addProgressCallback { callback($0) })
  }

  func onDownloadStateChange(
    callback: any Callback<(String, String, DownloadState, DownloadError?), Void>
  ) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadStateChange callback registered")
    stateChangeCallbackIds.append(core.addStateChangeCallback { callback($0, $1, $2, $3) })
  }

  func onDownloadComplete(callback: any Callback<(DownloadedTrack), Void>) throws {
    NitroPlayerLogger.log("HybridDownloadManager", "onDownloadComplete callback registered")
    completeCallbackIds.append(core.addCompleteCallback { callback($0) })
  }

  deinit {
    progressCallbackIds.forEach { core.removeProgressCallback(id: $0) }
    stateChangeCallbackIds.forEach { core.removeStateChangeCallback(id: $0) }
    completeCallbackIds.forEach { core.removeCompleteCallback(id: $0) }
  }
}
