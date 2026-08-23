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
    static let defaultRemoteSkipInterval: Double = 15.0
    static let supportedPlaybackRates: [Float] = [0.5, 1.0, 1.25, 1.5, 1.75, 2.0]
  }

  // MARK: - Properties

  private weak var trackPlayerCore: TrackPlayerCore?
  private let artworkCache = NSCache<NSString, UIImage>()

  private var showInNotification: Bool = true
  private var remoteSkipForwardInterval: Double = Constants.defaultRemoteSkipInterval
  private var remoteSkipBackwardInterval: Double = Constants.defaultRemoteSkipInterval

  // Tracks the artwork URL currently shown so we can discard stale async loads
  private var lastArtworkUrl: String?

  // Cached values received from playerQueue — main-thread-only reads (no sync needed)
  private var cachedTrack: TrackItem?
  private var cachedState: PlayerState?
  // Only the queue length and the current track's position are needed — never the
  // items themselves. Copying the whole queue on every state change was O(playlist)
  // per event; these two Ints are computed on playerQueue instead.
  private var cachedQueueCount: Int = 0
  private var cachedPositionInQueue: Int = -1
  private var cachedPlaybackSpeed: Double = 1.0

  init() {
    setupRemoteCommandCenter()
  }

  func setTrackPlayerCore(_ core: TrackPlayerCore) {
    trackPlayerCore = core
  }

  func configure(
    androidAutoEnabled: Bool?,
    carPlayEnabled: Bool?,
    showInNotification: Bool?,
    remoteSkipForwardInterval: Double?,
    remoteSkipBackwardInterval: Double?,
    playbackSpeed: Double?
  ) {
    if let showInNotification = showInNotification {
      self.showInNotification = showInNotification
    }
    if let playbackSpeed = sanitizedPositive(playbackSpeed) {
      cachedPlaybackSpeed = playbackSpeed
    }
    if let interval = sanitizedPositive(remoteSkipForwardInterval) {
      self.remoteSkipForwardInterval = interval
    }
    if let interval = sanitizedPositive(remoteSkipBackwardInterval) {
      self.remoteSkipBackwardInterval = interval
    }
    updateSkipCommandIntervals()
    refresh()
  }

  // MARK: - Entry point from playerQueue (called via DispatchQueue.main.async)
  //
  // Receives pre-computed values captured on playerQueue — no player access here.

  func updateFromPlayerQueue(
    track: TrackItem, state: PlayerState, queueCount: Int, positionInQueue: Int,
    playbackSpeed: Double
  ) {
    cachedTrack = track
    cachedState = state
    cachedQueueCount = queueCount
    cachedPositionInQueue = positionInQueue
    cachedPlaybackSpeed = sanitizedPositive(playbackSpeed) ?? 1.0
    refreshInternal()
  }

  // MARK: - Refresh using cached values (main thread only)

  func refresh() {
    if Thread.isMainThread {
      refreshInternal()
    } else {
      DispatchQueue.main.async { [weak self] in self?.refreshInternal() }
    }
  }

  // MARK: - Core internal update (main thread only)

  private func refreshInternal() {
    guard showInNotification else {
      clearNowPlayingInfo()
      disableAllCommands()
      return
    }

    guard let track = cachedTrack, let state = cachedState else {
      clearNowPlayingInfo()
      disableAllCommands()
      return
    }

    updateNowPlayingInfoInternal(
      track: track, state: state,
      queueCount: cachedQueueCount, positionInQueue: cachedPositionInQueue)
    updateCommandCenterState(
      state: state, queueCount: cachedQueueCount, positionInQueue: cachedPositionInQueue)
  }

  // MARK: - Now Playing Info

  private func updateNowPlayingInfoInternal(
    track: TrackItem,
    state: PlayerState,
    queueCount: Int,
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
    let playbackSpeed = sanitizedPositive(cachedPlaybackSpeed) ?? 1.0

    var nowPlayingInfo: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: safePosition,
      MPMediaItemPropertyPlaybackDuration: effectiveDuration,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackSpeed : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackSpeed,
      MPNowPlayingInfoPropertyPlaybackQueueCount: max(1, queueCount),
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

    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.togglePlayPauseCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.seekForwardCommand.removeTarget(nil)
    commandCenter.seekBackwardCommand.removeTarget(nil)
    commandCenter.changePlaybackRateCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    updateSkipCommandIntervals()
    commandCenter.changePlaybackRateCommand.supportedPlaybackRates =
      Constants.supportedPlaybackRates.map { NSNumber(value: $0) }

    // Play
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      Task { await core.play() }
      return .success
    }

    // Pause
    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      Task { await core.pause() }
      return .success
    }

    // Toggle play/pause
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      let isPlaying = self?.cachedState?.currentState == .playing
      Task { if isPlaying { await core.pause() } else { await core.play() } }
      return .success
    }

    // Next track
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      Task { await core.skipToNext() }
      return .success
    }

    // Previous track
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      guard let core = self?.trackPlayerCore else { return .commandFailed }
      Task { await core.skipToPrevious() }
      return .success
    }

    commandCenter.skipForwardCommand.isEnabled = false
    commandCenter.skipForwardCommand.addTarget { [weak self] event in
      guard let self = self, let core = self.trackPlayerCore else { return .commandFailed }
      let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? self.remoteSkipForwardInterval
      Task { await core.seekBy(offset: interval) }
      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = false
    commandCenter.skipBackwardCommand.addTarget { [weak self] event in
      guard let self = self, let core = self.trackPlayerCore else { return .commandFailed }
      let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? self.remoteSkipBackwardInterval
      Task { await core.seekBy(offset: -interval) }
      return .success
    }

    commandCenter.seekForwardCommand.isEnabled = false
    commandCenter.seekBackwardCommand.isEnabled = false

    commandCenter.changePlaybackRateCommand.isEnabled = false
    commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let core = self?.trackPlayerCore,
        let rateEvent = event as? MPChangePlaybackRateCommandEvent
      else {
        return .commandFailed
      }
      let rate = Double(rateEvent.playbackRate)
      guard rate.isFinite, rate > 0 else { return .commandFailed }
      Task {
        do {
          try await core.setPlaybackSpeed(rate)
        } catch {
          NitroPlayerLogger.log(
            "MediaSessionManager", "❌ Failed to set remote playback rate: \(error)")
        }
      }
      return .success
    }

    // Scrubber
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let core = self?.trackPlayerCore,
        let positionEvent = event as? MPChangePlaybackPositionCommandEvent
      else {
        return .commandFailed
      }
      // Optimistically freeze the scrubber at the tapped position
      if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionEvent.positionTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
      }
      Task { await core.seek(position: positionEvent.positionTime) }
      return .success
    }
  }

  private func updateCommandCenterState(
    state: PlayerState,
    queueCount: Int,
    positionInQueue: Int
  ) {
    let commandCenter = MPRemoteCommandCenter.shared()
    let hasCurrentTrack = positionInQueue >= 0
    let isNotLast = positionInQueue < queueCount - 1

    let playerDuration = state.totalDuration
    let hasDuration = playerDuration > 0 && !playerDuration.isNaN && !playerDuration.isInfinite

    commandCenter.nextTrackCommand.isEnabled = hasCurrentTrack && isNotLast
    commandCenter.previousTrackCommand.isEnabled = hasCurrentTrack
    commandCenter.skipForwardCommand.isEnabled = hasCurrentTrack
    commandCenter.skipBackwardCommand.isEnabled = hasCurrentTrack
    commandCenter.changePlaybackRateCommand.isEnabled = hasCurrentTrack
    commandCenter.changePlaybackPositionCommand.isEnabled = hasCurrentTrack && hasDuration
  }

  private func disableAllCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = false
    commandCenter.skipBackwardCommand.isEnabled = false
    commandCenter.changePlaybackRateCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
  }

  // MARK: - Helpers

  private func sanitizedPositive(_ value: Double?) -> Double? {
    guard let value = value, value.isFinite, value > 0 else { return nil }
    return value
  }

  private func updateSkipCommandIntervals() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.skipForwardCommand.preferredIntervals = [
      NSNumber(value: remoteSkipForwardInterval)
    ]
    commandCenter.skipBackwardCommand.preferredIntervals = [
      NSNumber(value: remoteSkipBackwardInterval)
    ]
  }

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
