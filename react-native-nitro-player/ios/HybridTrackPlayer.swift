//
//  HybridTrackPlayer.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import Foundation
import NitroModules

/// Hybrid implementation of TrackPlayerSpec for iOS
/// Bridges Nitro modules with the native TrackPlayerCore implementation
final class HybridTrackPlayer: HybridTrackPlayerSpec {
  // MARK: - Properties

  private let core: TrackPlayerCore

  /// Stable listener IDs for cleanup on deinit
  private var listenerIds: [(String, Int64)] = []

  // MARK: - Initialization

  override init() throws {
    core = TrackPlayerCore.shared
    try super.init()
  }

  // MARK: - Ordered dispatch
  //
  // `.async { … }` starts an unordered Task, so two calls made in order from JS could
  // reach the player in reverse order (play-then-pause landing as pause-then-play).
  // `.parallel(core.playerQueue)` enqueues synchronously, on the JS thread at call time,
  // so the serial queue's FIFO order equals the JS call order.

  // MARK: - Playback Control (async Promise<Void>)

  func play() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.playOnQueue() }
  }

  func pause() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.pauseOnQueue() }
  }

  func seek(position: Double) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.seekOnQueue(position: position) }
  }

  func skipToNext() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.skipToNextOnQueue() }
  }

  func skipToPrevious() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.skipToPreviousOnQueue() }
  }

  func playSong(songId: String, fromPlaylist: String?) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.playSongInternal(songId: songId, fromPlaylist: fromPlaylist) }
  }

  func skipToIndex(index: Double) throws -> any Promise<Bool> {
    .parallel(core.playerQueue) { [core] in core.skipToIndexOnQueue(index: Int(index)) }
  }

  // MARK: - Repeat / Volume / Config

  func setRepeatMode(mode: RepeatMode) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.setRepeatModeOnQueue(mode: mode) }
  }

  func getRepeatMode() throws -> RepeatMode {
    core.getRepeatMode()
  }

  func setVolume(volume: Double) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.setVolumeOnQueue(volume: volume) }
  }

  func configure(config: PlayerConfig) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in
      core.configureOnQueue(
        androidAutoEnabled: config.androidAutoEnabled,
        carPlayEnabled: config.carPlayEnabled,
        showInNotification: config.showInNotification,
        lookaheadCount: config.lookaheadCount.map { Int($0) },
        remoteSkipForwardInterval: config.remoteSkipForwardInterval,
        remoteSkipBackwardInterval: config.remoteSkipBackwardInterval,
        preferRemoteSkipIntervals: config.preferRemoteSkipIntervals
      )
    }
  }

  // MARK: - Queue / State reads

  func getActualQueue() throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.getActualQueueInternal() }
  }

  func getState() throws -> any Promise<PlayerState> {
    .parallel(core.playerQueue) { [core] in core.getStateInternal() }
  }

  func getCurrentTrackIndex() throws -> any Promise<Double> {
    .parallel(core.playerQueue) { [core] in Double(core.currentTrackIndex) }
  }

  // MARK: - URL updates / lazy loading

  func updateTracks(tracks: [TrackItem]) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.updateTracksInternal(tracks: tracks) }
  }

  func getTracksById(trackIds: [String]) throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.getPlaylistManager().getTracksById(trackIds: trackIds) }
  }

  func getTracksNeedingUrls() throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.getTracksNeedingUrlsInternal() }
  }

  func getNextTracks(count: Double) throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.getNextTracksInternal(count: Int(count)) }
  }

  // MARK: - Playback speed
  func setPlaybackSpeed(speed: Double) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in try core.setPlaybackSpeedOnQueue(speed) }
  }

  func getPlaybackSpeed() throws -> any Promise<Double> {
    .parallel(core.playerQueue) { [core] in core.currentPlaybackSpeed }
  }

  // MARK: - Temporary queue v2

  func addToUpNext(trackId: String) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in try core.addToUpNextOnQueue(trackId: trackId) }
  }

  func playNext(trackId: String) throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in try core.playNextOnQueue(trackId: trackId) }
  }

  func removeFromPlayNext(trackId: String) throws -> any Promise<Bool> {
    .parallel(core.playerQueue) { [core] in core.removeFromPlayNextOnQueue(trackId: trackId) }
  }

  func removeFromUpNext(trackId: String) throws -> any Promise<Bool> {
    .parallel(core.playerQueue) { [core] in core.removeFromUpNextOnQueue(trackId: trackId) }
  }

  func clearPlayNext() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.clearPlayNextOnQueue() }
  }

  func clearUpNext() throws -> any Promise<Void> {
    .parallel(core.playerQueue) { [core] in core.clearUpNextOnQueue() }
  }

  func reorderTemporaryTrack(trackId: String, newIndex: Double) throws -> any Promise<Bool> {
    .parallel(core.playerQueue) { [core] in core.reorderTemporaryTrackOnQueue(trackId: trackId, newIndex: Int(newIndex)) }
  }

  func getPlayNextQueue() throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.playNextStack }
  }

  func getUpNextQueue() throws -> any Promise<[TrackItem]> {
    .parallel(core.playerQueue) { [core] in core.upNextQueue }
  }

  // MARK: - Android Auto (iOS no-op)

  func onAndroidAutoConnectionChange(callback: any Callback<(Bool), Void>) throws {
    // No-op on iOS
  }

  func appStartedWithNotification(callback: any Callback<(TrackItem), Void>) throws {
    // No-op on iOS — Now Playing controls never launch the app
  }

  func isAndroidAutoConnected() throws -> Bool { false }

  // MARK: - Event listeners (v2 — store IDs for cleanup)

  func onChangeTrack(callback: any Callback<(TrackItem, Reason?), Void>) throws {
    let id = core.addOnChangeTrackListener { callback($0, $1) }
    listenerIds.append(("onChangeTrack", id))
  }

  func onPlaybackStateChange(callback: any Callback<(TrackPlayerState, Reason?), Void>) throws {
    let id = core.addOnPlaybackStateChangeListener { callback($0, $1) }
    listenerIds.append(("onPlaybackStateChange", id))
  }

  func onSeek(callback: any Callback<(Double, Double), Void>) throws {
    let id = core.addOnSeekListener { callback($0, $1) }
    listenerIds.append(("onSeek", id))
  }

  func onPlaybackProgressChange(callback: any Callback<(Double, Double, Bool?), Void>) throws {
    let id = core.addOnProgressListener { callback($0, $1, $2) }
    listenerIds.append(("onPlaybackProgressChange", id))
  }

  func onTracksNeedUpdate(callback: any Callback<([TrackItem], Double), Void>) throws {
    let id = core.addOnTracksNeedUpdateListener { tracks, lookahead in
      callback(tracks, Double(lookahead))
    }
    listenerIds.append(("onTracksNeedUpdate", id))
  }

  func onTimedMetadata(callback: any Callback<(TimedMetadata), Void>) throws {
    let id = core.addOnTimedMetadataListener { callback($0) }
    listenerIds.append(("onTimedMetadata", id))
  }

  func onTemporaryQueueChange(callback: any Callback<([TrackItem], [TrackItem]), Void>) throws {
    let id = core.addOnTemporaryQueueChangeListener { callback($0, $1) }
    listenerIds.append(("onTemporaryQueueChange", id))
  }

  // MARK: - Cleanup

  deinit {
    for (type, id) in listenerIds {
      switch type {
      case "onChangeTrack":           _ = core.removeOnChangeTrackListener(id: id)
      case "onPlaybackStateChange":   _ = core.removeOnPlaybackStateChangeListener(id: id)
      case "onSeek":                  _ = core.removeOnSeekListener(id: id)
      case "onPlaybackProgressChange":_ = core.removeOnProgressListener(id: id)
      case "onTracksNeedUpdate":      _ = core.removeOnTracksNeedUpdateListener(id: id)
      case "onTemporaryQueueChange":  _ = core.removeOnTemporaryQueueChangeListener(id: id)
      case "onTimedMetadata":         _ = core.removeOnTimedMetadataListener(id: id)
      default: break
      }
    }
  }
}
