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

  override init() {
    core = TrackPlayerCore.shared
    super.init()
  }

  // MARK: - Ordered dispatch
  //
  // `Promise.async` starts an unordered Task, so the hop onto the player queue used
  // to happen at an arbitrary later point: two calls made in order from JS could
  // reach the player in reverse order (play-then-pause landing as pause-then-play).
  // Enqueueing synchronously here — on the JS thread, at call time — makes the serial
  // queue's FIFO order equal the JS call order.

  private func enqueue<T>(_ block: @escaping () -> T) -> Promise<T> {
    let promise = Promise<T>()
    core.playerQueue.async { promise.resolve(withResult: block()) }
    return promise
  }

  private func enqueueThrowing<T>(_ block: @escaping () throws -> T) -> Promise<T> {
    let promise = Promise<T>()
    core.playerQueue.async {
      do { promise.resolve(withResult: try block()) }
      catch { promise.reject(withError: error) }
    }
    return promise
  }

  // MARK: - Playback Control (async Promise<Void>)

  func play() throws -> Promise<Void> {
    enqueue { self.core.playOnQueue() }
  }

  func pause() throws -> Promise<Void> {
    enqueue { self.core.pauseOnQueue() }
  }

  func seek(position: Double) throws -> Promise<Void> {
    enqueue { self.core.seekOnQueue(position: position) }
  }

  func skipToNext() throws -> Promise<Void> {
    enqueue { self.core.skipToNextOnQueue() }
  }

  func skipToPrevious() throws -> Promise<Void> {
    enqueue { self.core.skipToPreviousOnQueue() }
  }

  func playSong(songId: String, fromPlaylist: String?) throws -> Promise<Void> {
    enqueue { self.core.playSongInternal(songId: songId, fromPlaylist: fromPlaylist) }
  }

  func skipToIndex(index: Double) throws -> Promise<Bool> {
    enqueue { self.core.skipToIndexOnQueue(index: Int(index)) }
  }

  // MARK: - Repeat / Volume / Config

  func setRepeatMode(mode: RepeatMode) throws -> Promise<Void> {
    enqueue { self.core.setRepeatModeOnQueue(mode: mode) }
  }

  func getRepeatMode() throws -> RepeatMode {
    core.getRepeatMode()
  }

  func setVolume(volume: Double) throws -> Promise<Void> {
    enqueue { self.core.setVolumeOnQueue(volume: volume) }
  }

  func configure(config: PlayerConfig) throws -> Promise<Void> {
    enqueue {
      self.core.configureOnQueue(
        androidAutoEnabled: config.androidAutoEnabled,
        carPlayEnabled: config.carPlayEnabled,
        showInNotification: config.showInNotification,
        lookaheadCount: config.lookaheadCount.map { Int($0) }
      )
    }
  }

  // MARK: - Queue / State reads

  func getActualQueue() throws -> Promise<[TrackItem]> {
    enqueue { self.core.getActualQueueInternal() }
  }

  func getState() throws -> Promise<PlayerState> {
    enqueue { self.core.getStateInternal() }
  }

  func getCurrentTrackIndex() throws -> Promise<Double> {
    enqueue { Double(self.core.currentTrackIndex) }
  }

  // MARK: - URL updates / lazy loading

  func updateTracks(tracks: [TrackItem]) throws -> Promise<Void> {
    enqueue { self.core.updateTracksInternal(tracks: tracks) }
  }

  func getTracksById(trackIds: [String]) throws -> Promise<[TrackItem]> {
    enqueue { self.core.getPlaylistManager().getTracksById(trackIds: trackIds) }
  }

  func getTracksNeedingUrls() throws -> Promise<[TrackItem]> {
    enqueue { self.core.getTracksNeedingUrlsInternal() }
  }

  func getNextTracks(count: Double) throws -> Promise<[TrackItem]> {
    enqueue { self.core.getNextTracksInternal(count: Int(count)) }
  }

  // MARK: - Playback speed
  func setPlaybackSpeed(speed: Double) throws -> Promise<Void> {
    enqueue { self.core.setPlaybackSpeedOnQueue(speed) }
  }

  func getPlaybackSpeed() throws -> Promise<Double> {
    enqueue { self.core.currentPlaybackSpeed }
  }

  // MARK: - Temporary queue v2

  func addToUpNext(trackId: String) throws -> Promise<Void> {
    enqueueThrowing { try self.core.addToUpNextOnQueue(trackId: trackId) }
  }

  func playNext(trackId: String) throws -> Promise<Void> {
    enqueueThrowing { try self.core.playNextOnQueue(trackId: trackId) }
  }

  func removeFromPlayNext(trackId: String) throws -> Promise<Bool> {
    enqueue { self.core.removeFromPlayNextOnQueue(trackId: trackId) }
  }

  func removeFromUpNext(trackId: String) throws -> Promise<Bool> {
    enqueue { self.core.removeFromUpNextOnQueue(trackId: trackId) }
  }

  func clearPlayNext() throws -> Promise<Void> {
    enqueue { self.core.clearPlayNextOnQueue() }
  }

  func clearUpNext() throws -> Promise<Void> {
    enqueue { self.core.clearUpNextOnQueue() }
  }

  func reorderTemporaryTrack(trackId: String, newIndex: Double) throws -> Promise<Bool> {
    enqueue { self.core.reorderTemporaryTrackOnQueue(trackId: trackId, newIndex: Int(newIndex)) }
  }

  func getPlayNextQueue() throws -> Promise<[TrackItem]> {
    enqueue { self.core.playNextStack }
  }

  func getUpNextQueue() throws -> Promise<[TrackItem]> {
    enqueue { self.core.upNextQueue }
  }

  // MARK: - Android Auto (iOS no-op)

  func onAndroidAutoConnectionChange(callback: @escaping (Bool) -> Void) throws {
    // No-op on iOS
  }

  func isAndroidAutoConnected() throws -> Bool { false }

  // MARK: - Event listeners (v2 — store IDs for cleanup)

  func onChangeTrack(callback: @escaping (_ track: TrackItem, _ reason: Reason?) -> Void) throws {
    let id = core.addOnChangeTrackListener(callback)
    listenerIds.append(("onChangeTrack", id))
  }

  func onPlaybackStateChange(callback: @escaping (_ state: TrackPlayerState, _ reason: Reason?) -> Void) throws {
    let id = core.addOnPlaybackStateChangeListener(callback)
    listenerIds.append(("onPlaybackStateChange", id))
  }

  func onSeek(callback: @escaping (_ position: Double, _ totalDuration: Double) -> Void) throws {
    let id = core.addOnSeekListener(callback)
    listenerIds.append(("onSeek", id))
  }

  func onPlaybackProgressChange(callback: @escaping (_ position: Double, _ totalDuration: Double, _ isManuallySeeked: Bool?) -> Void) throws {
    let id = core.addOnProgressListener(callback)
    listenerIds.append(("onPlaybackProgressChange", id))
  }

  func onTracksNeedUpdate(callback: @escaping (_ tracks: [TrackItem], _ lookahead: Double) -> Void) throws {
    let id = core.addOnTracksNeedUpdateListener { tracks, lookahead in
      callback(tracks, Double(lookahead))
    }
    listenerIds.append(("onTracksNeedUpdate", id))
  }

  func onTemporaryQueueChange(callback: @escaping (_ playNextQueue: [TrackItem], _ upNextQueue: [TrackItem]) -> Void) throws {
    let id = core.addOnTemporaryQueueChangeListener(callback)
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
      default: break
      }
    }
  }
}
