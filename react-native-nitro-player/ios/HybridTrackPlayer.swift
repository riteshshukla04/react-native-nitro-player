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

  // MARK: - Initialization

  override init() {
    core = TrackPlayerCore.shared
    super.init()
  }

  // MARK: - Playback Control

  func play() throws {
    core.play()
  }

  func pause() throws {
    core.pause()
  }

  func playSong(songId: String, fromPlaylist: String?) throws -> Promise<Void> {
    return Promise.async {
      self.core.playSong(songId: songId, fromPlaylist: fromPlaylist)
    }
  }

  func skipToNext() throws {
    core.skipToNext()
  }

  func skipToPrevious() throws {
    core.skipToPrevious()
  }

  func seek(position: Double) throws {
    core.seek(position: position)
  }

  func addToUpNext(trackId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.addToUpNext(trackId: trackId)
    }
  }

  func playNext(trackId: String) throws -> Promise<Void> {
    return Promise.async {
      self.core.playNext(trackId: trackId)
    }
  }

  func getActualQueue() throws -> Promise<[TrackItem]> {
    return Promise.async {
      return self.core.getActualQueue()
    }
  }

  func getState() throws -> Promise<PlayerState> {
    return Promise.async {
      return self.core.getState()
    }
  }

  func setRepeatMode(mode: RepeatMode) throws -> Bool {
    return core.setRepeatMode(mode: mode)
  }

  // MARK: - Configuration

  func configure(config: PlayerConfig) throws {
    core.configure(
      androidAutoEnabled: config.androidAutoEnabled,
      carPlayEnabled: config.carPlayEnabled,
      showInNotification: config.showInNotification
    )
  }

  // MARK: - Event Callbacks

  func onChangeTrack(callback: @escaping (TrackItem, Reason?) -> Void) throws {
    NitroPlayerLogger.log("HybridTrackPlayer", "onChangeTrack callback registered")
    core.addOnChangeTrackListener(owner: self, callback)
  }

  func onPlaybackStateChange(callback: @escaping (TrackPlayerState, Reason?) -> Void) throws {
    NitroPlayerLogger.log("HybridTrackPlayer", "onPlaybackStateChange callback registered")
    core.addOnPlaybackStateChangeListener(owner: self, callback)
  }

  func onSeek(callback: @escaping (Double, Double) -> Void) throws {
    NitroPlayerLogger.log("HybridTrackPlayer", "onSeek callback registered")
    core.addOnSeekListener(owner: self, callback)
  }

  func onPlaybackProgressChange(callback: @escaping (Double, Double, Bool?) -> Void) throws {
    NitroPlayerLogger.log("HybridTrackPlayer", "onPlaybackProgressChange callback registered")
    core.addOnPlaybackProgressChangeListener(owner: self, callback)
  }

  // MARK: - Android Auto (iOS No-op)

  /// iOS doesn't support Android Auto, so this is a no-op
  /// - Parameter callback: Callback that will never be invoked
  func onAndroidAutoConnectionChange(callback: @escaping (Bool) -> Void) throws {
    // iOS doesn't have Android Auto, so this is a no-op
  }

  /// iOS doesn't support Android Auto, always returns false
  /// - Returns: Always returns false on iOS
  func isAndroidAutoConnected() throws -> Bool {
    return false
  }

  func skipToIndex(index: Double) throws -> Promise<Bool> {
    return Promise.async {
      return self.core.skipToIndex(index: Int(index))
    }
  }

  // MARK: - Volume Control

  func setVolume(volume: Double) throws -> Bool {
    return core.setVolume(volume: volume)
  }
}
