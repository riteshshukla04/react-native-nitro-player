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
    static let artworkSize: CGFloat = 500.0
  }

  // MARK: - Properties

  private var trackPlayerCore: TrackPlayerCore?
  private let artworkCache = NSCache<NSString, UIImage>()

  private var showInNotification: Bool = true

  // Tracks the artwork URL currently shown so we can discard stale async loads
  private var lastArtworkUrl: String?

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
    if let showInNotification = showInNotification {
      self.showInNotification = showInNotification
    }
    refresh()
  }

  // MARK: - Single refresh entry point
  //
  // All public callbacks route here. Always dispatches to main thread so
  // MPNowPlayingInfoCenter and MPRemoteCommandCenter are only touched from main.

  func refresh() {
    if Thread.isMainThread {
      refreshInternal()
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.refreshInternal()
      }
    }
  }

  // Convenience aliases used by TrackPlayerCore call sites
  func updateNowPlayingInfo() { refresh() }
  func onTrackChanged() { refresh() }
  func onPlaybackStateChanged() { refresh() }
  func onQueueChanged() { refresh() }

  // MARK: - Core internal update (main thread only)

  private func refreshInternal() {
    guard showInNotification else {
      clearNowPlayingInfo()
      disableAllCommands()
      return
    }

    guard let core = trackPlayerCore,
      let track = core.getCurrentTrack()
    else {
      clearNowPlayingInfo()
      disableAllCommands()
      return
    }

    // Fetch snapshot once — both calls are cheap on main thread (no sync overhead)
    let state = core.getState()
    let queue = core.getActualQueue()

    // Find the actual position of the current track inside the actual queue.
    // state.currentIndex is the original-playlist index which is wrong when a
    // temp (playNext / upNext) track is playing.
    let positionInQueue = queue.firstIndex(where: { $0.id == track.id }) ?? -1

    updateNowPlayingInfoInternal(track: track, state: state, queue: queue, positionInQueue: positionInQueue)
    updateCommandCenterState(state: state, queue: queue, positionInQueue: positionInQueue)
  }

  // MARK: - Now Playing Info

  private func updateNowPlayingInfoInternal(
    track: TrackItem,
    state: PlayerState,
    queue: [TrackItem],
    positionInQueue: Int
  ) {
    let playerDuration = state.totalDuration
    let effectiveDuration: Double
    if playerDuration > 0 && !playerDuration.isNaN && !playerDuration.isInfinite {
      effectiveDuration = playerDuration
    } else if track.duration > 0 {
      effectiveDuration = track.duration
    } else {
      effectiveDuration = 0
    }

    let currentPosition = state.currentPosition
    let safePosition = currentPosition.isNaN || currentPosition.isInfinite ? 0 : currentPosition
    let isPlaying = state.currentState == .playing

    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: safePosition,
      MPMediaItemPropertyPlaybackDuration: effectiveDuration,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
      MPNowPlayingInfoPropertyPlaybackQueueCount: max(1, queue.count),
      MPNowPlayingInfoPropertyPlaybackQueueIndex: max(0, positionInQueue),
    ]

    // Artwork: use cache synchronously when available, otherwise kick off async load
    if let artwork = track.artwork, case .second(let artworkUrl) = artwork {
      lastArtworkUrl = artworkUrl
      if let cachedImage = artworkCache.object(forKey: artworkUrl as NSString) {
        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
          boundsSize: CGSize(width: Constants.artworkSize, height: Constants.artworkSize),
          requestHandler: { _ in cachedImage }
        )
      } else {
        // Write info first without artwork, then patch it in when loaded
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        loadArtwork(url: artworkUrl) { [weak self] image in
          guard let self = self, let image = image else { return }
          // Discard if track changed while loading
          guard self.lastArtworkUrl == artworkUrl else { return }
          var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
          updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
            boundsSize: CGSize(width: Constants.artworkSize, height: Constants.artworkSize),
            requestHandler: { _ in image }
          )
          MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
        }
        return
      }
    } else {
      lastArtworkUrl = nil
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  // MARK: - Command Center State

  private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    // Clear any previously registered targets before adding fresh ones.
    // Prevents duplicate handlers if this were ever called more than once.
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.seekForwardCommand.removeTarget(nil)
    commandCenter.seekBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    // Play
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      core.play()
      return .success
    }

    // Pause
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      core.pause()
      return .success
    }

    // Toggle play/pause
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      if core.getState().currentState == .playing {
        core.pause()
      } else {
        core.play()
      }
      return .success
    }

    // Next track — isEnabled managed dynamically in updateCommandCenterState
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      core.skipToNext()
      return .success
    }

    // Previous track — isEnabled managed dynamically in updateCommandCenterState
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      core.skipToPrevious()
      return .success
    }

    // Disable skip-forward/backward — these replace the scrubber with non-interactive buttons
    commandCenter.seekForwardCommand.isEnabled = false
    commandCenter.seekBackwardCommand.isEnabled = false

    // Scrubber — isEnabled managed dynamically based on known duration
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let self = self,
        let core = self.trackPlayerCore,
        let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else {
        return .commandFailed
      }
      // Optimistically freeze the scrubber at the tapped position while the async
      // seek is in flight — updateNowPlayingInfo in the seek completion restores it.
      if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionEvent.positionTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
      core.seek(position: positionEvent.positionTime)
      return .success
    }
  }

  private func updateCommandCenterState(
    state: PlayerState,
    queue: [TrackItem],
    positionInQueue: Int
  ) {
    let commandCenter = MPRemoteCommandCenter.shared()
    let hasCurrentTrack = positionInQueue >= 0
    let isNotLast = positionInQueue < queue.count - 1

    let playerDuration = state.totalDuration
    let hasDuration = playerDuration > 0 && !playerDuration.isNaN && !playerDuration.isInfinite

    // Next: only enabled when there is a track after the current one
    commandCenter.nextTrackCommand.isEnabled = hasCurrentTrack && isNotLast

    // Previous: always enabled when something is playing — either restarts current or goes back
    commandCenter.previousTrackCommand.isEnabled = hasCurrentTrack

    // Scrubber: only enabled when we have a known, finite duration
    commandCenter.changePlaybackPositionCommand.isEnabled = hasCurrentTrack && hasDuration
  }

  private func disableAllCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
  }

  // MARK: - Helpers

  private func clearNowPlayingInfo() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    lastArtworkUrl = nil
  }

  private func loadArtwork(url: String, completion: @escaping (UIImage?) -> Void) {
    if let cached = artworkCache.object(forKey: url as NSString) {
      completion(cached)
      return
    }

    guard let imageUrl = URL(string: url) else {
      completion(nil)
      return
    }

    URLSession.shared.dataTask(with: imageUrl) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else {
        DispatchQueue.main.async { completion(nil) }
        return
      }
      DispatchQueue.main.async {
        self?.artworkCache.setObject(image, forKey: url as NSString)
        completion(image)
      }
    }.resume()
  }

  func release() {
    clearNowPlayingInfo()
    disableAllCommands()
    artworkCache.removeAllObjects()
  }
}
