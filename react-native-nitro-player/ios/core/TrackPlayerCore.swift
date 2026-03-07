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
  private var currentRepeatMode: RepeatMode = .off
  private var lookaheadCount: Int = 5  // Number of tracks to preload ahead
  private var boundaryTimeObserver: Any?
  private var currentItemObservers: [NSKeyValueObservation] = []

  // Gapless playback: Cache for preloaded assets
  private var preloadedAssets: [String: AVURLAsset] = [:]
  private let preloadQueue = DispatchQueue(label: "com.nitroplayer.preload", qos: .utility)

  // Debounce flag: prevents firing checkUpcomingTracksForUrls every boundary tick
  // once we've already requested URLs for the current track's remaining window.
  private var didRequestUrlsForCurrentItem = false

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
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Failed to setup audio session - \(error)")
    }
  }

  private func setupPlayer() {
    player = AVQueuePlayer()

    // MARK: - Gapless Playback Configuration

    // Start with stall-waiting enabled so the first track buffers before playing.
    // Once the first item is ready (readyToPlay), this is flipped to false for
    // gapless inter-track transitions (see setupCurrentItemObservers).
    player?.automaticallyWaitsToMinimizeStalling = true

    // Set playback rate to 1.0 immediately when ready (reduces gap between tracks)
    player?.actionAtItemEnd = .advance

    // Configure for high-quality audio playback with minimal latency
    if #available(iOS 15.0, *) {
      player?.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🎵 Gapless playback configured - automaticallyWaitsToMinimizeStalling=true (flipped to false on first readyToPlay)")

    // Listen for EQ enabled/disabled changes so we can update ALL items in
    // the queue atomically, keeping the audio pipeline configuration uniform.
    // A mismatch (some items with tap, some without) forces AVQueuePlayer to
    // reconfigure the pipeline at transition boundaries → audible gap.
    EqualizerCore.shared.addOnEnabledChangeListener(owner: self) { [weak self] enabled in
      guard let self = self, let player = self.player else { return }
      DispatchQueue.main.async {
        for item in player.items() {
          if enabled {
            EqualizerCore.shared.applyAudioMix(to: item)
          } else {
            item.audioMix = nil
          }
        }
        NitroPlayerLogger.log("TrackPlayerCore",
          "🎛️ EQ toggled \(enabled ? "ON" : "OFF") — updated \(player.items().count) items for pipeline consistency")
      }
    }

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
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Cannot setup boundary observer - no player or item")
      return
    }

    // Wait for duration to be available
    guard currentItem.status == .readyToPlay else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Item not ready, will setup boundaries when ready")
      return
    }

    let duration = currentItem.duration.seconds
    guard duration > 0 && !duration.isNaN && !duration.isInfinite else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Invalid duration: \(duration), cannot setup boundaries")
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

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Setting up periodic observer (interval: \(interval)s, duration: \(Int(duration))s)")

    let cmInterval = CMTime(seconds: interval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    boundaryTimeObserver = player.addPeriodicTimeObserver(forInterval: cmInterval, queue: .main) {
      [weak self] _ in
      self?.handleBoundaryTimeCrossed()
    }

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Periodic time observer setup complete")
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

    NitroPlayerLogger.log("TrackPlayerCore", "⏱️ Boundary crossed - position: \(Int(position))s / \(Int(duration))s, callback exists: \(!onPlaybackProgressChangeListeners.isEmpty)")

    notifyPlaybackProgress(
      position,
      duration,
      isManuallySeeked ? true : nil
    )
    isManuallySeeked = false

    // Proactive gapless URL resolution: when the track is within the
    // buffer window of its end, check if any upcoming tracks still
    // need URLs and fire the callback so JS can resolve them in time.
    let remaining = duration - position
    if remaining > 0 && remaining <= Constants.preferredForwardBufferDuration && !didRequestUrlsForCurrentItem {
      didRequestUrlsForCurrentItem = true
      NitroPlayerLogger.log("TrackPlayerCore",
        "⏳ \(Int(remaining))s remaining — proactively checking upcoming URLs")
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
    }
  }

  // MARK: - Notification Handlers

  @objc private func playerItemDidPlayToEndTime(notification: Notification) {
    NitroPlayerLogger.log("TrackPlayerCore", "\n🏁 Track finished playing")

    guard let finishedItem = notification.object as? AVPlayerItem else {
      return
    }

    // 1. TRACK repeat — handle FIRST, before any temp-track removal
    if currentRepeatMode == .track {
      NitroPlayerLogger.log("TrackPlayerCore", "🔁 TRACK repeat — seeking to zero and replaying")
      player?.seek(to: .zero)
      player?.play()
      return  // do not remove temp tracks, do not notify track change (same track looping)
    }

    // 2. Remove finished temp track from its list
    if let trackId = finishedItem.trackId {
      // Check if it was a playNext track
      if let index = playNextStack.firstIndex(where: { $0.id == trackId }) {
        let track = playNextStack.remove(at: index)
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished playNext track: \(track.title) - removed from stack")
      }
      // Check if it was an upNext track
      else if let index = upNextQueue.firstIndex(where: { $0.id == trackId }) {
        let track = upNextQueue.remove(at: index)
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished upNext track: \(track.title) - removed from queue")
      }
      // Otherwise it was from original playlist
      else if let track = currentTracks.first(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "🏁 Finished original track: \(track.title)")
      }
    }

    // 3. Normal next-track advance happens via actionAtItemEnd = .advance
    // The KVO observer (currentItemDidChange) will handle the track change notification
    if let player = player {
      NitroPlayerLogger.log("TrackPlayerCore", "📋 Remaining items in queue: \(player.items().count)")
    }

    // Check if upcoming tracks need URLs
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  @objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Playback failed - \(error)")
      notifyPlaybackStateChange(.stopped, .error)
    }
  }

  @objc private func playerItemNewErrorLogEntry(notification: Notification) {
    guard let item = notification.object as? AVPlayerItem,
      let errorLog = item.errorLog()
    else { return }

    for event in errorLog.events ?? [] {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Error log - \(event.errorComment ?? "Unknown error") - Code: \(event.errorStatusCode)")
    }

    // Also check item error
    if let error = item.error {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Item error - \(error.localizedDescription)")
    }
  }

  @objc private func playerItemTimeJumped(notification: Notification) {
    guard let player = player,
      let currentItem = player.currentItem
    else { return }

    let position = currentItem.currentTime().seconds
    let duration = currentItem.duration.seconds

    NitroPlayerLogger.log("TrackPlayerCore", "🎯 Time jumped (seek detected) - position: \(Int(position))s")

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

    NitroPlayerLogger.log("TrackPlayerCore", "👀 KVO - keyPath: \(keyPath ?? "nil")")

    if keyPath == "status" {
      NitroPlayerLogger.log("TrackPlayerCore", "👀 Player status changed to: \(player.status.rawValue)")
      if player.status == .readyToPlay {
        emitStateChange()
      } else if player.status == .failed {
        NitroPlayerLogger.log("TrackPlayerCore", "❌ Player failed")
        notifyPlaybackStateChange(.stopped, .error)
      }
    } else if keyPath == "rate" {
      NitroPlayerLogger.log("TrackPlayerCore", "👀 Rate changed to: \(player.rate)")
      emitStateChange()
    } else if keyPath == "timeControlStatus" {
      NitroPlayerLogger.log("TrackPlayerCore", "👀 TimeControlStatus changed to: \(player.timeControlStatus.rawValue)")
      emitStateChange()
    } else if keyPath == "currentItem" {
      NitroPlayerLogger.log("TrackPlayerCore", "👀 Current item changed")
      currentItemDidChange()
    }
  }

  // MARK: - Item Change Handling

  @objc private func currentItemDidChange() {
    // Clear old item observers
    currentItemObservers.removeAll()

    // Reset proactive URL check debounce for the new track
    didRequestUrlsForCurrentItem = false

    // Track changed - update index
    guard let player = player,
      let currentItem = player.currentItem
    else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Current item changed to nil")
      // Queue exhausted — handle PLAYLIST repeat
      if currentRepeatMode == .playlist && !currentTracks.isEmpty, let player = player {
        NitroPlayerLogger.log("TrackPlayerCore", "🔁 PLAYLIST repeat — rebuilding original queue and restarting")
        playNextStack.removeAll()
        upNextQueue.removeAll()
        currentTemporaryType = .none

        let allItems = currentTracks.compactMap { createGaplessPlayerItem(for: $0, isPreload: false) }
        var lastItem: AVPlayerItem? = nil
        for item in allItems {
          player.insert(item, after: lastItem)
          lastItem = item
        }
        currentTrackIndex = 0
        player.play()

        if let firstTrack = currentTracks.first {
          notifyTrackChange(firstTrack, .repeat)
          mediaSessionManager?.onTrackChanged()
        }
      }
      return
    }

    #if DEBUG
    NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "▶", count: Constants.separatorLineLength))
    NitroPlayerLogger.log("TrackPlayerCore", "🔄 CURRENT ITEM CHANGED")
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "▶", count: Constants.separatorLineLength))

    // Log current item details
    if let trackId = currentItem.trackId,
      let track = currentTracks.first(where: { $0.id == trackId })
    {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️  NOW PLAYING: \(track.title) - \(track.artist) (ID: \(track.id))")
    } else {
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️  NOW PLAYING: Unknown track (trackId: \(currentItem.trackId ?? "nil"))")
    }

    // Show remaining items in queue
    let remainingItems = player.items()
    NitroPlayerLogger.log("TrackPlayerCore", "\n📋 REMAINING ITEMS IN QUEUE: \(remainingItems.count)")
    for (index, item) in remainingItems.enumerated() {
      if let trackId = item.trackId, let track = currentTracks.first(where: { $0.id == trackId }) {
        let marker = item == currentItem ? "▶️" : "  "
        NitroPlayerLogger.log("TrackPlayerCore", "\(marker) [\(index + 1)] \(track.title) - \(track.artist)")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   [\(index + 1)] ⚠️ Unknown track")
      }
    }

    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "▶", count: Constants.separatorLineLength) + "\n")
    #endif

    // Log item status
    NitroPlayerLogger.log("TrackPlayerCore", "📱 Item status: \(currentItem.status.rawValue)")

    // Check for errors
    if let error = currentItem.error {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Current item has error - \(error.localizedDescription)")
    }

    // Setup KVO observers for current item
    setupCurrentItemObservers(item: currentItem)

    // Update track index and determine temporary type
    if let trackId = currentItem.trackId {
      NitroPlayerLogger.log("TrackPlayerCore", "🔍 Looking up trackId '\(trackId)' in currentTracks...")
      NitroPlayerLogger.log("TrackPlayerCore", "   Current index BEFORE lookup: \(currentTrackIndex)")

      // Update temporary type
      currentTemporaryType = determineCurrentTemporaryType()
      NitroPlayerLogger.log("TrackPlayerCore", "   🎯 Track type: \(currentTemporaryType)")

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
          NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Temporary track: \(track.title) - \(track.artist)")
          NitroPlayerLogger.log("TrackPlayerCore", "   📢 Emitting onChangeTrack for temporary track")
          notifyTrackChange(track, .skip)
          mediaSessionManager?.onTrackChanged()
        }
      }
      // It's an original playlist track
      else if let index = currentTracks.firstIndex(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Found track at index: \(index)")
        NitroPlayerLogger.log("TrackPlayerCore", "   Setting currentTrackIndex from \(currentTrackIndex) to \(index)")

        let oldIndex = currentTrackIndex
        currentTrackIndex = index

        if let track = currentTracks[safe: index] {
          NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Track: \(track.title) - \(track.artist)")

          // Only emit onChangeTrack if index actually changed
          // This prevents duplicate emissions
          if oldIndex != index {
            NitroPlayerLogger.log("TrackPlayerCore", "   📢 Emitting onChangeTrack (index changed from \(oldIndex) to \(index))")
            notifyTrackChange(track, .skip)
            mediaSessionManager?.onTrackChanged()
          } else {
            NitroPlayerLogger.log("TrackPlayerCore", "   ⏭️ Skipping onChangeTrack emission (index unchanged)")
          }
        }
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   ⚠️ Track ID '\(trackId)' NOT FOUND in currentTracks!")
        #if DEBUG
        NitroPlayerLogger.log("TrackPlayerCore", "   Current tracks:")
        for (idx, track) in currentTracks.enumerated() {
          NitroPlayerLogger.log("TrackPlayerCore", "      [\(idx)] \(track.id) - \(track.title)")
        }
        #endif
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
    NitroPlayerLogger.log("TrackPlayerCore", "📱 Setting up item observers")

    // Observe status - recreate boundaries when ready and update now playing info
    let statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      if item.status == .readyToPlay {
        NitroPlayerLogger.log("TrackPlayerCore", "✅ Item ready, setting up boundaries")
        self?.setupBoundaryTimeObserver()
        // First item is buffered and ready — disable stall waiting for gapless inter-track transitions
        self?.player?.automaticallyWaitsToMinimizeStalling = false
        // Update now playing info now that duration is available
        self?.mediaSessionManager?.updateNowPlayingInfo()
      } else if item.status == .failed {
        NitroPlayerLogger.log("TrackPlayerCore", "❌ Item failed")
        self?.notifyPlaybackStateChange(.stopped, .error)
      }
    }
    currentItemObservers.append(statusObserver)

    // Observe playback buffer
    let bufferEmptyObserver = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { item, _ in
      if item.isPlaybackBufferEmpty {
        NitroPlayerLogger.log("TrackPlayerCore", "⏸️ Buffer empty (buffering)")
      }
    }
    currentItemObservers.append(bufferEmptyObserver)

    let bufferKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) {
      item, _ in
      if item.isPlaybackLikelyToKeepUp {
        NitroPlayerLogger.log("TrackPlayerCore", "▶️ Buffer likely to keep up")
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
  
  func setPlaybackSpeed(_ speed: Double) {
    player?.rate = Float(speed)
  }
  
  func getPlaybackSpeed() -> Double {
    return Double(player?.rate ?? 1.0)
  }

  private func loadPlaylistInternal(playlistId: String) {
    NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "🎼", count: Constants.playlistSeparatorLength))
    NitroPlayerLogger.log("TrackPlayerCore", "📂 LOAD PLAYLIST REQUEST")
    NitroPlayerLogger.log("TrackPlayerCore", "   Playlist ID: \(playlistId)")

    // Clear temporary tracks when loading new playlist
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

    let playlist = self.playlistManager.getPlaylist(playlistId: playlistId)
    if let playlist = playlist {
      NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Found playlist: \(playlist.name)")
      NitroPlayerLogger.log("TrackPlayerCore", "   📋 Contains \(playlist.tracks.count) tracks:")
      for (index, track) in playlist.tracks.enumerated() {
        NitroPlayerLogger.log("TrackPlayerCore", "      [\(index + 1)] \(track.title) - \(track.artist)")
      }
      NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")

      self.currentPlaylistId = playlistId
      self.updatePlayerQueue(tracks: playlist.tracks)
      // Emit initial state (paused/stopped before play)
      self.emitStateChange()

      // Check if upcoming tracks need URLs
      self.checkUpcomingTracksForUrls(lookahead: lookaheadCount)
    } else {
      NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Playlist NOT FOUND")
      NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "🎼", count: Constants.playlistSeparatorLength) + "\n")
    }
  }

  func updatePlaylist(playlistId: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      guard self.currentPlaylistId == playlistId,
        let playlist = self.playlistManager.getPlaylist(playlistId: playlistId)
      else { return }

      // If nothing is playing yet, do a full load
      guard let player = self.player, player.currentItem != nil else {
        self.updatePlayerQueue(tracks: playlist.tracks)
        return
      }

      // Update tracks list without interrupting playback
      self.currentTracks = playlist.tracks

      // Rebuild only the items after the currently playing item
      self.rebuildAVQueueFromCurrentPosition()
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

    NitroPlayerLogger.log("TrackPlayerCore", "🔔 Emitting state change: \(state)")
    NitroPlayerLogger.log("TrackPlayerCore", "🔔 Callback exists: \(!onPlaybackStateChangeListeners.isEmpty)")
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
      NitroPlayerLogger.log("TrackPlayerCore", "📥 Using DOWNLOADED version for \(track.title)")
      NitroPlayerLogger.log("TrackPlayerCore", "   Local path: \(effectiveUrlString)")

      // Verify file exists
      if FileManager.default.fileExists(atPath: effectiveUrlString) {
        url = URL(fileURLWithPath: effectiveUrlString)
        NitroPlayerLogger.log("TrackPlayerCore", "   File URL: \(url.absoluteString)")
        NitroPlayerLogger.log("TrackPlayerCore", "   ✅ File verified to exist")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "   ❌ Downloaded file does NOT exist at path!")
        NitroPlayerLogger.log("TrackPlayerCore", "   Falling back to remote URL: \(track.url)")
        guard let remoteUrl = URL(string: track.url) else {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Invalid remote URL: \(track.url)")
          return nil
        }
        url = remoteUrl
      }
    } else {
      // Remote URL
      guard let remoteUrl = URL(string: effectiveUrlString) else {
        NitroPlayerLogger.log("TrackPlayerCore", "❌ Invalid URL for track: \(track.title) - \(effectiveUrlString)")
        return nil
      }
      url = remoteUrl
      NitroPlayerLogger.log("TrackPlayerCore", "🌐 Using REMOTE version for \(track.title)")
    }

    // Check if we have a preloaded asset for this track
    let asset: AVURLAsset
    if let preloadedAsset = preloadedAssets[track.id] {
      asset = preloadedAsset
      NitroPlayerLogger.log("TrackPlayerCore", "🚀 Using preloaded asset for \(track.title)")
    } else {
      asset = AVURLAsset(url: url, options: [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
      ])
    }

    let item = AVPlayerItem(asset: asset)

    // Let the system choose the optimal forward buffer size (0 = automatic).
    // An explicit cap (e.g. 30 s) limits how much of the *next* queued item
    // AVQueuePlayer pre-rolls, which can cause audible gaps on HTTP streams.
    item.preferredForwardBufferDuration = 0

    // Enable automatic loading of item properties for faster starts
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

    // Store track ID for later reference
    item.trackId = track.id

    // If this is a preload request, start loading asset keys asynchronously.
    // EQ is applied INSIDE the completion handler so the "tracks" key is
    // already loaded → applyAudioMix takes the synchronous fast-path and
    // the tap is attached before AVQueuePlayer pre-rolls the item.
    if isPreload {
      asset.loadValuesAsynchronously(forKeys: Constants.preloadAssetKeys) {
        // Asset keys are now loaded, which speeds up playback start
        var allKeysLoaded = true
        for key in Constants.preloadAssetKeys {
          var error: NSError?
          let status = asset.statusOfValue(forKey: key, error: &error)
          if status == .failed {
            NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Failed to load key '\(key)' for \(track.title): \(error?.localizedDescription ?? "unknown")")
            allKeysLoaded = false
          }
        }
        if allKeysLoaded {
          NitroPlayerLogger.log("TrackPlayerCore", "✅ All asset keys preloaded for \(track.title)")
        }
        // "tracks" key is now loaded — EQ tap attaches synchronously
        EqualizerCore.shared.applyAudioMix(to: item)
      }
    } else {
      // Non-preload: asset may already have keys loaded (preloadedAssets cache)
      // so applyAudioMix will use the sync path if possible, async otherwise.
      EqualizerCore.shared.applyAudioMix(to: item)
    }

    return item
  }

  /// Preloads assets for upcoming tracks to enable gapless playback
  private func preloadUpcomingTracks(from startIndex: Int) {
    // Capture the set of track IDs that already have AVPlayerItems in the
    // queue (main-thread access). Creating duplicate AVURLAssets for these
    // would start parallel HTTP downloads for the same URLs, competing
    // with AVQueuePlayer's own pre-roll buffering and potentially starving
    // the next-item buffer — resulting in an audible gap at the transition.
    let queuedTrackIds = Set(player?.items().compactMap { $0.trackId } ?? [])

    preloadQueue.async { [weak self] in
      guard let self = self else { return }

      // Capture currentTracks to avoid race condition with main thread
      let tracks = self.currentTracks
      let endIndex = min(startIndex + Constants.gaplessPreloadCount, tracks.count)

      for i in startIndex..<endIndex {
        guard i < tracks.count else { break }
        let track = tracks[i]

        // Skip if already preloaded OR already in the player queue
        if self.preloadedAssets[track.id] != nil || queuedTrackIds.contains(track.id) {
          continue
        }

        // Use effective URL so downloaded tracks preload from disk, not network
        let effectiveUrlString = DownloadManagerCore.shared.getEffectiveUrl(track: track)
        let isLocal = effectiveUrlString.hasPrefix("/")

        let url: URL
        if isLocal {
          url = URL(fileURLWithPath: effectiveUrlString)
        } else {
          guard let remoteUrl = URL(string: effectiveUrlString) else { continue }
          url = remoteUrl
        }

        let asset = AVURLAsset(url: url, options: [
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
              NitroPlayerLogger.log("TrackPlayerCore", "🎯 Preloaded asset for upcoming track: \(track.title)")
            }
          }
        }
      }
    }
  }

  /// Clears preloaded assets that are no longer needed
  private func cleanupPreloadedAssets(keepingFrom currentIndex: Int) {
    // Must run on main thread — preloadedAssets is only mutated on main
    DispatchQueue.main.async { [weak self] in
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
        NitroPlayerLogger.log("TrackPlayerCore", "🧹 Cleaned up \(assetsToRemove.count) preloaded assets")
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
      NitroPlayerLogger.log("TrackPlayerCore", "🎯 Added onChangeTrack listener (total: \(self?.onChangeTrackListeners.count ?? 0))")
    }
  }

  func addOnPlaybackStateChangeListener(
    owner: AnyObject,
    _ listener: @escaping (TrackPlayerState, Reason?) -> Void
  ) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onPlaybackStateChangeListeners.append(box)
      NitroPlayerLogger.log("TrackPlayerCore", "🎯 Added onPlaybackStateChange listener (total: \(self?.onPlaybackStateChangeListeners.count ?? 0))")
    }
  }

  func addOnSeekListener(owner: AnyObject, _ listener: @escaping (Double, Double) -> Void) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onSeekListeners.append(box)
      NitroPlayerLogger.log("TrackPlayerCore", "🎯 Added onSeek listener (total: \(self?.onSeekListeners.count ?? 0))")
    }
  }

  func addOnPlaybackProgressChangeListener(
    owner: AnyObject,
    _ listener: @escaping (Double, Double, Bool?) -> Void
  ) {
    let box = WeakCallbackBox(owner: owner, callback: listener)
    listenersQueue.async(flags: .barrier) { [weak self] in
      self?.onPlaybackProgressChangeListeners.append(box)
      NitroPlayerLogger.log("TrackPlayerCore", "🎯 Added onPlaybackProgressChange listener (total: \(self?.onPlaybackProgressChangeListeners.count ?? 0))")
    }
  }

  // MARK: - Listener Notification Helpers

  private func notifyTrackChange(_ track: TrackItem, _ reason: Reason?) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      // Remove dead listeners
      self.onChangeTrackListeners.removeAll { !$0.isAlive }

      // Get live callbacks (all remaining are alive after removeAll)
      let liveCallbacks = self.onChangeTrackListeners.map { $0.callback }

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

      let liveCallbacks = self.onPlaybackStateChangeListeners.map { $0.callback }

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

      let liveCallbacks = self.onSeekListeners.map { $0.callback }

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

      let liveCallbacks = self.onPlaybackProgressChangeListeners.map { $0.callback }

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
    NitroPlayerLogger.log("TrackPlayerCore", "\n" + String(repeating: "=", count: Constants.separatorLineLength))
    NitroPlayerLogger.log("TrackPlayerCore", "📋 UPDATE PLAYER QUEUE - Received \(tracks.count) tracks")
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength))

    #if DEBUG
    for (index, track) in tracks.enumerated() {
      let isDownloaded = DownloadManagerCore.shared.isTrackDownloaded(trackId: track.id)
      let downloadStatus = isDownloaded ? "📥 DOWNLOADED" : "🌐 REMOTE"
      NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] 🎵 \(track.title) - \(track.artist) (ID: \(track.id)) - \(downloadStatus)")
      if isDownloaded {
        if let localPath = DownloadManagerCore.shared.getLocalPath(trackId: track.id) {
          NitroPlayerLogger.log("TrackPlayerCore", "      Local path: \(localPath)")
        }
      }
    }
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength) + "\n")
    #endif

    // Store tracks for index tracking
    currentTracks = tracks
    currentTrackIndex = 0
    NitroPlayerLogger.log("TrackPlayerCore", "🔢 Reset currentTrackIndex to 0 (will be updated by KVO observer)")

    // Remove old boundary observer if exists (this is safe)
    if let boundaryObserver = boundaryTimeObserver, let currentPlayer = player {
      currentPlayer.removeTimeObserver(boundaryObserver)
      boundaryTimeObserver = nil
    }

    // Re-enable stall waiting for the new first track so it buffers before playing.
    // Will be flipped back to false once the first item reaches readyToPlay.
    player?.automaticallyWaitsToMinimizeStalling = true

    // Clear old preloaded assets when loading new queue
    preloadedAssets.removeAll()

    // Replace current queue (player should always exist after setupPlayer)
    guard let existingPlayer = self.player else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player available")
      return
    }

    // Always clear old items so a stale playlist doesn't keep playing.
    NitroPlayerLogger.log("TrackPlayerCore", "🔄 Removing \(existingPlayer.items().count) old items from player")
    existingPlayer.removeAllItems()

    // Lazy-load mode: if any track has no URL AND is not downloaded locally,
    // we can't create an AVPlayerItem for it and the queue order would be wrong.
    // Downloaded tracks with empty remote URLs still play from disk via getEffectiveUrl.
    let isLazyLoad = tracks.contains {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }
    if isLazyLoad {
      NitroPlayerLogger.log("TrackPlayerCore", "⏳ Lazy-load mode — player cleared, awaiting URL resolution")
      return
    }

    // Create gapless-optimized AVPlayerItems from tracks
    let items = tracks.enumerated().compactMap { (index, track) -> AVPlayerItem? in
      let isPreload = index < Constants.gaplessPreloadCount
      return createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🎵 Created \(items.count) gapless-optimized player items")

    guard !items.isEmpty else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No valid items to play")
      return
    }

    NitroPlayerLogger.log("TrackPlayerCore", "🔄 Adding \(items.count) new items to player")

    // Add new items IN ORDER
    // IMPORTANT: insert(after: nil) puts item at the start
    // To maintain order, we need to track the last inserted item
    var lastItem: AVPlayerItem? = nil
    for (index, item) in items.enumerated() {
      existingPlayer.insert(item, after: lastItem)
      lastItem = item

      #if DEBUG
      if let trackId = item.trackId, let track = tracks.first(where: { $0.id == trackId }) {
        NitroPlayerLogger.log("TrackPlayerCore", "  ➕ Added to player queue [\(index + 1)]: \(track.title)")
      }
      #endif
    }

    #if DEBUG
    let trackById = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
    NitroPlayerLogger.log("TrackPlayerCore", "\n🔍 VERIFICATION - Player now has \(existingPlayer.items().count) items:")
    for (index, item) in existingPlayer.items().enumerated() {
      if let trackId = item.trackId, let track = trackById[trackId] {
        NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] ✓ \(track.title) - \(track.artist) (ID: \(track.id))")
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "  [\(index + 1)] ⚠️ Unknown item (no trackId)")
      }
    }
    if let currentItem = existingPlayer.currentItem,
      let trackId = currentItem.trackId,
      let track = trackById[trackId]
    {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️  Current item: \(track.title)")
    }
    NitroPlayerLogger.log("TrackPlayerCore", String(repeating: "=", count: Constants.separatorLineLength) + "\n")
    #endif

    // Note: Boundary time observers will be set up automatically when item becomes ready
    // This happens in setupCurrentItemObservers() -> status observer -> setupBoundaryTimeObserver()

    // Notify track change
    if let firstTrack = tracks.first {
      NitroPlayerLogger.log("TrackPlayerCore", "🎵 Emitting track change: \(firstTrack.title)")
      NitroPlayerLogger.log("TrackPlayerCore", "🎵 onChangeTrack callbacks count: \(onChangeTrackListeners.count)")
      notifyTrackChange(firstTrack, nil)
      mediaSessionManager?.onTrackChanged()
    }

    // Start preloading upcoming tracks for gapless playback
    preloadUpcomingTracks(from: 1)

    NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue updated with \(items.count) gapless-optimized tracks")
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
    queue.reserveCapacity(currentTracks.count + playNextStack.count + upNextQueue.count)

    // Add tracks before current (original playlist)
    // When a temp track is playing, include the original track at currentTrackIndex
    // (it already played before the temp track started)
    let beforeEnd = currentTemporaryType != .none
      ? min(currentTrackIndex + 1, currentTracks.count) : currentTrackIndex
    if beforeEnd > 0 {
      queue.append(contentsOf: currentTracks[0..<beforeEnd])
    }

    // Add current track (temp or original)
    if let current = getCurrentTrack() {
      queue.append(current)
    }

    // Add playNext stack (LIFO - most recently added plays first)
    // Skip index 0 if current track is from playNext (it's already added as current)
    if currentTemporaryType == .playNext && playNextStack.count > 1 {
      queue.append(contentsOf: playNextStack.dropFirst())
    } else if currentTemporaryType != .playNext {
      queue.append(contentsOf: playNextStack)
    }

    // Add upNext queue (in order, FIFO)
    // Skip index 0 if current track is from upNext (it's already added as current)
    if currentTemporaryType == .upNext && upNextQueue.count > 1 {
      queue.append(contentsOf: upNextQueue.dropFirst())
    } else if currentTemporaryType != .upNext {
      queue.append(contentsOf: upNextQueue)
    }

    // Add remaining original tracks
    if currentTrackIndex + 1 < currentTracks.count {
      queue.append(contentsOf: currentTracks[(currentTrackIndex + 1)...])
    }

    return queue
  }

  func play() {
    NitroPlayerLogger.log("TrackPlayerCore", "▶️ play() called")
    if Thread.isMainThread {
      playInternal()
    } else {
      DispatchQueue.main.sync { [weak self] in
        self?.playInternal()
      }
    }
  }

  private func playInternal() {
    NitroPlayerLogger.log("TrackPlayerCore", "▶️ Calling player.play()")
    if let player = self.player {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️ Player status: \(player.status.rawValue)")
      if let currentItem = player.currentItem {
        NitroPlayerLogger.log("TrackPlayerCore", "▶️ Current item status: \(currentItem.status.rawValue)")
        if let error = currentItem.error {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Current item error: \(error.localizedDescription)")
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
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player available")
    }
  }

  func pause() {
    NitroPlayerLogger.log("TrackPlayerCore", "⏸️ pause() called")
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
    NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

    var targetPlaylistId: String?
    var songIndex: Int = -1

    // Case 1: If fromPlaylist is provided, use that playlist
    if let playlistId = fromPlaylist {
      NitroPlayerLogger.log("TrackPlayerCore", "🎵 Looking for song in specified playlist: \(playlistId)")
      if let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) {
        if let index = playlist.tracks.firstIndex(where: { $0.id == songId }) {
          targetPlaylistId = playlistId
          songIndex = index
          NitroPlayerLogger.log("TrackPlayerCore", "✅ Found song at index \(index) in playlist \(playlistId)")
        } else {
          NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Song \(songId) not found in specified playlist \(playlistId)")
          return
        }
      } else {
        NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Playlist \(playlistId) not found")
        return
      }
    }
    // Case 2: If fromPlaylist is not provided, search in current/loaded playlist first
    else {
      NitroPlayerLogger.log("TrackPlayerCore", "🎵 No playlist specified, checking current playlist")

      // Check if song exists in currently loaded playlist
      if let currentId = self.currentPlaylistId,
        let currentPlaylist = self.playlistManager.getPlaylist(playlistId: currentId)
      {
        if let index = currentPlaylist.tracks.firstIndex(where: { $0.id == songId }) {
          targetPlaylistId = currentId
          songIndex = index
          NitroPlayerLogger.log("TrackPlayerCore", "✅ Found song at index \(index) in current playlist \(currentId)")
        }
      }

      // If not found in current playlist, search in all playlists
      if songIndex == -1 {
        NitroPlayerLogger.log("TrackPlayerCore", "🔍 Song not found in current playlist, searching all playlists...")
        let allPlaylists = self.playlistManager.getAllPlaylists()

        for playlist in allPlaylists {
          if let index = playlist.tracks.firstIndex(where: { $0.id == songId }) {
            targetPlaylistId = playlist.id
            songIndex = index
            NitroPlayerLogger.log("TrackPlayerCore", "✅ Found song at index \(index) in playlist \(playlist.id)")
            break
          }
        }

        // If still not found, just use the first playlist if available
        if songIndex == -1 && !allPlaylists.isEmpty {
          targetPlaylistId = allPlaylists[0].id
          songIndex = 0
          NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Song not found in any playlist, using first playlist and starting at index 0")
        }
      }
    }

    // Now play the song
    guard let playlistId = targetPlaylistId, songIndex >= 0 else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Could not determine playlist or song index")
      return
    }

    // Load playlist if it's different from current
    if self.currentPlaylistId != playlistId {
      NitroPlayerLogger.log("TrackPlayerCore", "🔄 Loading new playlist: \(playlistId)")
      if let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) {
        self.currentPlaylistId = playlistId
        self.updatePlayerQueue(tracks: playlist.tracks)
      }
    }

    // Play from the found index
    NitroPlayerLogger.log("TrackPlayerCore", "▶️ Playing from index: \(songIndex)")
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

    // Lazy-load: AVQueuePlayer is empty because updatePlayerQueue deferred population.
    // Delegate to playFromIndexInternal which handles both the has-URL (rebuild queue)
    // and no-URL (defer + emit) cases correctly.
    if queuePlayer.items().isEmpty && !currentTracks.isEmpty {
      let nextIndex = currentTrackIndex + 1
      if nextIndex < currentTracks.count {
        _ = skipToIndexInternal(index: nextIndex)
      }
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      return
    }

    // Remove current temp track from its list before advancing
    if let trackId = queuePlayer.currentItem?.trackId {
      if currentTemporaryType == .playNext {
        if let idx = playNextStack.firstIndex(where: { $0.id == trackId }) {
          playNextStack.remove(at: idx)
        }
      } else if currentTemporaryType == .upNext {
        if let idx = upNextQueue.firstIndex(where: { $0.id == trackId }) {
          upNextQueue.remove(at: idx)
        }
      }
    }

    // Check if there are more items in the player queue
    if queuePlayer.items().count > 1 {
      queuePlayer.advanceToNextItem()
    } else {
      queuePlayer.pause()
      self.notifyPlaybackStateChange(.stopped, .end)
    }

    // Check if upcoming tracks need URLs
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
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

    let currentTime = queuePlayer.currentTime()
    if currentTime.seconds > Constants.skipToPreviousThreshold {
      // If more than threshold seconds in, restart current track
      queuePlayer.seek(to: .zero)
    } else if self.currentTemporaryType != .none {
      // Playing temporary track — remove from its list, then restart
      if let trackId = queuePlayer.currentItem?.trackId {
        if currentTemporaryType == .playNext {
          if let idx = playNextStack.firstIndex(where: { $0.id == trackId }) {
            playNextStack.remove(at: idx)
          }
        } else if currentTemporaryType == .upNext {
          if let idx = upNextQueue.firstIndex(where: { $0.id == trackId }) {
            upNextQueue.remove(at: idx)
          }
        }
      }
      // Go to current original track position (skip back from temp)
      self.rebuildQueueFromPlaylistIndex(index: self.currentTrackIndex)
    } else if self.currentTrackIndex > 0 {
      // Go to previous track in original playlist
      let previousIndex = self.currentTrackIndex - 1
      self.rebuildQueueFromPlaylistIndex(index: previousIndex)
    } else {
      // Already at first track, restart it
      queuePlayer.seek(to: .zero)
    }

    // Check if upcoming tracks need URLs
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
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
      // Always update now playing info to restore playback rate after seek
      // This ensures the scrubber animation resumes correctly
      self?.mediaSessionManager?.updateNowPlayingInfo()
      
      if completed {
        let duration = player.currentItem?.duration.seconds ?? 0.0
        self?.notifySeek(position, duration)
      }
    }
  }

  // MARK: - Repeat Mode

  func setRepeatMode(mode: RepeatMode) -> Bool {
    currentRepeatMode = mode
    DispatchQueue.main.async { [weak self] in
      self?.player?.actionAtItemEnd = (mode == .track) ? .none : .advance
    }
    NitroPlayerLogger.log("TrackPlayerCore", "🔁 setRepeatMode: \(mode)")
    return true
  }

  func getRepeatMode() -> RepeatMode {
    return currentRepeatMode
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
    showInNotification: Bool?,
    lookaheadCount: Int? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      if let lookahead = lookaheadCount {
        self?.lookaheadCount = lookahead
        NitroPlayerLogger.log("TrackPlayerCore", "🔄 Lookahead count set to: \(lookahead)")
      }
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
      NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Cannot set volume - no player available")
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
      NitroPlayerLogger.log("TrackPlayerCore", "🔊 Volume set to \(Int(clampedVolume))% (normalized: \(normalizedVolume))")
    }
    return true
  }

  func playFromIndex(index: Int) {
    if Thread.isMainThread {
      rebuildQueueFromPlaylistIndex(index: index)
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.rebuildQueueFromPlaylistIndex(index: index)
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
    // Get actual queue to validate index and determine position
    let actualQueue = getActualQueueInternal()
    let totalQueueSize = actualQueue.count

    // Validate index
    guard index >= 0 && index < totalQueueSize else { return false }

    // Calculate queue section boundaries using effective sizes
    // (reduced by 1 when current track is from that temp list, matching getActualQueueInternal)
    // When temp is playing, the original track at currentTrackIndex is included in "before",
    // so the current playing position shifts by 1
    let currentPos = currentTemporaryType != .none
      ? currentTrackIndex + 1 : currentTrackIndex
    let effectivePlayNextSize = currentTemporaryType == .playNext
      ? max(0, playNextStack.count - 1) : playNextStack.count
    let effectiveUpNextSize = currentTemporaryType == .upNext
      ? max(0, upNextQueue.count - 1) : upNextQueue.count

    let playNextStart = currentPos + 1
    let playNextEnd = playNextStart + effectivePlayNextSize
    let upNextStart = playNextEnd
    let upNextEnd = upNextStart + effectiveUpNextSize
    let originalRemainingStart = upNextEnd

    // Case 1: Target is before current - rebuild from that playlist index
    if index < currentPos {
      rebuildQueueFromPlaylistIndex(index: index)
      return true
    }

    // Case 2: Target is current - seek to beginning
    if index == currentPos {
      player?.seek(to: .zero)
      return true
    }

    // Case 3: Target is in playNext section
    if index >= playNextStart && index < playNextEnd {
      let playNextIndex = index - playNextStart
      // Offset by 1 if current is from playNext (index 0 is already playing)
      let actualListIndex = currentTemporaryType == .playNext
        ? playNextIndex + 1 : playNextIndex

      // Remove tracks before the target from playNext (they're being skipped)
      if actualListIndex > 0 {
        playNextStack.removeFirst(actualListIndex)
      }

      // Rebuild queue and advance
      rebuildAVQueueFromCurrentPosition()
      player?.advanceToNextItem()
      return true
    }

    // Case 4: Target is in upNext section
    if index >= upNextStart && index < upNextEnd {
      let upNextIndex = index - upNextStart
      // Offset by 1 if current is from upNext (index 0 is already playing)
      let actualListIndex = currentTemporaryType == .upNext
        ? upNextIndex + 1 : upNextIndex

      // Clear all playNext tracks (they're being skipped)
      playNextStack.removeAll()

      // Remove tracks before target from upNext
      if actualListIndex > 0 {
        upNextQueue.removeFirst(actualListIndex)
      }

      // Rebuild queue and advance
      rebuildAVQueueFromCurrentPosition()
      player?.advanceToNextItem()
      return true
    }

    // Case 5: Target is in remaining original tracks
    if index >= originalRemainingStart {
      let targetTrack = actualQueue[index]

      // Find this track's index in the original playlist
      guard let originalIndex = currentTracks.firstIndex(where: { $0.id == targetTrack.id }) else {
        return false
      }

      // Clear all temporary tracks (they're being skipped)
      playNextStack.removeAll()
      upNextQueue.removeAll()
      currentTemporaryType = .none

      let result = rebuildQueueFromPlaylistIndex(index: originalIndex)

      // Check if upcoming tracks need URLs
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)

      return result
    }

    // Check if upcoming tracks need URLs after any successful skip
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)

    return false
  }

  /// Clears temporary tracks, rebuilds AVQueuePlayer from `index` in the original playlist,
  /// and resumes playback only if the player was already playing (preserves paused state).
  @discardableResult
  private func rebuildQueueFromPlaylistIndex(index: Int) -> Bool {
    guard index >= 0 && index < self.currentTracks.count else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ rebuildQueueFromPlaylistIndex - invalid index \(index), currentTracks.count = \(self.currentTracks.count)")
      return false
    }

    NitroPlayerLogger.log("TrackPlayerCore", "\n🎯 REBUILD QUEUE FROM PLAYLIST INDEX \(index)")
    NitroPlayerLogger.log("TrackPlayerCore", "   Total tracks in playlist: \(self.currentTracks.count)")
    NitroPlayerLogger.log("TrackPlayerCore", "   Current index: \(self.currentTrackIndex), target index: \(index)")

    // Preserve playback state — only resume if already playing.
    // This prevents auto-starting when called during queue setup (e.g. loadPlaylist → skipToIndex).
    let wasPlaying = self.player?.rate ?? 0 > 0

    // Clear temporary tracks when jumping to specific index
    self.playNextStack.removeAll()
    self.upNextQueue.removeAll()
    self.currentTemporaryType = .none
    NitroPlayerLogger.log("TrackPlayerCore", "   🧹 Cleared temporary tracks")

    // Store the full playlist
    let fullPlaylist = self.currentTracks

    // Update currentTrackIndex BEFORE updating queue
    self.currentTrackIndex = index

    // Lazy-load guard: if the target track has no URL AND is not downloaded locally,
    // the queue can't be built. Defer to updateTracks once URL resolution completes.
    // Downloaded tracks play from disk via getEffectiveUrl — no remote URL needed.
    let targetTrack = fullPlaylist[index]
    let isLazyLoad = targetTrack.url.isEmpty
      && !DownloadManagerCore.shared.isTrackDownloaded(trackId: targetTrack.id)
    if isLazyLoad {
      NitroPlayerLogger.log("TrackPlayerCore", "   ⏳ Lazy-load — deferring AVQueuePlayer setup; emitting track change for index \(index)")
      self.currentTracks = fullPlaylist
      if let track = self.currentTracks[safe: index] {
        notifyTrackChange(track, .skip)
        self.mediaSessionManager?.onTrackChanged()
      }
      return true
    }

    // Recreate the queue starting from the target index
    // This ensures all remaining tracks are in the queue
    let tracksToPlay = Array(fullPlaylist[index...])
    NitroPlayerLogger.log("TrackPlayerCore", "   🔄 Creating gapless queue with \(tracksToPlay.count) tracks starting from index \(index)")

    // Create gapless-optimized player items
    let items = tracksToPlay.enumerated().compactMap { (offset, track) -> AVPlayerItem? in
      let isPreload = offset < Constants.gaplessPreloadCount
      return self.createGaplessPlayerItem(for: track, isPreload: isPreload)
    }

    guard let player = self.player, !items.isEmpty else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player or no items to play")
      return false
    }

    // Remove old boundary observer
    if let boundaryObserver = self.boundaryTimeObserver {
      player.removeTimeObserver(boundaryObserver)
      self.boundaryTimeObserver = nil
    }

    // Re-enable stall waiting for the new first track so it buffers before playing.
    // Will be flipped back to false once the first item reaches readyToPlay.
    player.automaticallyWaitsToMinimizeStalling = true

    // Clear and rebuild queue
    player.removeAllItems()
    var lastItem: AVPlayerItem? = nil
    for item in items {
      player.insert(item, after: lastItem)
      lastItem = item
    }

    // Restore the full playlist reference (don't slice it!)
    self.currentTracks = fullPlaylist

    NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Gapless queue recreated. Now at index: \(self.currentTrackIndex)")
    if let track = self.getCurrentTrack() {
      NitroPlayerLogger.log("TrackPlayerCore", "   🎵 Playing: \(track.title)")
      notifyTrackChange(track, .skip)
      self.mediaSessionManager?.onTrackChanged()
    }

    // Start preloading upcoming tracks for gapless playback
    self.preloadUpcomingTracks(from: index + 1)

    // Only resume playback if the player was already playing before we rebuilt
    // the loaded playlist. This prevents auto-starting when called during queue setup
    // (e.g. loadPlaylist → skipToIndex).
    if wasPlaying {
      player.play()
    }
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
    NitroPlayerLogger.log("TrackPlayerCore", "📋 addToUpNext(\(trackId))")

    // Find the track from current playlist or all playlists
    guard let track = self.findTrackById(trackId) else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Track \(trackId) not found")
      return
    }

    // Add to end of upNext queue (FIFO)
    self.upNextQueue.append(track)
    NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Added '\(track.title)' to upNext queue (position: \(self.upNextQueue.count))")

    // Rebuild the player queue if actively playing
    if self.player?.currentItem != nil {
      self.rebuildAVQueueFromCurrentPosition()
    }
    mediaSessionManager?.onQueueChanged()
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
    NitroPlayerLogger.log("TrackPlayerCore", "⏭️ playNext(\(trackId))")

    // Find the track from current playlist or all playlists
    guard let track = self.findTrackById(trackId) else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Track \(trackId) not found")
      return
    }

    // Insert at beginning of playNext stack (LIFO)
    self.playNextStack.insert(track, at: 0)
    NitroPlayerLogger.log("TrackPlayerCore", "   ✅ Added '\(track.title)' to playNext stack (position: 1)")

    // Rebuild the player queue if actively playing
    if self.player?.currentItem != nil {
      self.rebuildAVQueueFromCurrentPosition()
    }
    mediaSessionManager?.onQueueChanged()
  }

  /**
   * Rebuild the AVQueuePlayer from current position with temporary tracks
   * Order: [current] + [playNext stack reversed] + [upNext queue] + [remaining original]
   *
   * - Parameter changedTrackIds: When non-nil, performs a **surgical** update:
   *   only AVPlayerItems whose track ID is in this set are removed and re-created.
   *   All other pre-buffered items are left in place and new items are inserted
   *   around them. This preserves AVQueuePlayer's internal audio pre-roll buffers
   *   for gapless inter-track transitions.
   *   When nil, the queue is fully torn down and rebuilt (used by skip, reorder,
   *   addToUpNext, playNext, etc.).
   */
  private func rebuildAVQueueFromCurrentPosition(changedTrackIds: Set<String>? = nil) {
    guard let player = self.player else { return }

    let currentItem = player.currentItem
    let playingItems = player.items()

    // ---- Build the desired upcoming track list ----

    var newQueueTracks: [TrackItem] = []

    // Add playNext stack (LIFO - most recently added plays first)
    if currentTemporaryType == .playNext && playNextStack.count > 1 {
      newQueueTracks.append(contentsOf: playNextStack.dropFirst())
    } else if currentTemporaryType != .playNext {
      newQueueTracks.append(contentsOf: playNextStack)
    }

    // Add upNext queue (in order, FIFO)
    if currentTemporaryType == .upNext && upNextQueue.count > 1 {
      newQueueTracks.append(contentsOf: upNextQueue.dropFirst())
    } else if currentTemporaryType != .upNext {
      newQueueTracks.append(contentsOf: upNextQueue)
    }

    // Add remaining original tracks
    if currentTrackIndex + 1 < currentTracks.count {
      newQueueTracks.append(contentsOf: currentTracks[(currentTrackIndex + 1)...])
    }

    // ---- Collect existing upcoming AVPlayerItems ----

    let upcomingItems: [AVPlayerItem]
    if let ci = currentItem, let ciIndex = playingItems.firstIndex(of: ci) {
      upcomingItems = Array(playingItems.suffix(from: playingItems.index(after: ciIndex)))
    } else {
      upcomingItems = []
    }

    let existingIds = upcomingItems.compactMap { $0.trackId }
    let desiredIds = newQueueTracks.map { $0.id }

    // ---- Fast-path: nothing to do if queue already matches ----

    if existingIds == desiredIds {
      if let changedIds = changedTrackIds {
        if Set(existingIds).isDisjoint(with: changedIds) {
          NitroPlayerLogger.log("TrackPlayerCore",
            "✅ Queue matches & no buffered URLs changed — preserving \(existingIds.count) items for gapless")
          return
        }
      } else {
        NitroPlayerLogger.log("TrackPlayerCore",
          "✅ Queue already matches desired order — preserving \(existingIds.count) items for gapless")
        return
      }
    }

    // ---- Surgical path (changedTrackIds provided, e.g. from updateTracks) ----
    // Only remove items whose URLs actually changed; insert newly-resolved items
    // in the correct positions around existing, pre-buffered items.

    if let changedIds = changedTrackIds {
      // Build lookup of reusable (un-changed) items by track ID
      var reusableByTrackId: [String: AVPlayerItem] = [:]
      for item in upcomingItems {
        if let trackId = item.trackId, !changedIds.contains(trackId) {
          reusableByTrackId[trackId] = item
        }
      }

      // Remove only items whose URLs changed
      let desiredIdSet = Set(desiredIds)
      for item in upcomingItems {
        guard let trackId = item.trackId else { continue }
        if changedIds.contains(trackId) || !desiredIdSet.contains(trackId) {
          player.remove(item)
        }
      }

      // Walk through the desired order, inserting new items around the
      // reusable items that are still sitting in the queue untouched.
      var lastAnchor: AVPlayerItem? = currentItem
      for trackId in desiredIds {
        if let reusable = reusableByTrackId[trackId] {
          // Item is still in the queue at its original position — advance anchor
          lastAnchor = reusable
        } else if let track = newQueueTracks.first(where: { $0.id == trackId }),
          let newItem = createGaplessPlayerItem(for: track, isPreload: false)
        {
          player.insert(newItem, after: lastAnchor)
          lastAnchor = newItem
        }
      }

      let preserved = reusableByTrackId.count
      let inserted = desiredIds.count - preserved
      NitroPlayerLogger.log("TrackPlayerCore",
        "🔄 Surgical rebuild: preserved \(preserved) buffered items, inserted \(inserted) new items")
      return
    }

    // ---- Full rebuild path (no changedTrackIds — skip, reorder, etc.) ----

    for item in playingItems where item != currentItem {
      player.remove(item)
    }

    var lastItem = currentItem
    for track in newQueueTracks {
      if let item = createGaplessPlayerItem(for: track, isPreload: false) {
        player.insert(item, after: lastItem)
        lastItem = item
      }
    }
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

  // MARK: - Lazy URL Loading Support

  /**
   * Update entire track objects and rebuild queue if needed
   * Skips currently playing track to preserve gapless playback
   * CRITICAL: Invalidates preloaded assets and re-preloads for gapless
   */
  func updateTracks(tracks: [TrackItem]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      NitroPlayerLogger.log("TrackPlayerCore", "🔄 updateTracks: \(tracks.count) updates")

      // Get current track to decide how to handle it
      let currentTrack = self.getCurrentTrack()
      let currentTrackId = currentTrack?.id
      // A track is only "empty" if it has no remote URL AND is not downloaded.
      // Downloaded tracks with empty .url are playing from disk — don't replace them.
      let currentTrackIsEmpty = currentTrack.map {
        $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
      } ?? false

      // Filter out current track and validate
      let safeTracks = tracks.filter { track in
        switch true {
        case track.id == currentTrackId && !currentTrackIsEmpty:
          // Has a real URL already — skip to preserve gapless playback
          NitroPlayerLogger.log(
            "TrackPlayerCore",
            "⚠️ Skipping update for currently playing track: \(track.id) (preserves gapless)")
          return false
        case track.id == currentTrackId && currentTrackIsEmpty:
          // Empty URL — must not be playing, allow the update (only if the new URL is real)
          NitroPlayerLogger.log(
            "TrackPlayerCore",
            "🔄 Updating current track with no URL: \(track.id)")
          return !track.url.isEmpty
        case track.url.isEmpty:
          NitroPlayerLogger.log(
            "TrackPlayerCore", "⚠️ Skipping track with empty URL: \(track.id)")
          return false
        default:
          return true
        }
      }

      guard !safeTracks.isEmpty else {
        NitroPlayerLogger.log("TrackPlayerCore", "✅ No valid updates to apply")
        return
      }

      // Invalidate preloaded assets for tracks with updated data
      // This is CRITICAL for gapless playback - old assets might use old URLs
      let updatedTrackIds = Set(safeTracks.map { $0.id })
      for trackId in updatedTrackIds {
        if self.preloadedAssets[trackId] != nil {
          NitroPlayerLogger.log(
            "TrackPlayerCore", "🗑️ Invalidating preloaded asset for track: \(trackId)")
          self.preloadedAssets.removeValue(forKey: trackId)
        }
      }

      // Update in PlaylistManager
      let affectedPlaylists = self.playlistManager.updateTracks(tracks: safeTracks)

      // If the current track had no URL and now has one, replace the current AVPlayerItem
      if let update = currentTrack, currentTrackIsEmpty, !update.url.isEmpty {
        NitroPlayerLogger.log(
          "TrackPlayerCore", "🔄 Replacing current AVPlayerItem for track with resolved URL: \(update.id)")
        if let newItem = self.createGaplessPlayerItem(for: update, isPreload: false) {
          self.player?.replaceCurrentItem(with: newItem)
        }
      }

      // Rebuild queue if current playlist was affected  
      if let currentId = self.currentPlaylistId,
        let updateCount = affectedPlaylists[currentId]
      {
        NitroPlayerLogger.log(
          "TrackPlayerCore",
          "🔄 Rebuilding queue - \(updateCount) tracks updated in current playlist")

        // Sync currentTracks from the freshly-updated PlaylistManager so rebuilds use resolved URLs
        if let updatedPlaylist = self.playlistManager.getPlaylist(playlistId: currentId) {
          self.currentTracks = updatedPlaylist.tracks
          NitroPlayerLogger.log("TrackPlayerCore", "📥 Synced currentTracks from PlaylistManager (\(self.currentTracks.count) tracks)")
        }

        if self.player?.currentItem == nil, let player = self.player {
          // No AVPlayerItem exists yet — lazy-load mode: URLs were empty when the queue first
          // loaded. Rebuild the full queue from currentTrackIndex now that URLs are resolved.
          NitroPlayerLogger.log(
            "TrackPlayerCore",
            "🔄 No current item — full queue rebuild from currentTrackIndex \(self.currentTrackIndex)")
          player.removeAllItems()
          var lastItem: AVPlayerItem? = nil
          for (offset, track) in self.currentTracks[self.currentTrackIndex...].enumerated() {
            let isPreload = offset < Constants.gaplessPreloadCount
            if let newItem = self.createGaplessPlayerItem(for: track, isPreload: isPreload) {
              player.insert(newItem, after: lastItem)
              lastItem = newItem
            }
          }
          player.play()
          self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
        } else {
          // A current AVPlayerItem already exists — preserve it and only rebuild upcoming items.
          // Pass the set of track IDs whose URLs actually changed so the rebuild
          // can keep already-buffered items intact for gapless transitions.
          self.rebuildAVQueueFromCurrentPosition(changedTrackIds: updatedTrackIds)
          // Re-preload upcoming tracks for gapless playback
          // CRITICAL: This restores gapless buffering after queue rebuild
          self.preloadUpcomingTracks(from: self.currentTrackIndex + 1)
        }

        NitroPlayerLogger.log("TrackPlayerCore", "✅ Queue rebuilt, gapless playback preserved")
      }

      NitroPlayerLogger.log(
        "TrackPlayerCore",
        "✅ Track updates complete - \(affectedPlaylists.count) playlists affected")
    }
  }

  /**
   * Get tracks by IDs from all playlists
   */
  func getTracksById(trackIds: [String]) -> [TrackItem] {
    if Thread.isMainThread {
      return playlistManager.getTracksById(trackIds: trackIds)
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.playlistManager.getTracksById(trackIds: trackIds) ?? []
      }
      return tracks
    }
  }

  /**
   * Get tracks needing URLs from current playlist
   */
  func getTracksNeedingUrls() -> [TrackItem] {
    if Thread.isMainThread {
      return getTracksNeedingUrlsInternal()
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.getTracksNeedingUrlsInternal() ?? []
      }
      return tracks
    }
  }

  private func getTracksNeedingUrlsInternal() -> [TrackItem] {
    guard let currentId = currentPlaylistId,
      let playlist = playlistManager.getPlaylist(playlistId: currentId)
    else {
      return []
    }

    // Only return tracks that truly can't play: empty remote URL AND not
    // downloaded locally.  Downloaded tracks play from disk via getEffectiveUrl.
    return playlist.tracks.filter {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }
  }

  /**
   * Get next N tracks from current position
   */
  func getNextTracks(count: Int) -> [TrackItem] {
    if Thread.isMainThread {
      return getNextTracksInternal(count: count)
    } else {
      var tracks: [TrackItem] = []
      DispatchQueue.main.sync { [weak self] in
        tracks = self?.getNextTracksInternal(count: count) ?? []
      }
      return tracks
    }
  }

  private func getNextTracksInternal(count: Int) -> [TrackItem] {
    let actualQueue = getActualQueueInternal()
    guard !actualQueue.isEmpty else { return [] }

    guard let currentTrack = getCurrentTrack(),
      let currentIndex = actualQueue.firstIndex(where: { $0.id == currentTrack.id })
    else {
      return []
    }

    let startIndex = currentIndex + 1
    let endIndex = min(startIndex + count, actualQueue.count)

    return startIndex < actualQueue.count ? Array(actualQueue[startIndex..<endIndex]) : []
  }

  /**
   * Get current track index in playlist
   */
  func getCurrentTrackIndex() -> Int {
    if Thread.isMainThread {
      return currentTrackIndex
    } else {
      var index = -1
      DispatchQueue.main.sync { [weak self] in
        index = self?.currentTrackIndex ?? -1
      }
      return index
    }
  }

  /**
   * Callback for tracks needing update
   */
  typealias OnTracksNeedUpdateCallback = ([TrackItem], Int) -> Void

  // Add to class properties
  private var onTracksNeedUpdateListeners: [(callback: OnTracksNeedUpdateCallback, isAlive: Bool)] =
    []
  private let tracksNeedUpdateQueue = DispatchQueue(
    label: "com.nitroplayer.tracksneedupdate", attributes: .concurrent)

  /**
   * Register listener for when tracks need update
   */
  func addOnTracksNeedUpdateListener(callback: @escaping OnTracksNeedUpdateCallback) {
    tracksNeedUpdateQueue.async(flags: .barrier) { [weak self] in
      self?.onTracksNeedUpdateListeners.append((callback: callback, isAlive: true))
    }
  }

  /**
   * Notify listeners that tracks need updating
   */
  private func notifyTracksNeedUpdate(tracks: [TrackItem], lookahead: Int) {
    tracksNeedUpdateQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }

      // Clean up dead listeners
      self.onTracksNeedUpdateListeners.removeAll { !$0.isAlive }
      let liveCallbacks = self.onTracksNeedUpdateListeners.map { $0.callback }

      if !liveCallbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in liveCallbacks {
            callback(tracks, lookahead)
          }
        }
      }
    }
  }

  /**
   * Check if upcoming tracks need URLs and notify listeners
   * Call this in playerItemDidPlayToEndTime or after skip operations
   */
  private func checkUpcomingTracksForUrls(lookahead: Int = 5) {
    let upcomingTracks = getNextTracksInternal(count: lookahead)

    // Always include the current track if it has no URL and isn't downloaded — it can't play without one
    let currentTrack = getCurrentTrack()
    let currentNeedsUrl = currentTrack.map {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    } ?? false
    let candidateTracks = currentNeedsUrl ? [currentTrack!] + upcomingTracks : upcomingTracks

    // Only request URLs for tracks that truly can't play: empty remote URL
    // AND not downloaded locally (downloaded tracks play from disk via getEffectiveUrl).
    let tracksNeedingUrls = candidateTracks.filter {
      $0.url.isEmpty && !DownloadManagerCore.shared.isTrackDownloaded(trackId: $0.id)
    }

    if !tracksNeedingUrls.isEmpty {
      NitroPlayerLogger.log(
        "TrackPlayerCore", "⚠️ \(tracksNeedingUrls.count) upcoming tracks need URLs")
      notifyTracksNeedUpdate(tracks: tracksNeedingUrls, lookahead: lookahead)
    }
  }

  // MARK: - Cleanup

  deinit {
    NitroPlayerLogger.log("TrackPlayerCore", "🧹 Cleaning up...")

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
      NitroPlayerLogger.log("TrackPlayerCore", "✅ Player observers removed")
    }

    // Remove all notification observers
    NotificationCenter.default.removeObserver(self)
    NitroPlayerLogger.log("TrackPlayerCore", "✅ Cleanup complete")
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
