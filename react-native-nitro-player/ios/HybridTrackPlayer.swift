//
//  HybridTrackPlayer.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import Foundation
import NitroModules

final class HybridTrackPlayer: HybridTrackPlayerSpec {
  private let core: TrackPlayerCore

  override init() {
    core = TrackPlayerCore.shared
    super.init()
  }

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

  func configure(config: PlayerConfig) throws {
    core.configure(
      androidAutoEnabled: config.androidAutoEnabled,
      carPlayEnabled: config.carPlayEnabled,
      showInNotification: config.showInNotification
    )
  }

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

  func onAndroidAutoConnectionChange(callback: @escaping (Bool) -> Void) throws {
    // iOS doesn't have Android Auto, so this is a no-op
    // Always return false for isAndroidAutoConnected
  }

  func isAndroidAutoConnected() throws -> Bool {
    // iOS doesn't have Android Auto
    return false
  }
}
