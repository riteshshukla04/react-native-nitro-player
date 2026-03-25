//
//  TrackPlayerCore.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//
import AVFoundation
import Foundation
import MediaPlayer
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
  internal var pendingPlaylistUpdateWorkItem: DispatchWorkItem?
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
      self?.mediaSessionManager = MediaSessionManager()
      self?.mediaSessionManager?.setTrackPlayerCore(self!)
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
      self.preloadedAssets.removeAll()
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
