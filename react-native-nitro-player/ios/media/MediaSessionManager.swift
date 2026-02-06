//
//  MediaSessionManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import AVFoundation
import Foundation
import MediaPlayer
import NitroModules
import UIKit

class MediaSessionManager {
  // MARK: - Constants

  private enum Constants {
    // Seek intervals (in seconds)
    static let seekInterval: Double = 10.0

    // Artwork size
    static let artworkSize: CGFloat = 500.0
  }

  // MARK: - Properties

  private var trackPlayerCore: TrackPlayerCore?
  private var artworkCache: [String: UIImage] = [:]

  private var androidAutoEnabled: Bool = false
  private var carPlayEnabled: Bool = false
  private var showInNotification: Bool = true

  init() {
    setupRemoteCommandCenter()
  }

  func setTrackPlayerCore(_ core: TrackPlayerCore) {
    trackPlayerCore = core
  }

  func configure(
    androidAutoEnabled: Bool?,
    carPlayEnabled: Bool?,
    showInNotification: Bool?
  ) {
    if let androidAutoEnabled = androidAutoEnabled {
      self.androidAutoEnabled = androidAutoEnabled
    }
    if let carPlayEnabled = carPlayEnabled {
      self.carPlayEnabled = carPlayEnabled
      // CarPlay is handled by the app's CarPlaySceneDelegate
      // We just maintain the flag here for reference
    }
    if let showInNotification = showInNotification {
      self.showInNotification = showInNotification
      if showInNotification {
        updateNowPlayingInfo()
      } else {
        clearNowPlayingInfo()
      }
    }
  }

  private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    // Play command
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.trackPlayerCore?.play()
      return .success
    }

    // Pause command
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.trackPlayerCore?.pause()
      return .success
    }

    // Toggle play/pause
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self = self, let core = self.trackPlayerCore else { return .commandFailed }
      let state = core.getState()
      if state.currentState == .playing {
        core.pause()
      } else {
        core.play()
      }
      return .success
    }

    // Next track command
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.trackPlayerCore?.skipToNext()
      return .success
    }

    // Previous track command
    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.trackPlayerCore?.skipToPrevious()
      return .success
    }

    // Disable continuous seek commands - they replace the interactive scrubber
    // with non-interactive forward/backward buttons on the lock screen
    commandCenter.seekForwardCommand.isEnabled = false
    commandCenter.seekBackwardCommand.isEnabled = false

    // Change playback position (interactive scrubber)
    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self = self,
        let core = self.trackPlayerCore,
        let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else {
        return .commandFailed
      }
      // Immediately update elapsed time AND set playback rate to 0 during seek
      // This prevents the scrubber from freezing/desyncing during the async seek operation
      if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionEvent.positionTime
        // Set rate to 0 to pause scrubber animation during seek
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
      core.seek(position: positionEvent.positionTime)
      return .success
    }
  }

  private func getCurrentTrack() -> TrackItem? {
    return trackPlayerCore?.getCurrentTrack()
  }

  func updateNowPlayingInfo() {
    guard showInNotification else { return }

    guard let track = getCurrentTrack(),
      let core = trackPlayerCore
    else {
      clearNowPlayingInfo()
      return
    }

    let state = core.getState()

    // Use player duration if valid, otherwise fall back to track metadata duration.
    // Duration must always be present for the lock screen scrubber to be interactive.
    let playerDuration = state.totalDuration
    let effectiveDuration: Double
    if playerDuration > 0 && !playerDuration.isNaN && !playerDuration.isInfinite {
      effectiveDuration = playerDuration
    } else {
      effectiveDuration = track.duration
    }

    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentPosition,
      MPMediaItemPropertyPlaybackDuration: effectiveDuration,
      MPNowPlayingInfoPropertyPlaybackRate: state.currentState == .playing ? 1.0 : 0.0,
    ]

    // Add artwork synchronously if cached, otherwise load async
    if let artwork = track.artwork, case .second(let artworkUrl) = artwork {
      if let cachedImage = artworkCache[artworkUrl] {
        // Artwork is cached - include it directly to avoid overwrite race condition
        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
          boundsSize: CGSize(width: Constants.artworkSize, height: Constants.artworkSize),
          requestHandler: { _ in cachedImage }
        )
      } else {
        // Artwork not cached - load asynchronously and update later
        loadArtwork(url: artworkUrl) { [weak self] image in
          guard let self = self, let image = image else { return }
          // Re-read current nowPlayingInfo to avoid overwriting other updates
          var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
          updatedInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: CGSize(width: Constants.artworkSize, height: Constants.artworkSize),
            requestHandler: { _ in image }
          )
          MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
        }
      }
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func clearNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func loadArtwork(url: String, completion: @escaping (UIImage?) -> Void) {
    // Check cache first
    if let cached = artworkCache[url] {
      completion(cached)
      return
    }

    guard let imageUrl = URL(string: url) else {
      completion(nil)
      return
    }

    // Load image asynchronously
    URLSession.shared.dataTask(with: imageUrl) { [weak self] data, _, _ in
      guard let data = data,
        let image = UIImage(data: data)
      else {
        completion(nil)
        return
      }

      // Cache the image
      self?.artworkCache[url] = image
      DispatchQueue.main.async {
        completion(image)
      }
    }.resume()
  }

  func onTrackChanged() {
    updateNowPlayingInfo()
  }

  func onPlaybackStateChanged() {
    updateNowPlayingInfo()
  }

  func release() {
    clearNowPlayingInfo()
    artworkCache.removeAll()
  }
}
