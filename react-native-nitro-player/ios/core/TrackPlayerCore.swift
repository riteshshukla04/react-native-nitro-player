//
//  TrackPlayerCore.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//
import AVFoundation
import Foundation
import MediaPlayer
import Network
import NitroModules
import ObjectiveC

class TrackPlayerCore: NSObject {
  // MARK: - Constants
  enum Constants {
    static let skipToPreviousThreshold: Double = 2.0
    static let stateChangeDelay: TimeInterval = 0.1
    static let twoHoursInSeconds: Double = 7200
    static let oneHourInSeconds: Double = 3600
    static let boundaryIntervalLong: Double = 5.0
    static let boundaryIntervalMedium: Double = 2.0
    static let boundaryIntervalDefault: Double = 1.0
    static let separatorLineLength: Int = 80
    static let playlistSeparatorLength: Int = 40
    static let preferredForwardBufferDuration: Double = 30.0
    static let preloadAssetKeys: [String] = ["playable", "duration", "tracks", "preferredTransform"]
    static let gaplessPreloadCount: Int = 3
    /// Upcoming AVPlayerItems kept materialized behind the current one. The logical
    /// queue (currentTracks + temp lists) stays complete; only the AVQueuePlayer is
    /// windowed, and it is topped up on every item transition.
    static let queueWindowSize: Int = 4
    // Stall & failure recovery
    static let maxFailedItemRetries: Int = 3
    static let failedItemRetryDelay: TimeInterval = 2.0
  }

  // MARK: - Thread infrastructure
  internal let playerQueue = DispatchQueue(label: "com.nitroplayer.player", qos: .userInitiated)
  internal let playerQueueKey = DispatchSpecificKey<Bool>()

  // MARK: - Player
  internal var player: AVQueuePlayer?
  internal let playlistManager = PlaylistManager.shared
  internal var mediaSessionManager: MediaSessionManager?

  // MARK: - Playback state
  internal var currentPlaylistId: String?
  internal var currentTrackIndex: Int = -1
  internal var currentTracks: [TrackItem] = []
  // Bumped on every updatePlaylist request (playerQueue-owned). A queued rebuild
  // whose generation is stale was superseded by a later request and is dropped,
  // so a burst of playlist mutations collapses into a single rebuild.
  internal var playlistUpdateGeneration: UInt64 = 0
  internal var isManuallySeeked = false
  internal var currentRepeatMode: RepeatMode = .off
  internal var currentPlaybackSpeed: Double = 1.0
  internal var lookaheadCount: Int = 5
  internal var boundaryTimeObserver: Any?
  internal var currentItemObservers: [NSKeyValueObservation] = []

  // Gapless playback
  internal var preloadedAssets: [String: AVURLAsset] = [:]
  internal let preloadQueue = DispatchQueue(label: "com.nitroplayer.preload", qos: .utility)
  internal var didRequestUrlsForCurrentItem = false

  // Follows http→https redirects that AVURLAsset otherwise silently drops (issue #111).
  // Attached as the resource-loader delegate for cleartext-http assets only.
  internal let redirectResolver = TrackPlayerRedirectResolver()

  // MARK: - Stall & network recovery
  // Whether the user/app wants playback ongoing (true after play(), false after pause()).
  internal var intendedToPlay = false
  // Set when AVPlayer stalls on a buffer underrun; cleared once the buffer refills.
  // Needed because automaticallyWaitsToMinimizeStalling == false means AVPlayer
  // will NOT auto-resume after a stall — we must re-issue play() ourselves.
  internal var isRecoveringFromStall = false
  // True while an audio-session interruption (phone call, Siri, other app) is active.
  // Recovery must NOT resume playback during this window even though `intendedToPlay`
  // may still be true — the system decides whether to resume when the interruption ends.
  internal var isInterrupted = false
  // Set right before `recoverFailedItem` swaps the current item in place. Tells the
  // resulting `currentItemDidChange` that this is an in-place recovery of the SAME
  // track, not a real track change — so it must not emit onChangeTrack or reset
  // per-track state. Consumed (cleared) by the next `currentItemDidChange`.
  internal var suppressTrackChangeEmit = false
  // Last observed playback position, used to resume after recreating a failed item.
  internal var lastKnownPosition: Double = 0
  // Per-track retry budget for recreating AVPlayerItems that hit status == .failed.
  internal var failedItemRetryCounts: [String: Int] = [:]
  // Monitors network path changes (VPN toggle, Wi-Fi band switch) to drive recovery.
  internal var pathMonitor: NWPathMonitor?
  // Starts unsatisfied so the first genuine `.satisfied` update is treated as a
  // transition (and so a network that starts down is not mistaken for "up").
  internal var lastPathStatus: NWPath.Status = .unsatisfied

  // MARK: - Temporary queue
  internal var playNextStack: [TrackItem] = []
  internal var upNextQueue: [TrackItem] = []
  internal var currentTemporaryType: TemporaryType = .none

  internal enum TemporaryType {
    case none, playNext, upNext
  }

  // MARK: - Listener registries (v2 — replaces WeakCallbackBox)
  internal let onChangeTrackListeners         = ListenerRegistry<(TrackItem, Reason?) -> Void>()
  internal let onPlaybackStateChangeListeners = ListenerRegistry<(TrackPlayerState, Reason?) -> Void>()
  internal let onSeekListeners                = ListenerRegistry<(Double, Double) -> Void>()
  internal let onProgressListeners            = ListenerRegistry<(Double, Double, Bool?) -> Void>()
  internal let onTracksNeedUpdateListeners    = ListenerRegistry<([TrackItem], Int) -> Void>()
  internal let onTemporaryQueueChangeListeners = ListenerRegistry<([TrackItem], [TrackItem]) -> Void>()
  internal let onCastStateChangeListeners     = ListenerRegistry<(CastState, String?) -> Void>()

  // MARK: - Google Cast
  /// Owns the GoogleCast session; created on the main thread in init. Cast features
  /// are inert no-ops if the GoogleCast SDK is not linked.
  internal var castManager: CastSessionManager?
  /// True while playback is routed to a Cast device (audio plays only on the device).
  internal var isCasting = false

  // MARK: - Singleton
  static let shared = TrackPlayerCore()

  // MARK: - Initialization
  private override init() {
    super.init()
    playerQueue.setSpecific(key: playerQueueKey, value: true)
    setupAudioSession()
    playerQueue.async { [weak self] in
      self?.setupPlayer()
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.mediaSessionManager = MediaSessionManager()
      self.mediaSessionManager?.setTrackPlayerCore(self)
      // Initialize Cast with the Default Media Receiver. Apps can override the
      // receiver ID early via Cast.configure(id). No-op without the GoogleCast SDK.
      self.castManager = CastSessionManager()
      self.castManager?.core = self
      self.castManager?.configure(receiverApplicationId: nil)
    }
  }

  internal func setupAudioSession() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .default, options: [])
      try audioSession.setActive(true)
    } catch {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Failed to setup audio session - \(error)")
    }
  }

  // MARK: - withPlayerQueue (async bridge to player thread)

  internal func withPlayerQueue<T>(_ block: @escaping () throws -> T) async throws -> T {
    if DispatchQueue.getSpecific(key: playerQueueKey) == true { return try block() }
    return try await withCheckedThrowingContinuation { cont in
      playerQueue.async {
        do { cont.resume(returning: try block()) }
        catch { cont.resume(throwing: error) }
      }
    }
  }

  @discardableResult
  internal func withPlayerQueueNoThrow<T>(_ block: @escaping () -> T) async -> T {
    if DispatchQueue.getSpecific(key: playerQueueKey) == true { return block() }
    return await withCheckedContinuation { cont in
      playerQueue.async { cont.resume(returning: block()) }
    }
  }

  // MARK: - Listener add/remove (returns stable ID for cleanup)

  @discardableResult func addOnChangeTrackListener(_ cb: @escaping (TrackItem, Reason?) -> Void) -> Int64 {
    onChangeTrackListeners.add(cb)
  }
  @discardableResult func removeOnChangeTrackListener(id: Int64) -> Bool {
    onChangeTrackListeners.remove(id: id)
  }

  @discardableResult func addOnPlaybackStateChangeListener(_ cb: @escaping (TrackPlayerState, Reason?) -> Void) -> Int64 {
    onPlaybackStateChangeListeners.add(cb)
  }
  @discardableResult func removeOnPlaybackStateChangeListener(id: Int64) -> Bool {
    onPlaybackStateChangeListeners.remove(id: id)
  }

  @discardableResult func addOnSeekListener(_ cb: @escaping (Double, Double) -> Void) -> Int64 {
    onSeekListeners.add(cb)
  }
  @discardableResult func removeOnSeekListener(id: Int64) -> Bool {
    onSeekListeners.remove(id: id)
  }

  @discardableResult func addOnProgressListener(_ cb: @escaping (Double, Double, Bool?) -> Void) -> Int64 {
    onProgressListeners.add(cb)
  }
  @discardableResult func removeOnProgressListener(id: Int64) -> Bool {
    onProgressListeners.remove(id: id)
  }

  @discardableResult func addOnTracksNeedUpdateListener(_ cb: @escaping ([TrackItem], Int) -> Void) -> Int64 {
    onTracksNeedUpdateListeners.add(cb)
  }
  @discardableResult func removeOnTracksNeedUpdateListener(id: Int64) -> Bool {
    onTracksNeedUpdateListeners.remove(id: id)
  }

  @discardableResult func addOnTemporaryQueueChangeListener(_ cb: @escaping ([TrackItem], [TrackItem]) -> Void) -> Int64 {
    onTemporaryQueueChangeListeners.add(cb)
  }
  @discardableResult func removeOnTemporaryQueueChangeListener(id: Int64) -> Bool {
    onTemporaryQueueChangeListeners.remove(id: id)
  }

  @discardableResult func addOnCastStateChangeListener(_ cb: @escaping (CastState, String?) -> Void) -> Int64 {
    onCastStateChangeListeners.add(cb)
  }
  @discardableResult func removeOnCastStateChangeListener(id: Int64) -> Bool {
    onCastStateChangeListeners.remove(id: id)
  }

  // MARK: - Simple accessors
  func getCurrentPlaylistId() -> String? { currentPlaylistId }
  func getPlaylistManager() -> PlaylistManager { playlistManager }
  func isAndroidAutoConnected() -> Bool { false } // iOS stub
  func getRepeatMode() -> RepeatMode { currentRepeatMode }

  // MARK: - Lifecycle
  func destroy() {
    playerQueue.async { [weak self] in
      guard let self else { return }
      if let obs = self.boundaryTimeObserver, let p = self.player {
        p.removeTimeObserver(obs)
      }
      self.currentItemObservers.removeAll()
      if let p = self.player {
        p.removeObserver(self, forKeyPath: "status")
        p.removeObserver(self, forKeyPath: "rate")
        p.removeObserver(self, forKeyPath: "timeControlStatus")
        p.removeObserver(self, forKeyPath: "currentItem")
      }
      NotificationCenter.default.removeObserver(self)
      self.pathMonitor?.cancel()
      self.pathMonitor = nil
      self.preloadedAssets.values.forEach { $0.cancelLoading() }
      self.preloadedAssets.removeAll()
      self.failedItemRetryCounts.removeAll()
      self.redirectResolver.clear()
    }
  }

  deinit {
    NitroPlayerLogger.log("TrackPlayerCore", "🧹 deinit")
  }
}

// Safe array subscript
extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

// Associated object for AVPlayerItem trackId
private var trackIdKey: UInt8 = 0
extension AVPlayerItem {
  var trackId: String? {
    get { objc_getAssociatedObject(self, &trackIdKey) as? String }
    set { objc_setAssociatedObject(self, &trackIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
  }
}
