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

#if canImport(CarPlay)
  import CarPlay
#endif

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
  private var preferRemoteSkipIntervals = false

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
  private var cachedRepeatMode: RepeatMode = .off

  // Buttons from PlayerConfig.notificationButtons — main-thread-only, like the cache above
  private var lockScreenButtons: [LockScreenButton] = []
  private var carPlayButtons: [CarPlayButton] = []
  private let buttonStates = NotificationButtonStates()
  // What CarPlay shows now; nil until the app configures CarPlay buttons, so its own are left alone
  private var carPlayButtonsShown: [String]?
  private var carPlayConnectObserver: NSObjectProtocol?

  init() {
    setupRemoteCommandCenter()
    #if canImport(CarPlay)
      // CarPlay buttons are pushed when CarPlay connects; until then CarPlay is never touched
      carPlayConnectObserver = NotificationCenter.default.addObserver(
        forName: UIScene.willConnectNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard #available(iOS 14.0, *),
          (notification.object as? UIScene)?.session.role == .carTemplateApplication
        else { return }
        // After the scene finishes connecting, so CarPlay's Now Playing template exists
        DispatchQueue.main.async { self?.updateCarPlayButtons(force: true) }
      }
    #endif
  }

  deinit {
    if let observer = carPlayConnectObserver { NotificationCenter.default.removeObserver(observer) }
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
    preferRemoteSkipIntervals: Bool?,
    playbackSpeed: Double?
  ) {
    if let showInNotification = showInNotification {
      self.showInNotification = showInNotification
    }
    if let preferRemoteSkipIntervals = preferRemoteSkipIntervals {
      self.preferRemoteSkipIntervals = preferRemoteSkipIntervals
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
    playbackSpeed: Double, repeatMode: RepeatMode
  ) {
    cachedTrack = track
    cachedState = state
    cachedQueueCount = queueCount
    cachedPositionInQueue = positionInQueue
    cachedPlaybackSpeed = sanitizedPositive(playbackSpeed) ?? 1.0
    cachedRepeatMode = repeatMode
    refreshInternal()
  }

  // MARK: - Notification buttons (main thread only)

  func setNotificationButtons(_ config: IOSButtonConfig) {
    lockScreenButtons = config.lockScreen
    carPlayButtons = config.carPlay
    refreshInternal()
  }

  func setNotificationButtonState(buttonId: String, trackIds: [String]?, isActive: Bool) {
    buttonStates.set(buttonId, trackIds: trackIds, isActive: isActive)
    refreshInternal()
  }

  private func lockScreenButton(for command: LockScreenCommand) -> LockScreenButton? {
    lockScreenButtons.first { $0.command == command }
  }

  private var feedbackCommands: [(MPFeedbackCommand, LockScreenCommand, String)] {
    let commandCenter = MPRemoteCommandCenter.shared()
    return [
      (commandCenter.likeCommand, .like, "Like"),
      (commandCenter.dislikeCommand, .dislike, "Dislike"),
      (commandCenter.bookmarkCommand, .bookmark, "Bookmark"),
    ]
  }

  /// Records a toggle pressed for the current track, redraws, and reports it
  private func pressToggle(_ buttonId: String, isActive: Bool) -> MPRemoteCommandHandlerStatus {
    guard let track = cachedTrack else { return .commandFailed }
    buttonStates.setFromPress(buttonId, trackId: track.id, isActive: isActive)
    refreshInternal()
    trackPlayerCore?.notifyNotificationButtonPress(
      buttonId, track, NotificationButtonEvent(isActive: isActive, rating: nil, repeatMode: nil))
    return .success
  }

  private static func repeatMode(from type: MPRepeatType) -> RepeatMode {
    switch type {
    case .one: return .track
    case .all: return .playlist
    default: return .off
    }
  }

  private static func repeatType(from mode: RepeatMode) -> MPRepeatType {
    switch mode {
    case .track: return .one
    case .playlist: return .all
    default: return .off
    }
  }

  private func updateCarPlayButtons(force: Bool = false) {
    #if canImport(CarPlay)
      guard #available(iOS 14.0, *) else { return }
      guard !carPlayButtons.isEmpty || carPlayButtonsShown != nil else { return }
      // Only with CarPlay connected: that needs the CarPlay entitlement, and the buttons only show there
      guard
        UIApplication.shared.connectedScenes.contains(where: {
          $0.session.role == .carTemplateApplication
        })
      else { return }
      let trackId = cachedTrack?.id
      let looks = carPlayButtons.map { button -> String in
        let isActive = buttonStates.isActive(button.id, trackId: trackId)
        switch button.type ?? .image {
        case .image:
          guard let activeIcon = button.activeIcon, isActive else { return button.icon ?? "" }
          return activeIcon
        case .repeat: return cachedRepeatMode.stringValue
        case .playbackrate, .more: return ""
        case .shuffle, .addtolibrary: return isActive ? "on" : "off"
        }
      }
      // Refreshes run on every state change; only push when what CarPlay shows changes
      let shown = zip(carPlayButtons, looks).map { "\($0.id)=\($1)" }
      guard force || shown != carPlayButtonsShown else { return }
      carPlayButtonsShown = shown
      let buttons = zip(carPlayButtons, looks).compactMap { button, look -> CPNowPlayingButton? in
        let id = button.id
        let handler: (CPNowPlayingButton) -> Void = { [weak self] _ in self?.onCarPlayButtonPress(id) }
        switch button.type ?? .image {
        case .image:
          guard let image = IOSButtonConfig.image(named: look) else { return nil }
          return CPNowPlayingImageButton(image: image, handler: handler)
        case .shuffle:
          let shuffle = CPNowPlayingShuffleButton(handler: handler)
          shuffle.isSelected = look == "on"
          return shuffle
        case .addtolibrary:
          let addToLibrary = CPNowPlayingAddToLibraryButton(handler: handler)
          addToLibrary.isSelected = look == "on"
          return addToLibrary
        case .repeat:
          let repeatButton = CPNowPlayingRepeatButton(handler: handler)
          repeatButton.isSelected = cachedRepeatMode != .off
          return repeatButton
        case .playbackrate:
          return CPNowPlayingPlaybackRateButton(handler: handler)
        case .more:
          return CPNowPlayingMoreButton(handler: handler)
        }
      }
      CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    #endif
  }

  private func onCarPlayButtonPress(_ buttonId: String) {
    guard let button = carPlayButtons.first(where: { $0.id == buttonId }),
      let track = cachedTrack
    else { return }
    switch button.type ?? .image {
    case .image where button.activeIcon != nil, .shuffle, .addtolibrary:
      _ = pressToggle(buttonId, isActive: !buttonStates.isActive(buttonId, trackId: track.id))
    case .repeat:
      let mode = Self.nextRepeatMode(after: cachedRepeatMode)
      cachedRepeatMode = mode
      refreshInternal()
      guard let core = trackPlayerCore else { return }
      Task {
        await core.setRepeatMode(mode: mode)
        core.notifyNotificationButtonPress(
          buttonId, track, NotificationButtonEvent(isActive: nil, rating: nil, repeatMode: mode))
      }
    case .playbackrate:
      let rates = Constants.supportedPlaybackRates.map(Double.init)
      let current = rates.firstIndex { abs($0 - cachedPlaybackSpeed) < 0.01 } ?? rates.firstIndex(of: 1.0) ?? 0
      let speed = rates[(current + 1) % rates.count]
      // The next press may come before the player reports the new speed
      cachedPlaybackSpeed = speed
      guard let core = trackPlayerCore else { return }
      Task {
        try? await core.setPlaybackSpeed(speed)
        core.notifyNotificationButtonPress(
          buttonId, track, NotificationButtonEvent(isActive: nil, rating: nil, repeatMode: nil))
      }
    default:
      trackPlayerCore?.notifyNotificationButtonPress(
        buttonId, track, NotificationButtonEvent(isActive: nil, rating: nil, repeatMode: nil))
    }
  }

  private static func nextRepeatMode(after mode: RepeatMode) -> RepeatMode {
    switch mode {
    case .off: return .playlist
    case .playlist: return .track
    default: return .off
    }
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
    updateCarPlayButtons()
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
    commandCenter.likeCommand.removeTarget(nil)
    commandCenter.dislikeCommand.removeTarget(nil)
    commandCenter.bookmarkCommand.removeTarget(nil)
    commandCenter.ratingCommand.removeTarget(nil)
    commandCenter.changeRepeatModeCommand.removeTarget(nil)
    commandCenter.changeShuffleModeCommand.removeTarget(nil)

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

    // Lock screen buttons from PlayerConfig.notificationButtons — off until configured
    for (command, kind, _) in feedbackCommands {
      command.isEnabled = false
      command.addTarget { [weak self] event in
        guard let self = self, let button = self.lockScreenButton(for: kind) else {
          return .commandFailed
        }
        let isNegative = (event as? MPFeedbackCommandEvent)?.isNegative ?? false
        return self.pressToggle(button.id, isActive: !isNegative)
      }
    }

    commandCenter.ratingCommand.isEnabled = false
    commandCenter.ratingCommand.minimumRating = 0
    commandCenter.ratingCommand.maximumRating = 5
    commandCenter.ratingCommand.addTarget { [weak self] event in
      guard let self = self, let button = self.lockScreenButton(for: .rating),
        let track = self.cachedTrack, let ratingEvent = event as? MPRatingCommandEvent
      else {
        return .commandFailed
      }
      self.trackPlayerCore?.notifyNotificationButtonPress(
        button.id, track,
        NotificationButtonEvent(isActive: nil, rating: Double(ratingEvent.rating), repeatMode: nil))
      return .success
    }

    commandCenter.changeRepeatModeCommand.isEnabled = false
    commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
      guard let self = self, let core = self.trackPlayerCore,
        let button = self.lockScreenButton(for: .repeat), let track = self.cachedTrack,
        let repeatEvent = event as? MPChangeRepeatModeCommandEvent
      else {
        return .commandFailed
      }
      let mode = Self.repeatMode(from: repeatEvent.repeatType)
      self.cachedRepeatMode = mode
      self.refreshInternal()
      let buttonId = button.id
      Task {
        await core.setRepeatMode(mode: mode)
        core.notifyNotificationButtonPress(
          buttonId, track, NotificationButtonEvent(isActive: nil, rating: nil, repeatMode: mode))
      }
      return .success
    }

    commandCenter.changeShuffleModeCommand.isEnabled = false
    commandCenter.changeShuffleModeCommand.addTarget { [weak self] event in
      guard let self = self, let button = self.lockScreenButton(for: .shuffle),
        let shuffleEvent = event as? MPChangeShuffleModeCommandEvent
      else {
        return .commandFailed
      }
      return self.pressToggle(button.id, isActive: shuffleEvent.shuffleType != .off)
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
    // iOS shows enabled skip-interval commands in place of next/previous, so they stay off unless the app prefers them
    commandCenter.skipForwardCommand.isEnabled = hasCurrentTrack && preferRemoteSkipIntervals
    commandCenter.skipBackwardCommand.isEnabled = hasCurrentTrack && preferRemoteSkipIntervals
    commandCenter.changePlaybackRateCommand.isEnabled = hasCurrentTrack
    commandCenter.changePlaybackPositionCommand.isEnabled = hasCurrentTrack && hasDuration

    let trackId = cachedTrack?.id
    for (command, kind, defaultTitle) in feedbackCommands {
      let button = lockScreenButton(for: kind)
      command.isEnabled = hasCurrentTrack && button != nil
      if let button = button {
        command.isActive = buttonStates.isActive(button.id, trackId: trackId)
        command.localizedTitle = button.title ?? defaultTitle
      }
    }
    commandCenter.ratingCommand.isEnabled = hasCurrentTrack && lockScreenButton(for: .rating) != nil
    commandCenter.changeRepeatModeCommand.isEnabled =
      hasCurrentTrack && lockScreenButton(for: .repeat) != nil
    commandCenter.changeRepeatModeCommand.currentRepeatType = Self.repeatType(from: cachedRepeatMode)
    let shuffleButton = lockScreenButton(for: .shuffle)
    commandCenter.changeShuffleModeCommand.isEnabled = hasCurrentTrack && shuffleButton != nil
    commandCenter.changeShuffleModeCommand.currentShuffleType =
      shuffleButton.map { buttonStates.isActive($0.id, trackId: trackId) } == true ? .items : .off
  }

  private func disableAllCommands() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.nextTrackCommand.isEnabled = false
    commandCenter.previousTrackCommand.isEnabled = false
    commandCenter.skipForwardCommand.isEnabled = false
    commandCenter.skipBackwardCommand.isEnabled = false
    commandCenter.changePlaybackRateCommand.isEnabled = false
    commandCenter.changePlaybackPositionCommand.isEnabled = false
    for (command, _, _) in feedbackCommands { command.isEnabled = false }
    commandCenter.ratingCommand.isEnabled = false
    commandCenter.changeRepeatModeCommand.isEnabled = false
    commandCenter.changeShuffleModeCommand.isEnabled = false
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
