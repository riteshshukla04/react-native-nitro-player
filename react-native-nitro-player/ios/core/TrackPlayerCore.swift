//
//  TrackPlayerCore.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import AVFoundation
import Foundation
import MediaPlayer
import NitroModules
import ObjectiveC

class TrackPlayerCore: NSObject {
  // MARK: - Constants

  private enum Constants {
    // Time thresholds (in seconds)
    static let skipToPreviousThreshold: Double = 2.0
    static let stateChangeDelay: TimeInterval = 0.1

    // Duration thresholds for boundary intervals (in seconds)
    static let twoHoursInSeconds: Double = 7200
    static let oneHourInSeconds: Double = 3600

    // Boundary time intervals (in seconds)
    static let boundaryIntervalLong: Double = 5.0  // For tracks > 2 hours
    static let boundaryIntervalMedium: Double = 2.0  // For tracks > 1 hour
    static let boundaryIntervalDefault: Double = 1.0  // Default interval

    // UI/Display constants
    static let separatorLineLength: Int = 80
    static let playlistSeparatorLength: Int = 40

    // Gapless playback configuration
    static let preferredForwardBufferDuration: Double = 30.0  // Buffer 30 seconds ahead
    static let preloadAssetKeys: [String] = [
      "playable", "duration", "tracks", "preferredTransform",
    ]
    static let gaplessPreloadCount: Int = 3  // Number of tracks to preload ahead
  }

  // MARK: - Properties

  private var player: AVQueuePlayer?
  private let playlistManager = PlaylistManager.shared
  private var mediaSessionManager: MediaSessionManager?
  private var currentPlaylistId: String?
  private var currentTrackIndex: Int = -1
  private var currentTracks: [TrackItem] = []
  private var isManuallySeeked = false
  private var repeatMode: RepeatMode = .off
  private var boundaryTimeObserver: Any?
  private var currentItemObservers: [NSKeyValueObservation] = []

  // Gapless playback: Cache for preloaded assets
  private var preloadedAssets: [String: AVURLAsset] = [:]
  private let preloadQueue = DispatchQueue(label: "com.nitroplayer.preload", qos: .utility)

  // Temporary tracks for addToUpNext and playNext
  private var playNextStack: [TrackItem] = []  // LIFO - last added plays first
  private var upNextQueue: [TrackItem] = []  // FIFO - first added plays first
  private var currentTemporaryType: TemporaryType = .none

  // Enum to track what type of track is currently playing
  private enum TemporaryType {
    case none  // Playing from original playlist
    case playNext  // Currently in playNextStack
    case upNext  // Currently in upNextQueue
  }

  // MARK: - Weak Callback Wrapper

  /// Wrapper to hold callbacks with weak reference for auto-cleanup
  private class WeakCallbackBox<T> {
    private(set) weak var owner: AnyObject?
    let callback: T

    init(owner: AnyObject, callback: T) {
      self.owner = owner
      self.callback = callback
    }

    var isAlive: Bool { owner != nil }
  }

  // Event callbacks - support multiple listeners with auto-cleanup
  private var onChangeTrackListeners: [WeakCallbackBox<(TrackItem, Reason?) -> Void>] = []
  private var onPlaybackStateChangeListeners:
    [WeakCallbackBox<(TrackPlayerState, Reason?) -> Void>] = []
  private var onSeekListeners: [WeakCallbackBox<(Double, Double) -> Void>] = []
  private var onPlaybackProgressChangeListeners:
    [WeakCallbackBox<(Double, Double, Bool?) -> Void>] = []

  // Thread-safe queue for listener access
  private let listenersQueue = DispatchQueue(
    label: "com.trackplayer.listeners", attributes: .concurrent)

  static let shared = TrackPlayerCore()

  // MARK: - Initialization

  private override init() {
    super.init()
    setupAudioSession()
    setupPlayer()
    mediaSessionManager = MediaSessionManager()
    mediaSessionManager?.setTrackPlayerCore(self)
  }

  // MARK: - Setup

  private func setupAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true)
    } catch {
      print("❌ TrackPlayerCore: Failed to setup audio session - \(error)")
    }
  }

  private func setupPlayer() {
    player = AVQueuePlayer()

    // MARK: - Gapless Playback Configuration

    // Disable automatic waiting to minimize stalling - this allows smoother transitions
    // between tracks as AVPlayer won't pause to buffer excessively
    player?.automaticallyWaitsToMinimizeStalling = false

    // Set playback rate to 1.0 immediately when ready (reduces gap between tracks)
    player?.actionAtItemEnd = .advance

    // Configure for high-quality audio playback with minimal latency
    if #available(iOS 15.0, *) {
      player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    print(
      "🎵 TrackPlayerCore: Gapless playback configured - automaticallyWaitsToMinimizeStalling=false")

    setupPlayerObservers()
  }

  private func setupPlayerObservers() {
    guard let player = player else { return }

    // Observe player status
    player.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
    player.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)

    // Observe time control status
    player.addObserver(self, forKeyPath: "timeControlStatus", options: [.new], context: nil)

    // Observe current item changes
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemDidPlayToEndTime),
      name: .AVPlayerItemDidPlayToEndTime,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemFailedToPlayToEndTime),
      name: .AVPlayerItemFailedToPlayToEndTime,
      object: nil
    )

    // Observe player item errors
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemNewErrorLogEntry),
      name: .AVPlayerItemNewErrorLogEntry,
      object: nil
    )

    // Observe time jumps (seeks)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(playerItemTimeJumped),
      name: .AVPlayerItemTimeJumped,
      object: nil
    )

    // Observe when item changes (using KVO on currentItem)
    player.addObserver(self, forKeyPath: "currentItem", options: [.new], context: nil)
  }

  // MARK: - Boundary Time Observer

  private func setupBoundaryTimeObserver() {
    // Remove existing boundary observer if any
    if let existingObserver = boundaryTimeObserver, let currentPlayer = player {
      currentPlayer.removeTimeObserver(existingObserver)
      boundaryTimeObserver = nil
    }

    guard let player = player,
      let currentItem = player.currentItem
    else {
      print("⚠️ TrackPlayerCore: Cannot setup boundary observer - no player or item")
      return
    }

    // Wait for duration to be available
    guard currentItem.status == .readyToPlay else {
      print("⚠️ TrackPlayerCore: Item not ready, will setup boundaries when ready")
      return
    }

    let duration = currentItem.duration.seconds
    guard duration > 0 && !duration.isNaN && !duration.isInfinite else {
      print("⚠️ TrackPlayerCore: Invalid duration: \(duration), cannot setup boundaries")
      return
    }

    // Determine interval based on duration
    let interval: Double
    if duration > Constants.twoHoursInSeconds {
      interval = Constants.boundaryIntervalLong
    } else if duration > Constants.oneHourInSeconds {
      interval = Constants.boundaryIntervalMedium
    } else {
      interval = Constants.boundaryIntervalDefault
    }

    // Create boundary times at each interval
    var boundaryTimes: [NSValue] = []
    var time: Double = 0
    while time <= duration {
      let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
      boundaryTimes.append(NSValue(time: cmTime))
      time += interval
    }

    print(
      "⏱️ TrackPlayerCore: Setting up \(boundaryTimes.count) boundary observers (interval: \(interval)s, duration: \(Int(duration))s)"
    )

    // Add boundary time observer
    boundaryTimeObserver = player.addBoundaryTimeObserver(forTimes: boundaryTimes, queue: .main) {
      [weak self] in
      guard let self = self else { return }
      self.handleBoundaryTimeCrossed()
    }

    print("⏱️ TrackPlayerCore: Boundary time observer setup complete")
  }

  private func handleBoundaryTimeCrossed() {
    guard let player = player,
      let currentItem = player.currentItem
    else { return }

    // Don't fire progress when paused
    guard player.rate > 0 else { return }

    let position = currentItem.currentTime().seconds
    let duration = currentItem.duration.seconds

    guard duration > 0 && !duration.isNaN && !duration.isInfinite else { return }

    print(
      "⏱️ TrackPlayerCore: Boundary crossed - position: \(Int(position))s / \(Int(duration))s, callback exists: \(!onPlaybackProgressChangeListeners.isEmpty)"
    )

    notifyPlaybackProgress(
      position,
      duration,
      isManuallySeeked ? true : nil
    )
    isManuallySeeked = false
  }

  // MARK: - Notification Handlers

  @objc private func playerItemDidPlayToEndTime(notification: Notification) {
    print("\n🏁 TrackPlayerCore: Track finished playing")

    guard let finishedItem = notification.object as? AVPlayerItem else {
      print("⚠️ Cannot identify finished item")
      skipToNext()
      return
    }

    // Determine what type of track just finished and remove it from temporary lists
    if let trackId = finishedItem.trackId {
      // Check if it was a playNext track
      if let index = playNextStack.firstIndex(where: { $0.id == trackId }) {
        let track = playNextStack.remove(at: index)
        print("🏁 Finished playNext track: \(track.title) - removed from stack")
      }
      // Check if it was an upNext track
      else if let index = upNextQueue.firstIndex(where: { $0.id == trackId }) {
        let track = upNextQueue.remove(at: index)
        print("🏁 Finished upNext track: \(track.title) - removed from queue")
      }
      // Otherwise it was from original playlist
      else if let track = currentTracks.first(where: { $0.id == trackId }) {
        print("🏁 Finished original track: \(track.title)")
      }
    }

    // Check remaining queue
    if let player = player {
      print("📋 Remaining items in queue: \(player.items().count)")
    }

    // Handle repeat modes
    switch repeatMode {
    case .track:
      // Repeat current track - seek to beginning and play
      print("🔁 TrackPlayerCore: Repeat mode is TRACK - replaying current track")
      DispatchQueue.main.async { [weak self] in
        guard let self = self, let player = self.player else { return }
        // For temporary tracks, just seek to beginning
        if self.currentTemporaryType != .none {
          player.seek(to: .zero)
          player.play()
        } else {
          // For original tracks, recreate via playFromIndex
          self.playFromIndex(index: self.currentTrackIndex)
        }
      }
      return

    case .playlist:
      // Check if we're at the end of the ORIGINAL playlist (ignore temps)
      if currentTemporaryType == .none && currentTrackIndex >= currentTracks.count - 1 {
        // Check if there are still temporary tracks
        if !playNextStack.isEmpty || !upNextQueue.isEmpty {
          print("🔁 TrackPlayerCore: Temporary tracks remaining, continuing...")
        } else {
          print("🔁 TrackPlayerCore: Repeat mode is PLAYLIST - restarting from beginning")
          // Clear temps and restart
          playNextStack.removeAll()
          upNextQueue.removeAll()
          DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.playFromIndex(index: 0)
          }
          return
        }
      } else {
        print("🔁 TrackPlayerCore: Repeat mode is PLAYLIST - continuing to next track")
      }

    case .off:
      // Default behavior - stop at end of playlist
      print("🔁 TrackPlayerCore: Repeat mode is OFF")
    }

    // Track ended naturally
    notifyTrackChange(
      getCurrentTrack()
        ?? TrackItem(
          id: "",
          title: "",
          artist: "",
          album: "",
          duration: 0,
          url: "",
          artwork: nil,
          extraPayload: nil
        ), .end)

    // Try to play next track
    skipToNext()
  }

  @objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
      print("❌ TrackPlayerCore: Playback failed - \(error)")
      notifyPlaybackStateChange(.stopped, .error)
    }
  }

  @objc private func playerItemNewErrorLogEntry(notification: Notification) {
    guard let item = notification.object as? AVPlayerItem,
      let errorLog = item.errorLog()
    else { return }

    for event in errorLog.events ?? [] {
      print(
        "❌ TrackPlayerCore: Error log - \(event.errorComment ?? "Unknown error") - Code: \(event.errorStatusCode)"
      )
    }

    // Also check item error
    if let error = item.error {
      print("❌ TrackPlayerCore: Item error - \(error.localizedDescription)")
    }
  }

  @objc private func playerItemTimeJumped(notification: Notification) {
    guard let player = player,
      let currentItem = player.currentItem
    else { return }

    let position = currentItem.currentTime().seconds
    let duration = currentItem.duration.seconds

    print("🎯 TrackPlayerCore: Time jumped (seek detected) - position: \(Int(position))s")

    // Call onSeek callback immediately
    notifySeek(position, duration)

    // Mark that this was a manual seek
    isManuallySeeked = true

    // Trigger immediate progress update
    handleBoundaryTimeCrossed()
  }

  // MARK: - KVO Observer

  override func observeValue(
    forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    guard let player = player else { return }

    print("👀 TrackPlayerCore: KVO - keyPath: \(keyPath ?? "nil")")

    if keyPath == "status" {
      print("👀 TrackPlayerCore: Player status changed to: \(player.status.rawValue)")
      if player.status == .readyToPlay {
        emitStateChange()
      } else if player.status == .failed {
        print("❌ TrackPlayerCore: Player failed")
        notifyPlaybackStateChange(.stopped, .error)
      }
    } else if keyPath == "rate" {
      print("👀 TrackPlayerCore: Rate changed to: \(player.rate)")
      emitStateChange()
    } else if keyPath == "timeControlStatus" {
      print("👀 TrackPlayerCore: TimeControlStatus changed to: \(player.timeControlStatus.rawValue)")
      emitStateChange()
    } else if keyPath == "currentItem" {
      print("👀 TrackPlayerCore: Current item changed")
      currentItemDidChange()
    }
  }

  // MARK: - Item Change Handling

  @objc private func currentItemDidChange() {
    // Clear old item observers
    currentItemObservers.removeAll()

    // Track changed - update index
    guard let player = player,
      let currentItem = player.currentItem
    else {
      print("⚠️ TrackPlayerCore: Current item changed to nil")
      return
    }

    print("\n" + String(repeating: "▶", count: Constants.separatorLineLength))
    print("🔄 TrackPlayerCore: CURRENT ITEM CHANGED")
    print(String(repeating: "▶", count: Constants.separatorLineLength))

    // Log current item details
    if let trackId = currentItem.trackId,
      let track = currentTracks.first(where: { $0.id == trackId })
    {
      print("▶️  NOW PLAYING: \(track.title) - \(track.artist) (ID: \(track.id))")
    } else {
      print("⚠️  NOW PLAYING: Unknown track (trackId: \(currentItem.trackId ?? "nil"))")
    }

    // Show remaining items in queue
    let remainingItems = player.items()
    print("\n📋 REMAINING ITEMS IN QUEUE: \(remainingItems.count)")
    for (index, item) in remainingItems.enumerated() {
      if let trackId = item.trackId, let track = currentTracks.first(where: { $0.id == trackId }) {
        let marker = item == currentItem ? "▶️" : "  "
        print("\(marker) [\(index + 1)] \(track.title) - \(track.artist)")
      } else {
        print("   [\(index + 1)] ⚠️ Unknown track")
      }
    }

    print(String(repeating: "▶", count: Constants.separatorLineLength) + "\n")

    // Log item status
    print("📱 TrackPlayerCore: Item status: \(currentItem.status.rawValue)")

    // Check for errors
    if let error = currentItem.error {
      print("❌ TrackPlayerCore: Current item has error - \(error.localizedDescription)")
    }

    // Setup KVO observers for current item
    setupCurrentItemObservers(item: currentItem)

    // Update track index and determine temporary type
    if let trackId = currentItem.trackId {
      print("🔍 TrackPlayerCore: Looking up trackId '\(trackId)' in currentTracks...")
      print("   Current index BEFORE lookup: \(currentTrackIndex)")

      // Update temporary type
      currentTemporaryType = determineCurrentTemporaryType()
      print("   🎯 Track type: \(currentTemporaryType)")

      // If it's a temporary track, don't update currentTrackIndex
      if currentTemporaryType != .none {
        // Find and emit the temporary track
        var tempTrack: TrackItem? = nil
        if currentTemporaryType == .playNext {
          tempTrack = playNextStack.first(where: { $0.id == trackId })
        } else if currentTemporaryType == .upNext {
          tempTrack = upNextQueue.first(where: { $0.id == trackId })
        }

        if let track = tempTrack {
          print("   🎵 Temporary track: \(track.title) - \(track.artist)")
          print("   📢 Emitting onChangeTrack for temporary track")
          notifyTrackChange(track, .skip)
          mediaSessionManager?.onTrackChanged()
        }
      }
      // It's an original playlist track
      else if let index = currentTracks.firstIndex(where: { $0.id == trackId }) {
        print("   ✅ Found track at index: \(index)")
        print("   Setting currentTrackIndex from \(currentTrackIndex) to \(index)")

        let oldIndex = currentTrackIndex
        currentTrackIndex = index

        if let track = currentTracks[safe: index] {
          print("   🎵 Track: \(track.title) - \(track.artist)")

          // Only emit onChangeTrack if index actually changed
          // This prevents duplicate emissions
          if oldIndex != index {
            print("   📢 Emitting onChangeTrack (index changed from \(oldIndex) to \(index))")
            notifyTrackChange(track, .skip)
            mediaSessionManager?.onTrackChanged()
          } else {
            print("   ⏭️ Skipping onChangeTrack emission (index unchanged)")
          }
        }
      } else {
        print("   ⚠️ Track ID '\(trackId)' NOT FOUND in currentTracks!")
        print("   Current tracks:")
        for (idx, track) in currentTracks.enumerated() {
          print("      [\(idx)] \(track.id) - \(track.title)")
        }
      }
    }

    // Setup boundary observers when item is ready
    if currentItem.status == .readyToPlay {
      setupBoundaryTimeObserver()
    }

    // MARK: - Gapless Playback: Preload upcoming tracks when track changes
    // This ensures the next tracks are ready for seamless transitions
    preloadUpcomingTracks(from: currentTrackIndex + 1)
    cleanupPreloadedAssets(keepingFrom: currentTrackIndex)
  }

  private func setupCurrentItemObservers(item: AVPlayerItem) {
    print("📱 TrackPlayerCore: Setting up item observers")

    // Observe status - recreate boundaries when ready
    let statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      if item.status == .readyToPlay {
        print("✅ TrackPlayerCore: Item ready, setting up boundaries")
        self?.setupBoundaryTimeObserver()
      } else if item.status == .failed {
        print("❌ TrackPlayerCore: Item failed")
        self?.notifyPlaybackStateChange(.stopped, .error)
      }
    }
    currentItemObservers.append(statusObserver)

    // Observe playback buffer
    let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { item, _ in
      if item.isPlaybackBufferEmpty {
        print("⏸️ TrackPlayerCore: Buffer empty (buffering)")
      }
    }
    currentItemObservers.append(bufferEmptyObserver)

    let bufferKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
      item, _ in
      if item.isPlaybackLikelyToKeepUp {
        print("▶️ TrackPlayerCore: Buffer likely to keep up")
      }
    }
    currentItemObservers.append(bufferKeepUpObserver)
  }

  // MARK: - Playlist Management

  func loadPlaylist(playlistId: String) {
    if Thread.isMainThread {
      loadPlaylistInternal(playlistId: playlistId)
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.loadPlaylistInternal(playlistId: playlistId)
      }
    }
  }

  private func loadPlaylistInternal(playlistId: String) {
    print("\n" + String(repeating: "🎼", count: Constants.playlistSeparatorLength))
    print("📂 TrackPlayerCore: LOAD PLAYLIST REQUEST")
    print("   Playlist ID: \(playlistId)")

    // Clear temporary tracks when loading new playlist
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    print("   🧹 Cleared temporary tracks")

    let playlist = self.playlistManager.getPlaylist(playlistId: playlistId)
    if let playlist = playlist {
      print("   ✅ Found playlist: \(playlist.name)")
      print("   📋 Contains \(playlist.tracks.count) tracks:")
      for (index, track) in playlist.tracks.enumerated() {
        print("      [\(index + 1)] \(track.title) - \(track.artist)")
      }
      print(String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")

      self.currentPlaylistId = playlistId
      self.updatePlayerQueue(tracks: playlist.tracks)
      // Emit initial state (paused/stopped before play)
      self.emitStateChange()
    } else {
      print("   ❌ Playlist NOT FOUND")
      print(String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")
    }
  }

  func updatePlaylist(playlistId: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.currentPlaylistId == playlistId {
        let playlist = self.playlistManager.getPlaylist(playlistId: playlistId)
        if let playlist = playlist {
          self.updatePlayerQueue(tracks: playlist.tracks)
        }
      }
    }
  }

  // MARK: - Public Methods

  func getCurrentPlaylistId() -> String? {
    return currentPlaylistId
  }

  func getPlaylistManager() -> PlaylistManager {
    return playlistManager
  }

  private func emitStateChange(reason: Reason? = nil) {
    guard let player = player else { return }

    let state: TrackPlayerState
    if player.rate == 0 {
      state = .paused
    } else if player.timeControlStatus == .playing {
      state = .playing
    } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
      state = .paused  // Buffering
    } else {
      state = .stopped
    }

    print("🔔 TrackPlayerCore: Emitting state change: \(state)")
    print("🔔 TrackPlayerCore: Callback exists: \(!onPlaybackStateChangeListeners.isEmpty)")
    notifyPlaybackStateChange(state, reason)
    mediaSessionManager?.onPlaybackStateChanged()
  }

  // MARK: - Gapless Playback Helpers

  /// Creates a gapless-optimized AVPlayerItem with proper buffering configuration
  private func createGaplessPlayerItem(for track: TrackItem, isPreload: Bool = false)
    -> AVPlayerItem?
  {
    // Get effective URL - uses local path if downloaded, otherwise remote URL
    let effectiveUrlString = DownloadManagerCore.shared.getEffectiveUrl(track: track)

    // Create URL - use fileURLWithPath for local files, URL(string:) for remote
    let url: URL
    let isLocal = effectiveUrlString.hasPrefix("/")

    if isLocal {
      // Local file - use fileURLWithPath
      print("📥 TrackPlayerCore: Using DOWNLOADED version for \(track.title)")
      print("   Local path: \(effectiveUrlString)")

      // Verify file exists
      if FileManager.default.fileExists(atPath: effectiveUrlString) {
        url = URL(fileURLWithPath: effectiveUrlString)
        print("   File URL: \(url.absoluteString)")
        print("   ✅ File verified to exist")
      } else {
        print("   ❌ Downloaded file does NOT exist at path!")
        print("   Falling back to remote URL: \(track.url)")
        guard let remoteUrl = URL(string: track.url) else {
          print("❌ TrackPlayerCore: Invalid remote URL: \(track.url)")
          return nil
        }
        url = remoteUrl
      }
    } else {
      // Remote URL
      guard let remoteUrl = URL(string: effectiveUrlString) else {
        print("❌ TrackPlayerCore: Invalid URL for track: \(track.title) - \(effectiveUrlString)")
        return nil
      }
      url = remoteUrl
      print("🌐 TrackPlayerCore: Using REMOTE version for \(track.title)")
    }

    // Check if we have a preloaded asset for this track
    let asset: AVURLAsset
    if let preloadedAsset = preloadedAssets[track.id] {
      asset = preloadedAsset
      print("🚀 TrackPlayerCore: Using preloaded asset for \(track.title)")
    } else {
      // Create asset with options optimized for gapless playback
      asset = AVURLAsset(
        url: url,
        options: [
          AVURLAssetPreferPreciseDurationAndTimingKey: true  // Ensures accurate duration for gapless transitions
        ])
    }

    let item = AVPlayerItem(asset: asset)

    // Configure buffer duration for gapless playback
    // This tells AVPlayer how much content to buffer ahead
    item.preferredForwardBufferDuration = Constants.preferredForwardBufferDuration

    // Enable automatic loading of item properties for faster starts
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

    // Store track ID for later reference
    item.trackId = track.id

    // Apply equalizer audio mix to the player item
    // This enables real-time EQ processing via MTAudioProcessingTap
    // Apply equalizer audio mix to the player item
    // This enables real-time EQ processing via MTAudioProcessingTap
    EqualizerCore.shared.applyAudioMix(to: item)
    print("🎛️ TrackPlayerCore: Requesting EQ audio mix application for \(track.title)")

    // If this is a preload request, start loading asset keys asynchronously
    if isPreload {
      asset.loadValuesAsynchronously(forKeys: Constants.preloadAssetKeys) {
        // Asset keys are now loaded, which speeds up playback start
        var allKeysLoaded = true
        for key in Constants.preloadAssetKeys {
          var error: NSError?
          let status = asset.statusOfValue(forKey: key, error: &error)
          if status == .failed {
            print(
              "⚠️ TrackPlayerCore: Failed to load key '\(key)' for \(track.title): \(error?.localizedDescription ?? "unknown")"
            )
            allKeysLoaded = false
          }
        }
        if allKeysLoaded {
          print("✅ TrackPlayerCore: All asset keys preloaded for \(track.title)")
        }
      }
    }

    return item
  }

  /// Preloads assets for upcoming tracks to enable gapless playback
  private func preloadUpcomingTracks(from startIndex: Int) {
    preloadQueue.async { [weak self] in
      guard let self = self else { return }

      // Capture currentTracks to avoid race condition with main thread
      let tracks = self.currentTracks
      let endIndex = min(startIndex + Constants.gaplessPreloadCount, tracks.count)

      for i in startIndex..<endIndex {
        guard i < tracks.count else { break }
        let track = tracks[i]

        // Skip if already preloaded
        if self.preloadedAssets[track.id] != nil {
          continue
        }

        guard let url = URL(string: track.url) else { continue }

        let asset = AVURLAsset(
          url: url,
          options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
          ])

        // Preload essential keys for gapless playback
        asset.loadValuesAsynchronously(forKeys: Constants.preloadAssetKeys) { [weak self] in
          var allKeysLoaded = true
          for key in Constants.preloadAssetKeys {
            var error: NSError?
            let status = asset.statusOfValue(forKey: key, error: &error)
            if status != .loaded {
              allKeysLoaded = false
              break
            }
          }

          if allKeysLoaded {
            DispatchQueue.main.async {
              self?.preloadedAssets[track.id] = asset
              print("🎯 TrackPlayerCore: Preloaded asset for upcoming track: \(track.title)")
            }
          }
        }
      }
    }
  }

  /// Clears preloaded assets that are no longer needed
  private func cleanupPreloadedAssets(keepingFrom currentIndex: Int) {
    preloadQueue.async { [weak self] in
      guard let self = self else { return }

      // Keep assets for current track and upcoming tracks within preload range
      let keepRange =
        currentIndex..<min(
          currentIndex + Constants.gaplessPreloadCount + 1, self.currentTracks.count)
      let keepIds = Set(keepRange.compactMap { self.currentTracks[safe: $0]?.id })

      let assetsToRemove = self.preloadedAssets.keys.filter { !keepIds.contains($0) }
      for id in assetsToRemove {
        self.preloadedAssets.removeValue(forKey: id)
      }

      if !assetsToRemove.isEmpty {
        print("🧹 TrackPlayerCore: Cleaned up \(assetsToRemove.count) preloaded assets")
      }
    }
  }

  // MARK: - Listener Registration

  func addOnChangeTrackListener(
    owner: AnyObject, _ listener: @escaping (TrackItem, Reason?) -> Void
  ) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onChangeTrackListeners.append(box)
      print(
        "🎯 TrackPlayerCore: Added onChangeTrack listener (total: \(self?.onChangeTrackListeners.count ?? 0))"
      )
    }
  }

  func addOnPlaybackStateChangeListener(
    owner: AnyObject,
    _ listener: @escaping (TrackPlayerState, Reason?) -> Void
  ) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onPlaybackStateChangeListeners.append(box)
      print(
        "🎯 TrackPlayerCore: Added onPlaybackStateChange listener (total: \(self?.onPlaybackStateChangeListeners.count ?? 0))"
      )
    }
  }

  func addOnSeekListener(owner: AnyObject, _ listener: @escaping (Double, Double) -> Void) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onSeekListeners.append(box)
      print("🎯 TrackPlayerCore: Added onSeek listener (total: \(self?.onSeekListeners.count ?? 0))")
    }
  }

  func addOnPlaybackProgressChangeListener(
    owner: AnyObject,
    _ listener: @escaping (Double, Double, Bool?) -> Void
  ) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onPlaybackProgressChangeListeners.append(box)
      print(
        "🎯 TrackPlayerCore: Added onPlaybackProgressChange listener (total: \(self?.onPlaybackProgressChangeListeners.count ?? 0))"
      )
    }
  }

  // MARK: - Listener Notification Helpers

  private func notifyTrackChange(_ track: TrackItem, _ reason: Reason?) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      // Remove dead listeners
      self.onChangeTrackListeners.removeAll { !$0.isAlive }

      // Get live callbacks
      let liveCallbacks = self.onChangeTrackListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      // Call on main thread
      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(track, reason)
          }
        }
      }
    }
  }

  private func notifyPlaybackStateChange(_ state: TrackPlayerState, _ reason: Reason?) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      self.onPlaybackStateChangeListeners.removeAll { !$0.isAlive }

      let liveCallbacks = self.onPlaybackStateChangeListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(state, reason)
          }
        }
      }
    }
  }

  private func notifySeek(_ position: Double, _ duration: Double) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      self.onSeekListeners.removeAll { !$0.isAlive }

      let liveCallbacks = self.onSeekListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(position, duration)
          }
        }
      }
    }
  }

  private func notifyPlaybackProgress(_ position: Double, _ duration: Double, _ isPlaying: Bool?) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      self.onPlaybackProgressChangeListeners.removeAll { !$0.isAlive }

      let liveCallbacks = self.onPlaybackProgressChangeListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(position, duration, isPlaying)
          }
        }
      }
    }
  }

  // MARK: - State Management

  // MARK: - Queue Management

  private func updatePlayerQueue(tracks: [TrackItem]) {
    print("\n" + String(repeating: "=", count: Constants.separatorLineLength))
    print("📋 TrackPlayerCore: UPDATE PLAYER QUEUE - Received \(tracks.count) tracks")
    print(String(repeating: "=", count: Constants.separatorLineLength))

    // Print the full playlist being fed and check download status
    for (index, track) in tracks.enumerated() {
      let isDownloaded = DownloadManagerCore.shared.isTrackDownloaded(trackId: track.id)
      let downloadStatus = isDownloaded ? "📥 DOWNLOADED" : "🌐 REMOTE"
      print(
        "  [\(index + 1)] 🎵 \(track.title) - \(track.artist) (ID: \(track.id)) - \(downloadStatus)")
      if isDownloaded {
        if let localPath = DownloadManagerCore.shared.getLocalPath(trackId: track.id) {
          print("      Local path: \(localPath)")
        }
      }
    }
    print(String(repeating: "=", count: Constants.separatorLineLength) + "\n")

    // Store tracks for index tracking
    currentTracks = tracks
    currentTrackIndex = 0
    print("🔢 TrackPlayerCore: Reset currentTrackIndex to 0 (will be updated by KVO observer)")

    // Remove old boundary observer if exists (this is safe)
    if let boundaryObserver = boundaryTimeObserver, let currentPlayer = player {
      currentPlayer.removeTimeObserver(boundaryObserver)
      boundaryTimeObserver = nil
    }

    // Clear old preloaded assets when loading new queue
    preloadedAssets.removeAll()

    // Create gapless-optimized AVPlayerItems from tracks
    let items = tracks.enumerated().compactMap { (index, track) -> AVPlayerItem? in
      // First few items get preload treatment for faster initial playback
      let isPreload = index < Constants.gaplessPreloadCount
      return createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    print("🎵 TrackPlayerCore: Created \(items.count) gapless-optimized player items")

    guard !items.isEmpty else {
      print("❌ TrackPlayerCore: No valid items to play")
      return
    }

    // Replace current queue (player should always exist after setupPlayer)
    guard let existingPlayer = self.player else {
      print("❌ TrackPlayerCore: No player available - this should never happen!")
      return
    }

    print(
      "🔄 TrackPlayerCore: Updating queue - removing \(existingPlayer.items().count) items, adding \(items.count) new items"
    )

    // Remove all existing items
    existingPlayer.removeAllItems()

    // Add new items IN ORDER
    // IMPORTANT: insert(after: nil) puts item at the start
    // To maintain order, we need to track the last inserted item
    var lastItem: AVPlayerItem? = nil
    for (index, item) in items.enumerated() {
      existingPlayer.insert(item, after: lastItem)
      lastItem = item

      if let trackId = item.trackId, let track = tracks.first(where: { $0.id == trackId }) {
        print("  ➕ Added to player queue [\(index + 1)]: \(track.title)")
      }
    }

    // Verify what's actually in the player now
    print(
      "\n🔍 TrackPlayerCore: VERIFICATION - Player now has \(existingPlayer.items().count) items:")
    for (index, item) in existingPlayer.items().enumerated() {
      if let trackId = item.trackId, let track = tracks.first(where: { $0.id == trackId }) {
        print("  [\(index + 1)] ✓ \(track.title) - \(track.artist) (ID: \(track.id))")
      } else {
        print("  [\(index + 1)] ⚠️ Unknown item (no trackId)")
      }
    }

    if let currentItem = existingPlayer.currentItem, let trackId = currentItem.trackId {
      if let track = tracks.first(where: { $0.id == trackId }) {
        print("▶️  Current item: \(track.title)")
      }
    }
    print(String(repeating: "=", count: Constants.separatorLineLength) + "\n")

    // Note: Boundary time observers will be set up automatically when item becomes ready
    // This happens in setupCurrentItemObservers() -> status observer -> setupBoundaryTimeObserver()

    // Notify track change
    if let firstTrack = tracks.first {
      print("🎵 TrackPlayerCore: Emitting track change: \(firstTrack.title)")
      print("🎵 TrackPlayerCore: onChangeTrack callbacks count: \(onChangeTrackListeners.count)")
      notifyTrackChange(firstTrack, nil)
      mediaSessionManager?.onTrackChanged()
    }

    // Start preloading upcoming tracks for gapless playback
    preloadUpcomingTracks(from: 1)

    print("✅ TrackPlayerCore: Queue updated with \(items.count) gapless-optimized tracks")
  }

  func getCurrentTrack() -> TrackItem? {
    // If playing a temporary track, return that
    if currentTemporaryType != .none,
      let currentItem = player?.currentItem,
      let trackId = currentItem.trackId
    {
      if currentTemporaryType == .playNext {
        return playNextStack.first(where: { $0.id == trackId })
      } else if currentTemporaryType == .upNext {
        return upNextQueue.first(where: { $0.id == trackId })
      }
    }

    // Otherwise return from original playlist
    guard currentTrackIndex >= 0 && currentTrackIndex < currentTracks.count else {
      return nil
    }
    return currentTracks[currentTrackIndex]
  }

  func getActualQueue() -> [TrackItem] {
    // Called from Promise.async background thread
    // Schedule on main thread and wait for result
    if Thread.isMainThread {
      return getActualQueueInternal()
    } else {
      var queue: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        queue = self?.getActualQueueInternal() ?? []
      }
      return queue
    }
  }

  private func getActualQueueInternal() -> [TrackItem] {
    var queue: [TrackItem] = []

    // Add tracks before current (original playlist)
    if currentTrackIndex > 0 {
      queue.append(contentsOf: Array(currentTracks[0..<currentTrackIndex]))
    }

    // Add current track
    if let current = getCurrentTrack() {
      queue.append(current)
    }

    // Add playNext stack (LIFO - most recently added plays first)
    // Stack is already in correct order since we insert at position 0
    queue.append(contentsOf: playNextStack)

    // Add upNext queue (in order, FIFO)
    queue.append(contentsOf: upNextQueue)

    // Add remaining original tracks
    if currentTrackIndex + 1 < currentTracks.count {
      queue.append(contentsOf: Array(currentTracks[(currentTrackIndex + 1)...]))
    }

    return queue
  }

  func play() {
    print("▶️ TrackPlayerCore: play() called")
    if Thread.isMainThread {
      playInternal()
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.playInternal()
      }
    }
  }

  private func playInternal() {
    print("▶️ TrackPlayerCore: Calling player.play()")
    if let player = self.player {
      print("▶️ TrackPlayerCore: Player status: \(player.status.rawValue)")
      if let currentItem = player.currentItem {
        print("▶️ TrackPlayerCore: Current item status: \(currentItem.status.rawValue)")
        if let error = currentItem.error {
          print("❌ TrackPlayerCore: Current item error: \(error.localizedDescription)")
        }
      }
      player.play()
      // Emit state change immediately for responsive UI
      // KVO will also fire, but this ensures immediate feedback
      DispatchQueue.main.asyncAfter(deadline: .now() + Constants.stateChangeDelay) {
        [weak self] in
        self?.emitStateChange()
      }
    } else {
      print("❌ TrackPlayerCore: No player available")
    }
  }

  func pause() {
    print("⏸️ TrackPlayerCore: pause() called")
    if Thread.isMainThread {
      pauseInternal()
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.pauseInternal()
      }
    }
  }

  private func pauseInternal() {
    self.player?.pause()
    // Emit state change immediately for responsive UI
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.stateChangeDelay) { [weak self] in
      self?.emitStateChange()
    }
  }

  func playSong(songId: String, fromPlaylist: String?) {
    DispatchQueue.main.async { [weak self] in
      self?.playSongInternal(songId: songId, fromPlaylist: fromPlaylist)
    }
  }

  private func playSongInternal(songId: String, fromPlaylist: String?) {
    // Clear temporary tracks when directly playing a song
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    print("   🧹 Cleared temporary tracks")

    var targetPlaylistId: String?
    var songIndex: Int = -1

    // Case 1: If fromPlaylist is provided, use that playlist
    if let playlistId = fromPlaylist {
      print("🎵 TrackPlayerCore: Looking for song in specified playlist: \(playlistId)")
      if let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) {
        if let index = playlist.tracks.firstIndex(where: { $0.id == songId }) {
          targetPlaylistId = playlistId
          songIndex = index
          print("✅ Found song at index \(index) in playlist \(playlistId)")
        } else {
          print("⚠️ Song \(songId) not found in specified playlist \(playlistId)")
          return
        }
      } else {
        print("⚠️ Playlist \(playlistId) not found")
        return
      }
    }
    // Case 2: If fromPlaylist is not provided, search in current/loaded playlist first
    else {
      print("🎵 TrackPlayerCore: No playlist specified, checking current playlist")

      // Check if song exists in currently loaded playlist
      if let currentId = self.currentPlaylistId,
        let currentPlaylist = self.playlistManager.getPlaylist(playlistId: currentId)
      {
        if let index = currentPlaylist.tracks.firstIndex(where: { $0.id == songId }) {
          targetPlaylistId = currentId
          songIndex = index
          print("✅ Found song at index \(index) in current playlist \(currentId)")
        }
      }

      // If not found in current playlist, search in all playlists
      if songIndex == -1 {
        print("🔍 Song not found in current playlist, searching all playlists...")
        let allPlaylists = self.playlistManager.getAllPlaylists()

        for playlist in allPlaylists {
          if let index = playlist.tracks.firstIndex(where: { $0.id == songId }) {
            targetPlaylistId = playlist.id
            songIndex = index
            print("✅ Found song at index \(index) in playlist \(playlist.id)")
            break
          }
        }

        // If still not found, just use the first playlist if available
        if songIndex == -1 && !allPlaylists.isEmpty {
          targetPlaylistId = allPlaylists[0].id
          songIndex = 0
          print("⚠️ Song not found in any playlist, using first playlist and starting at index 0")
        }
      }
    }

    // Now play the song
    guard let playlistId = targetPlaylistId, songIndex >= 0 else {
      print("❌ Could not determine playlist or song index")
      return
    }

    // Load playlist if it's different from current
    if self.currentPlaylistId != playlistId {
      print("🔄 Loading new playlist: \(playlistId)")
      if let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) {
        self.currentPlaylistId = playlistId
        self.updatePlayerQueue(tracks: playlist.tracks)
      }
    }

    // Play from the found index
    print("▶️ Playing from index: \(songIndex)")
    self.playFromIndex(index: songIndex)
  }

  func skipToNext() {
    if Thread.isMainThread {
      skipToNextInternal()
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.skipToNextInternal()
      }
    }
  }

  private func skipToNextInternal() {
    guard let queuePlayer = self.player else { return }

    print("\n⏭️ TrackPlayerCore: SKIP TO NEXT")
    print("   BEFORE:")
    print("      currentTrackIndex: \(self.currentTrackIndex)")
    print("      Total tracks in currentTracks: \(self.currentTracks.count)")
    print("      Items in player queue: \(queuePlayer.items().count)")

    if let currentItem = queuePlayer.currentItem, let trackId = currentItem.trackId {
      if let track = self.currentTracks.first(where: { $0.id == trackId }) {
        print("      Currently playing: \(track.title) (ID: \(track.id))")
      }
    }

    // Check if there are more items in the queue
    if self.currentTrackIndex + 1 < self.currentTracks.count {
      print("   🔄 Calling advanceToNextItem()...")
      queuePlayer.advanceToNextItem()

      // NOTE: Don't manually update currentTrackIndex here!
      // The KVO observer (currentItemDidChange) will update it automatically

      print("   AFTER advanceToNextItem():")
      print("      Items in player queue: \(queuePlayer.items().count)")

      if let newCurrentItem = queuePlayer.currentItem, let trackId = newCurrentItem.trackId {
        if let track = self.currentTracks.first(where: { $0.id == trackId }) {
          print("      New current item: \(track.title) (ID: \(track.id))")
        }
      }

      print("   ⏳ Waiting for KVO observer to update index...")
    } else {
      print("   ⚠️ No more tracks in playlist")
      // At end of playlist - stop or loop
      queuePlayer.pause()
      self.notifyPlaybackStateChange(.stopped, .end)
    }
  }

  func skipToPrevious() {
    if Thread.isMainThread {
      skipToPreviousInternal()
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.skipToPreviousInternal()
      }
    }
  }

  private func skipToPreviousInternal() {
    guard let queuePlayer = self.player else { return }

    print("\n⏮️ TrackPlayerCore: SKIP TO PREVIOUS")
    print("   Current index: \(self.currentTrackIndex)")
    print("   Temporary type: \(self.currentTemporaryType)")
    print("   Current time: \(queuePlayer.currentTime().seconds)s")

    let currentTime = queuePlayer.currentTime()
    if currentTime.seconds > Constants.skipToPreviousThreshold {
      // If more than threshold seconds in, restart current track
      print(
        "   🔄 More than \(Int(Constants.skipToPreviousThreshold))s in, restarting current track")
      queuePlayer.seek(to: .zero)
    } else if self.currentTemporaryType != .none {
      // Playing temporary track - just restart it (temps are not navigable backwards)
      print("   🔄 Playing temporary track - restarting it (temps not navigable backwards)")
      queuePlayer.seek(to: .zero)
    } else if self.currentTrackIndex > 0 {
      // Go to previous track in original playlist
      let previousIndex = self.currentTrackIndex - 1
      print("   ⏮️ Going to previous track at index \(previousIndex)")
      self.playFromIndex(index: previousIndex)
    } else {
      // Already at first track, restart it
      print("   🔄 Already at first track, restarting it")
      queuePlayer.seek(to: .zero)
    }
  }

  func seek(position: Double) {
    if Thread.isMainThread {
      seekInternal(position: position)
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.seekInternal(position: position)
      }
    }
  }

  private func seekInternal(position: Double) {
    guard let player = self.player else { return }

    self.isManuallySeeked = true
    let time = CMTime(seconds: position, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    player.seek(to: time) { [weak self] completed in
      if completed {
        let duration = player.currentItem?.duration.seconds ?? 0.0
        self?.notifySeek(position, duration)
      }
    }
  }

  // MARK: - Repeat Mode

  func setRepeatMode(mode: RepeatMode) -> Bool {
    print("🔁 TrackPlayerCore: setRepeatMode called with mode: \(mode)")
    if Thread.isMainThread {
      self.repeatMode = mode
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.repeatMode = mode
      }
    }
    return true
  }

  func getState() -> PlayerState {
    // Called from Promise.async background thread
    // Schedule on main thread and wait for result
    if Thread.isMainThread {
      return getStateInternal()
    } else {
      var state: PlayerState!
      DispatchQueue.main.sync { [weak self] in
        state =
          self?.getStateInternal()
          ?? PlayerState(
            currentTrack: nil,
            currentPosition: 0.0,
            totalDuration: 0.0,
            currentState: .stopped,
            currentPlaylistId: nil,
            currentIndex: -1.0,
            currentPlayingType: .notPlaying
          )
      }
      return state
    }
  }

  private func getStateInternal() -> PlayerState {
    guard let player = player else {
      return PlayerState(
        currentTrack: nil,
        currentPosition: 0.0,
        totalDuration: 0.0,
        currentState: .stopped,
        currentPlaylistId: currentPlaylistId.map { Variant_NullType_String.second($0) },
        currentIndex: -1.0,
        currentPlayingType: .notPlaying
      )
    }

    let currentTrack = getCurrentTrack()
    let currentPosition = player.currentTime().seconds
    let totalDuration = player.currentItem?.duration.seconds ?? 0.0

    let currentState: TrackPlayerState
    if player.rate == 0 {
      currentState = .paused
    } else if player.timeControlStatus == .playing {
      currentState = .playing
    } else {
      currentState = .stopped
    }

    // Get current index
    let currentIndex: Double = currentTrackIndex >= 0 ? Double(currentTrackIndex) : -1.0

    // Map internal temporary type to CurrentPlayingType
    let currentPlayingType: CurrentPlayingType
    if currentTrack == nil {
      currentPlayingType = .notPlaying
    } else {
      switch currentTemporaryType {
      case .none:
        currentPlayingType = .playlist
      case .playNext:
        currentPlayingType = .playNext
      case .upNext:
        currentPlayingType = .upNext
      }
    }

    return PlayerState(
      currentTrack: currentTrack.map { Variant_NullType_TrackItem.second($0) },
      currentPosition: currentPosition,
      totalDuration: totalDuration,
      currentState: currentState,
      currentPlaylistId: currentPlaylistId.map { Variant_NullType_String.second($0) },
      currentIndex: currentIndex,
      currentPlayingType: currentPlayingType
    )
  }

  func configure(
    androidAutoEnabled: Bool?,
    carPlayEnabled: Bool?,
    showInNotification: Bool?
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.mediaSessionManager?.configure(
        androidAutoEnabled: androidAutoEnabled,
        carPlayEnabled: carPlayEnabled,
        showInNotification: showInNotification
      )
    }
  }

  func getAllPlaylists() -> [Playlist] {
    return playlistManager.getAllPlaylists().map { $0.toGeneratedPlaylist() }
  }

  // MARK: - Volume Control

  func setVolume(volume: Double) -> Bool {
    guard let player = player else {
      print("⚠️ TrackPlayerCore: Cannot set volume - no player available")
      return false
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let currentPlayer = self.player else {
        return
      }
      // Clamp volume to 0-100 range
      let clampedVolume = max(0.0, min(100.0, volume))
      // Convert to 0.0-1.0 range for AVQueuePlayer
      let normalizedVolume = Float(clampedVolume / 100.0)
      currentPlayer.volume = normalizedVolume
      print(
        "🔊 TrackPlayerCore: Volume set to \(Int(clampedVolume))% (normalized: \(normalizedVolume))")
    }
    return true
  }

  func playFromIndex(index: Int) {
    if Thread.isMainThread {
      playFromIndexInternal(index: index)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.playFromIndexInternal(index: index)
      }
    }
  }

  // MARK: - Skip to Index in Actual Queue

  func skipToIndex(index: Int) -> Bool {
    if Thread.isMainThread {
      return skipToIndexInternal(index: index)
    } else {
      var result = false
      DispatchQueue.main.sync { [weak self] in
        result = self?.skipToIndexInternal(index: index) ?? false
      }
      return result
    }
  }

  private func skipToIndexInternal(index: Int) -> Bool {
    print("\n🎯 TrackPlayerCore: SKIP TO INDEX \(index)")

    // Get actual queue to validate index and determine position
    let actualQueue = getActualQueueInternal()
    let totalQueueSize = actualQueue.count

    // Validate index
    guard index >= 0 && index < totalQueueSize else {
      print("   ❌ Invalid index \(index), queue size is \(totalQueueSize)")
      return false
    }

    // Calculate queue section boundaries
    // ActualQueue structure: [before_current] + [current] + [playNext] + [upNext] + [remaining_original]
    let currentPos = currentTrackIndex
    let playNextStart = currentPos + 1
    let playNextEnd = playNextStart + playNextStack.count
    let upNextStart = playNextEnd
    let upNextEnd = upNextStart + upNextQueue.count
    let originalRemainingStart = upNextEnd

    print("   Queue structure:")
    print("      currentPos: \(currentPos)")
    print("      playNextStart: \(playNextStart), playNextEnd: \(playNextEnd)")
    print("      upNextStart: \(upNextStart), upNextEnd: \(upNextEnd)")
    print("      originalRemainingStart: \(originalRemainingStart)")
    print("      totalQueueSize: \(totalQueueSize)")

    // Case 1: Target is before current - use playFromIndex on original
    if index < currentPos {
      print("   📍 Target is before current, jumping to original playlist index \(index)")
      playFromIndexInternal(index: index)
      return true
    }

    // Case 2: Target is current - seek to beginning
    if index == currentPos {
      print("   📍 Target is current track, seeking to beginning")
      player?.seek(to: .zero)
      return true
    }

    // Case 3: Target is in playNext section
    if index >= playNextStart && index < playNextEnd {
      let playNextIndex = index - playNextStart
      print("   📍 Target is in playNext section at position \(playNextIndex)")

      // Remove tracks before the target from playNext (they're being skipped)
      if playNextIndex > 0 {
        playNextStack.removeFirst(playNextIndex)
        print("      Removed \(playNextIndex) tracks from playNext stack")
      }

      // Rebuild queue and advance
      rebuildAVQueueFromCurrentPosition()
      player?.advanceToNextItem()
      return true
    }

    // Case 4: Target is in upNext section
    if index >= upNextStart && index < upNextEnd {
      let upNextIndex = index - upNextStart
      print("   📍 Target is in upNext section at position \(upNextIndex)")

      // Clear all playNext tracks (they're being skipped)
      playNextStack.removeAll()
      print("      Cleared all playNext tracks")

      // Remove tracks before target from upNext
      if upNextIndex > 0 {
        upNextQueue.removeFirst(upNextIndex)
        print("      Removed \(upNextIndex) tracks from upNext queue")
      }

      // Rebuild queue and advance
      rebuildAVQueueFromCurrentPosition()
      player?.advanceToNextItem()
      return true
    }

    // Case 5: Target is in remaining original tracks
    if index >= originalRemainingStart {
      // Get the target track directly from actualQueue
      let targetTrack = actualQueue[index]

      print("   📍 Case 5: Target is in remaining original tracks")
      print("      targetTrack.id: \(targetTrack.id)")
      print("      currentTracks.count: \(currentTracks.count)")
      print("      currentTracks IDs: \(currentTracks.map { $0.id })")

      // Find this track's index in the original playlist
      guard let originalIndex = currentTracks.firstIndex(where: { $0.id == targetTrack.id }) else {
        print("   ❌ Could not find track \(targetTrack.id) in original playlist")
        print("      Available tracks: \(currentTracks.map { $0.id })")
        return false
      }

      print("      originalIndex found: \(originalIndex)")

      // Clear all temporary tracks (they're being skipped)
      playNextStack.removeAll()
      upNextQueue.removeAll()
      currentTemporaryType = .none
      print("      Cleared all temporary tracks")

      // Play from the original playlist index
      let success = playFromIndexInternalWithResult(index: originalIndex)
      return success
    }

    print("   ❌ Unexpected case, index \(index) not handled")
    return false
  }

  private func playFromIndexInternal(index: Int) {
    _ = playFromIndexInternalWithResult(index: index)
  }

  private func playFromIndexInternalWithResult(index: Int) -> Bool {
    guard index >= 0 && index < self.currentTracks.count else {
      print(
        "❌ TrackPlayerCore: playFromIndex - invalid index \(index), currentTracks.count = \(self.currentTracks.count)"
      )
      return false
    }

    print("\n🎯 TrackPlayerCore: PLAY FROM INDEX \(index)")
    print("   Total tracks in playlist: \(self.currentTracks.count)")
    print("   Current index: \(self.currentTrackIndex), target index: \(index)")

    // Clear temporary tracks when jumping to specific index
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    print("   🧹 Cleared temporary tracks")

    // Store the full playlist
    let fullPlaylist = self.currentTracks

    // Update currentTrackIndex BEFORE updating queue
    self.currentTrackIndex = index

    // Recreate the queue starting from the target index
    // This ensures all remaining tracks are in the queue
    let tracksToPlay = Array(fullPlaylist[index...])
    print(
      "   🔄 Creating gapless queue with \(tracksToPlay.count) tracks starting from index \(index)"
    )

    // Create gapless-optimized player items
    let items = tracksToPlay.enumerated().compactMap { (offset, track) -> AVPlayerItem? in
      // First few items get preload treatment for faster playback
      let isPreload = offset < Constants.gaplessPreloadCount
      return self.createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    guard let player = self.player, !items.isEmpty else {
      print("❌ No player or no items to play")
      return false
    }

    // Remove old boundary observer
    if let boundaryObserver = self.boundaryTimeObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryTimeObserver = nil
    }

    // Clear and rebuild queue
    player.removeAllItems()
    var lastItem: AVPlayerItem? = nil
    for item in items {
      player.insert(item, after: lastItem)
      lastItem = item
    }

    // Restore the full playlist reference (don't slice it!)
    self.currentTracks = fullPlaylist

    print("   ✅ Gapless queue recreated. Now at index: \(self.currentTrackIndex)")
    if let track = self.getCurrentTrack() {
      print("   🎵 Playing: \(track.title)")
      notifyTrackChange(track, .skip)
      self.mediaSessionManager?.onTrackChanged()
    }

    // Start preloading upcoming tracks for gapless playback
    self.preloadUpcomingTracks(from: index + 1)

    player.play()
    return true
  }

  // MARK: - Temporary Track Management

  /**
   * Add a track to the up-next queue (FIFO - first added plays first)
   * Track will be inserted after currently playing track and any playNext tracks
   */
  func addToUpNext(trackId: String) {
    DispatchQueue.main.async { [weak self] in
      self?.addToUpNextInternal(trackId: trackId)
    }
  }

  private func addToUpNextInternal(trackId: String) {
    print("📋 TrackPlayerCore: addToUpNext(\(trackId))")

    // Find the track from current playlist or all playlists
    guard let track = self.findTrackById(trackId) else {
      print("❌ TrackPlayerCore: Track \(trackId) not found")
      return
    }

    // Add to end of upNext queue (FIFO)
    self.upNextQueue.append(track)
    print("   ✅ Added '\(track.title)' to upNext queue (position: \(self.upNextQueue.count))")

    // Rebuild the player queue if actively playing
    if self.player?.currentItem != nil {
      self.rebuildAVQueueFromCurrentPosition()
    }
  }

  /**
   * Add a track to play next (LIFO - last added plays first)
   * Track will be inserted immediately after currently playing track
   */
  func playNext(trackId: String) {
    DispatchQueue.main.async { [weak self] in
      self?.playNextInternal(trackId: trackId)
    }
  }

  private func playNextInternal(trackId: String) {
    print("⏭️ TrackPlayerCore: playNext(\(trackId))")

    // Find the track from current playlist or all playlists
    guard let track = self.findTrackById(trackId) else {
      print("❌ TrackPlayerCore: Track \(trackId) not found")
      return
    }

    // Insert at beginning of playNext stack (LIFO)
    self.playNextStack.insert(track, at: 0)
    print("   ✅ Added '\(track.title)' to playNext stack (position: 1)")

    // Rebuild the player queue if actively playing
    if self.player?.currentItem != nil {
      self.rebuildAVQueueFromCurrentPosition()
    }
  }

  /**
   * Rebuild the AVQueuePlayer from current position with temporary tracks
   * Order: [current] + [playNext stack reversed] + [upNext queue] + [remaining original]
   */
  private func rebuildAVQueueFromCurrentPosition() {
    guard let player = self.player else { return }

    print("\n🔄 TrackPlayerCore: REBUILDING QUEUE FROM CURRENT POSITION")
    print("   playNext stack: \(playNextStack.count) tracks")
    print("   upNext queue: \(upNextQueue.count) tracks")

    // Don't interrupt currently playing item
    let currentItem = player.currentItem
    let playingItems = player.items()

    // Build new queue order:
    // [playNext stack] + [upNext queue] + [remaining original tracks]
    var newQueueTracks: [TrackItem] = []

    // Add playNext stack (LIFO - most recently added plays first)
    // Stack is already in correct order since we insert at position 0
    newQueueTracks.append(contentsOf: playNextStack)

    // Add upNext queue (in order, FIFO)
    newQueueTracks.append(contentsOf: upNextQueue)

    // Add remaining original tracks
    if currentTrackIndex + 1 < currentTracks.count {
      let remainingOriginal = Array(currentTracks[(currentTrackIndex + 1)...])
      newQueueTracks.append(contentsOf: remainingOriginal)
    }

    print("   New queue: \(newQueueTracks.count) tracks total")

    // Remove all items from player EXCEPT the currently playing one
    for item in playingItems where item != currentItem {
      player.remove(item)
    }

    // Insert new items in order
    var lastItem = currentItem
    for track in newQueueTracks {
      if let item = createGaplessPlayerItem(for: track, isPreload: false) {
        player.insert(item, after: lastItem)
        lastItem = item
      }
    }

    print("   ✅ Queue rebuilt successfully")
  }

  /**
   * Find a track by ID from current playlist or all playlists
   */
  private func findTrackById(_ trackId: String) -> TrackItem? {
    // First check current playlist
    if let track = currentTracks.first(where: { $0.id == trackId }) {
      return track
    }

    // Then check all playlists
    let allPlaylists = playlistManager.getAllPlaylists()
    for playlist in allPlaylists {
      if let track = playlist.tracks.first(where: { $0.id == trackId }) {
        return track
      }
    }

    return nil
  }

  /**
   * Determine what type of track is currently playing
   */
  private func determineCurrentTemporaryType() -> TemporaryType {
    guard let currentItem = player?.currentItem,
      let trackId = currentItem.trackId
    else {
      return .none
    }

    // Check if in playNext stack
    if playNextStack.contains(where: { $0.id == trackId }) {
      return .playNext
    }

    // Check if in upNext queue
    if upNextQueue.contains(where: { $0.id == trackId }) {
      return .upNext
    }

    return .none
  }

  // MARK: - Cleanup

  deinit {
    print("🧹 TrackPlayerCore: Cleaning up...")

    // Clear preloaded assets for gapless playback
    preloadedAssets.removeAll()

    // Remove boundary time observer
    if let boundaryObserver = boundaryTimeObserver, let currentPlayer = player {
      currentPlayer.removeTimeObserver(boundaryObserver)
    }

    // Clear item observers (modern KVO automatically releases)
    currentItemObservers.removeAll()

    // Remove player KVO observers (these were added in setupPlayer)
    if let currentPlayer = player {
      currentPlayer.removeObserver(self, forKeyPath: "status")
      currentPlayer.removeObserver(self, forKeyPath: "rate")
      currentPlayer.removeObserver(self, forKeyPath: "timeControlStatus")
      currentPlayer.removeObserver(self, forKeyPath: "currentItem")
      print("✅ TrackPlayerCore: Player observers removed")
    }

    // Remove all notification observers
    NotificationCenter.default.removeObserver(self)
    print("✅ TrackPlayerCore: Cleanup complete")
  }
}

// Safe array access extension
extension Array {
  subscript(safe index: Int) -> Element? {
    return indices.contains(index) ? self[index] : nil
  }
}

// Associated object extension for AVPlayerItem
private var trackIdKey: UInt8 = 0

extension AVPlayerItem {
  var trackId: String? {
    get {
      return objc_getAssociatedObject(self, &trackIdKey) as? String
    }
    set {
      objc_setAssociatedObject(self, &trackIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
}
