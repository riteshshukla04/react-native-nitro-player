//
//  CastSessionManager.swift
//  NitroPlayer
//
//  Owns the Google Cast session lifecycle and remote media client, and bridges
//  Cast events back into TrackPlayerCore. All GoogleCast usage is guarded by
//  `#if canImport(GoogleCast)` so the library still builds when the SDK is not
//  linked — in that case every method is an inert no-op and casting is disabled.
//
//  Threading: the GoogleCast SDK is main-thread-affine, so every SDK call hops to
//  main via `onMain`. Core state lives on `playerQueue` and Nitro sync getters run
//  on the JS thread, so everything the core/JS reads back is served from small
//  lock-guarded caches that the main-thread Cast callbacks keep fresh.
//

import Foundation
import MediaPlayer

#if canImport(GoogleCast)
import GoogleCast
#endif

final class CastSessionManager: NSObject {
  weak var core: TrackPlayerCore?

  private var isConfigured = false
  private var progressTimer: Timer?

  // MARK: - Lock-guarded caches (written on main, read from playerQueue / JS thread)

  private let stateLock = NSLock()
  private var _lastCurrentTrackId: String?
  private var _loadedTracks: [TrackItem] = []
  private var _hasLoadedMedia = false
  private var _cachedPlaybackState: TrackPlayerState = .stopped
  private var _lastEmittedPlaybackState: TrackPlayerState?
  private var _lastKnownRemotePosition: Double = 0
  private var _lastKnownRemoteDuration: Double = 0
  private var cachedState: CastState = .noDevicesAvailable
  private var cachedDeviceName: String?

  /// Track ID of the item currently playing on the receiver (or expected to be,
  /// right after a locally-initiated jump).
  var currentRemoteTrackId: String? {
    stateLock.lock(); defer { stateLock.unlock() }
    return _lastCurrentTrackId
  }

  /// IDs of the tracks last sent to the receiver, in queue order.
  var loadedTrackIds: [String] {
    stateLock.lock(); defer { stateLock.unlock() }
    return _loadedTracks.map { $0.id }
  }

  /// Whether the receiver currently has media loaded.
  var hasLoadedMedia: Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    return _hasLoadedMedia
  }

  /// Last position reported by the receiver, used to resume locally on disconnect.
  var lastKnownRemotePosition: Double {
    stateLock.lock(); defer { stateLock.unlock() }
    return _lastKnownRemotePosition
  }

  /// Last duration reported by the receiver for the current item.
  var lastKnownRemoteDuration: Double {
    stateLock.lock(); defer { stateLock.unlock() }
    return _lastKnownRemoteDuration
  }

  /// Last playback state reported by the receiver.
  var cachedPlaybackState: TrackPlayerState {
    stateLock.lock(); defer { stateLock.unlock() }
    return _cachedPlaybackState
  }

  /// Pre-set the expected current track after a locally-initiated jump so the
  /// receiver's own status echo doesn't produce a duplicate track-change event.
  func setExpectedCurrentTrack(_ trackId: String?) {
    stateLock.lock(); defer { stateLock.unlock() }
    _lastCurrentTrackId = trackId
  }

  private func withState<T>(_ body: () -> T) -> T {
    stateLock.lock(); defer { stateLock.unlock() }
    return body()
  }

  // MARK: - Configuration

  func configure(receiverApplicationId: String?) {
    #if canImport(GoogleCast)
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.isConfigured else { return }
      self.isConfigured = true

      let appId = receiverApplicationId ?? kGCKDefaultMediaReceiverApplicationID
      let criteria = GCKDiscoveryCriteria(applicationID: appId)
      let options = GCKCastOptions(discoveryCriteria: criteria)
      options.suspendSessionsWhenBackgrounded = false
      // We expose a custom Cast button (not GCKUICastButton), so device discovery
      // must begin immediately instead of waiting for a tap on a GCKUICastButton —
      // otherwise no devices are ever found.
      options.startDiscoveryAfterFirstTapOnCastButton = false
      GCKCastContext.setSharedInstanceWith(options)

      let context = GCKCastContext.sharedInstance()
      // Begin scanning right away so devices are available before the picker opens.
      context.discoveryManager.startDiscovery()
      context.sessionManager.add(self)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(self.castStateDidChange),
        name: NSNotification.Name.gckCastStateDidChange,
        object: nil
      )
      self.emitCastState()
    }
    #endif
  }

  // MARK: - State

  var isCasting: Bool {
    #if canImport(GoogleCast)
    return currentCastState() == .connected
    #else
    return false
    #endif
  }

  /// Cached — safe to call from the JS thread.
  func currentCastState() -> CastState {
    stateLock.lock(); defer { stateLock.unlock() }
    return cachedState
  }

  /// Cached — safe to call from the JS thread.
  func deviceName() -> String? {
    stateLock.lock(); defer { stateLock.unlock() }
    return cachedDeviceName
  }

  // MARK: - UI / session control

  func showCastPicker() {
    #if canImport(GoogleCast)
    DispatchQueue.main.async {
      guard self.isConfigured else { return }
      GCKCastContext.sharedInstance().presentCastDialog()
    }
    #endif
  }

  func endSession() {
    #if canImport(GoogleCast)
    DispatchQueue.main.async {
      guard self.isConfigured else { return }
      GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }
    #endif
  }

  // MARK: - Transport (all dispatched to main — GoogleCast is main-thread only)

  func play() {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.play() }
    #endif
  }

  func pause() {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.pause() }
    #endif
  }

  func seek(to position: Double) {
    #if canImport(GoogleCast)
    onMain {
      let options = GCKMediaSeekOptions()
      options.interval = position
      self.remoteClient?.seek(with: options)
    }
    #endif
  }

  func skipToNext() {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.queueNextItem() }
    #endif
  }

  func setVolume(_ volume0to1: Float) {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.setStreamVolume(volume0to1) }
    #endif
  }

  func setPlaybackRate(_ rate: Float) {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.setPlaybackRate(rate) }
    #endif
  }

  func setQueueRepeatMode(_ mode: RepeatMode) {
    #if canImport(GoogleCast)
    onMain {
      let gckMode: GCKMediaRepeatMode
      switch mode {
      case .track: gckMode = .single
      case .playlist: gckMode = .all
      default: gckMode = .off
      }
      self.remoteClient?.queueSetRepeatMode(gckMode)
    }
    #endif
  }

  /// Stop and unload whatever the receiver is playing (used when jumping to a
  /// track whose URL is not resolved yet — the load happens after updateTracks).
  func stop() {
    #if canImport(GoogleCast)
    // No-op when nothing is loaded — avoids a pointless receiver RPC on every
    // updateTracks re-entry while still waiting for the target's URL.
    let hadMedia: Bool = withState {
      let had = _hasLoadedMedia || !_loadedTracks.isEmpty
      _hasLoadedMedia = false
      _loadedTracks = []
      return had
    }
    guard hadMedia else { return }
    onMain { self.remoteClient?.stop() }
    #endif
  }

  // MARK: - Queue loading

  /// Atomically replace the receiver queue. `tracks` must already be castable
  /// (non-empty remote URLs) and start at the item that should play.
  func loadQueue(tracks: [TrackItem], position: Double, autoplay: Bool, repeatMode: RepeatMode) {
    #if canImport(GoogleCast)
    guard !tracks.isEmpty else { return }
    withState {
      _loadedTracks = tracks
      _hasLoadedMedia = true // optimistic; corrected by the next media status
      _lastCurrentTrackId = tracks.first?.id
    }
    onMain {
      guard let client = self.remoteClient else { return }
      let items = tracks.compactMap { self.makeQueueItem(for: $0, autoplay: autoplay) }
      guard !items.isEmpty else { return }

      let options = GCKMediaQueueLoadOptions()
      options.startIndex = 0
      options.playPosition = position.isFinite ? max(0, position) : 0
      switch repeatMode {
      case .track: options.repeatMode = .single
      case .playlist: options.repeatMode = .all
      default: options.repeatMode = .off
      }
      client.queueLoad(items, with: options)
    }
    #endif
  }

  /// Append tracks to the END of the receiver queue without touching playback.
  func appendToQueue(tracks: [TrackItem]) {
    #if canImport(GoogleCast)
    guard !tracks.isEmpty else { return }
    withState {
      let known = Set(_loadedTracks.map { $0.id })
      _loadedTracks.append(contentsOf: tracks.filter { !known.contains($0.id) })
    }
    onMain {
      guard let client = self.remoteClient else { return }
      let items = tracks.compactMap { self.makeQueueItem(for: $0, autoplay: true) }
      guard !items.isEmpty else { return }
      client.queueInsert(items, beforeItemWithID: kGCKMediaQueueInvalidItemID)
    }
    #endif
  }

  // MARK: - Private helpers

  private func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
  }

  #if canImport(GoogleCast)
  private var remoteClient: GCKRemoteMediaClient? {
    guard isConfigured else { return nil }
    return GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
  }

  private func makeQueueItem(for track: TrackItem, autoplay: Bool) -> GCKMediaQueueItem? {
    // The receiver fetches media itself: only a remote URL is playable there —
    // never a downloaded file path. Callers pre-filter with isTrackCastable.
    let urlString = track.url
    guard !urlString.isEmpty, let contentURL = URL(string: urlString) else { return nil }

    let metadata = GCKMediaMetadata(metadataType: .musicTrack)
    metadata.setString(track.title, forKey: kGCKMetadataKeyTitle)
    metadata.setString(track.artist, forKey: kGCKMetadataKeyArtist)
    metadata.setString(track.album, forKey: kGCKMetadataKeyAlbumTitle)
    if let artwork = track.artwork, case let .second(art) = artwork, let artURL = URL(string: art) {
      metadata.addImage(GCKImage(url: artURL, width: 0, height: 0))
    }

    let infoBuilder = GCKMediaInformationBuilder(contentURL: contentURL)
    infoBuilder.streamType = .buffered
    infoBuilder.contentType = inferMimeType(urlString)
    infoBuilder.metadata = metadata
    infoBuilder.customData = ["trackId": track.id]

    let itemBuilder = GCKMediaQueueItemBuilder()
    itemBuilder.mediaInformation = infoBuilder.build()
    itemBuilder.autoplay = autoplay
    itemBuilder.preloadTime = 5
    return itemBuilder.build()
  }

  private func inferMimeType(_ url: String) -> String {
    let path = url.components(separatedBy: "?").first?.lowercased() ?? url.lowercased()
    if path.hasSuffix(".m3u8") { return "application/x-mpegurl" }
    if path.hasSuffix(".mpd") { return "application/dash+xml" }
    if path.hasSuffix(".flac") { return "audio/flac" }
    if path.hasSuffix(".wav") { return "audio/wav" }
    if path.hasSuffix(".opus") { return "audio/opus" }
    if path.hasSuffix(".ogg") { return "audio/ogg" }
    if path.hasSuffix(".aac") { return "audio/aac" }
    if path.hasSuffix(".m4a") || path.hasSuffix(".mp4") { return "audio/mp4" }
    return "audio/mpeg"
  }

  private func startProgressTimer() {
    onMain {
      self.progressTimer?.invalidate()
      self.progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.tickProgress()
      }
    }
  }

  private func stopProgressTimer() {
    onMain {
      self.progressTimer?.invalidate()
      self.progressTimer = nil
    }
  }

  private func tickProgress() {
    guard let client = remoteClient else { return }
    let position = client.approximateStreamPosition()
    let duration = client.mediaStatus?.mediaInformation?.streamDuration ?? 0
    let safeDuration = (duration.isFinite && duration > 0) ? duration : 0
    withState {
      if position.isFinite { _lastKnownRemotePosition = position }
      _lastKnownRemoteDuration = safeDuration
    }
    core?.emitCastProgress(position.isFinite ? position : 0, safeDuration)
    updateNowPlaying(position: position, duration: safeDuration)
  }

  /// Resolve the track currently playing on the receiver from its custom data.
  private func currentRemoteTrack(_ status: GCKMediaStatus?) -> TrackItem? {
    guard let status else { return nil }
    let item = status.queueItem(withItemID: status.currentItemID)
    let info = item?.mediaInformation ?? status.mediaInformation
    guard let customData = info?.customData as? [String: Any],
          let trackId = customData["trackId"] as? String
    else { return nil }
    return withState { _loadedTracks.first { $0.id == trackId } }
  }

  private func mapPlayerState(_ state: GCKMediaPlayerState) -> TrackPlayerState {
    switch state {
    case .playing: return .playing
    case .paused: return .paused
    case .buffering, .loading: return .buffering
    case .idle: return .stopped
    default: return .paused
    }
  }

  private func updateNowPlaying(position: Double, duration: Double) {
    let track = withState { _lastCurrentTrackId.flatMap { id in _loadedTracks.first { $0.id == id } } }
    guard let track else { return }
    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = track.title
    info[MPMediaItemPropertyArtist] = track.artist
    info[MPMediaItemPropertyAlbumTitle] = track.album
    if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
    if position.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position }
    info[MPNowPlayingInfoPropertyPlaybackRate] = (remoteClient?.mediaStatus?.playerState == .playing) ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }
  #endif

  @objc private func castStateDidChange() {
    emitCastState()
  }

  /// Refreshes the cache from live Cast state and notifies listeners. Callers must be on the main thread.
  private func emitCastState() {
    refreshCacheOnMain()
    core?.notifyCastStateChangeListeners(currentCastState(), deviceName())
  }

  /// Re-read live Cast state into the cache. MUST be called on the main thread.
  private func refreshCacheOnMain() {
    #if canImport(GoogleCast)
    guard isConfigured else {
      withState {
        cachedState = .noDevicesAvailable
        cachedDeviceName = nil
      }
      return
    }
    let newState: CastState
    switch GCKCastContext.sharedInstance().castState {
    case .noDevicesAvailable: newState = .noDevicesAvailable
    case .notConnected: newState = .notConnected
    case .connecting: newState = .connecting
    case .connected: newState = .connected
    @unknown default: newState = .notConnected
    }
    let name = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.device.friendlyName
    withState {
      cachedState = newState
      cachedDeviceName = name
    }
    #endif
  }
}

#if canImport(GoogleCast)
// MARK: - GCKSessionManagerListener

extension CastSessionManager: GCKSessionManagerListener {
  func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
    handleSessionStarted(session)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
    handleSessionStarted(session)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, willEnd session: GCKSession) {
    (session as? GCKCastSession)?.remoteMediaClient?.remove(self)
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
    stopProgressTimer()
    withState {
      _lastCurrentTrackId = nil
      _loadedTracks = []
      _hasLoadedMedia = false
      _cachedPlaybackState = .stopped
      _lastEmittedPlaybackState = nil
    }
    core?.handleCastDisconnected()
    emitCastState()
  }

  private func handleSessionStarted(_ session: GCKSession) {
    (session as? GCKCastSession)?.remoteMediaClient?.add(self)
    startProgressTimer()
    core?.handleCastConnected()
    emitCastState()
  }
}

// MARK: - GCKRemoteMediaClientListener

extension CastSessionManager: GCKRemoteMediaClientListener {
  func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
    guard let core else { return }

    let hasMedia = mediaStatus?.mediaInformation != nil
    let state = mapPlayerState(mediaStatus?.playerState ?? .unknown)

    // Track change — core state mutations must run on the player queue.
    if let track = currentRemoteTrack(mediaStatus) {
      let previousId: String? = withState {
        let prev = _lastCurrentTrackId
        _lastCurrentTrackId = track.id
        _hasLoadedMedia = hasMedia
        _cachedPlaybackState = state
        return prev
      }
      if previousId != track.id {
        core.playerQueue.async {
          core.emitCastTrackChange(track, previousTrackId: previousId)
        }
      }
    } else {
      withState {
        _hasLoadedMedia = hasMedia
        _cachedPlaybackState = state
      }
    }

    // Playback state — only forward actual changes (status updates are frequent).
    let stateChanged: Bool = withState {
      guard _lastEmittedPlaybackState != state else { return false }
      _lastEmittedPlaybackState = state
      return true
    }
    if stateChanged {
      core.emitCastPlaybackState(state)
    }
  }
}
#endif
