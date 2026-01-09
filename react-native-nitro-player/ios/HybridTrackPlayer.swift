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

  func playSong(songId: String, fromPlaylist: String?) throws {
    core.playSong(songId: songId, fromPlaylist: fromPlaylist)
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

  func getState() throws -> PlayerState {
    return core.getState()
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
    print("🎯 HybridTrackPlayer: onChangeTrack callback registered")
    core.onChangeTrack = callback
  }

  func onPlaybackStateChange(callback: @escaping (TrackPlayerState, Reason?) -> Void) throws {
    print("🎯 HybridTrackPlayer: onPlaybackStateChange callback registered")
    core.onPlaybackStateChange = callback
  }

  func onSeek(callback: @escaping (Double, Double) -> Void) throws {
    print("🎯 HybridTrackPlayer: onSeek callback registered")
    core.onSeek = callback
  }

  func onPlaybackProgressChange(callback: @escaping (Double, Double, Bool?) -> Void) throws {
    print("🎯 HybridTrackPlayer: onPlaybackProgressChange callback registered")
    core.onPlaybackProgressChange = callback
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

  // MARK: - Volume Control

  func setVolume(volume: Double) throws -> Bool {
    return core.setVolume(volume: volume)
  }
}
