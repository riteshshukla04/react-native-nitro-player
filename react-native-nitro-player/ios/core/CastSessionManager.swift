//
//  CastSessionManager.swift
//  NitroPlayer
//
//  Owns the Google Cast session lifecycle and remote media client, and bridges
//  Cast events back into TrackPlayerCore. All GoogleCast usage is guarded by
//  `#if canImport(GoogleCast)` so the library still builds when the SDK is not
//  linked — in that case every method is an inert no-op and casting is disabled.
//

import Foundation
import MediaPlayer

#if canImport(GoogleCast)
import GoogleCast
#endif

final class CastSessionManager: NSObject {
  weak var core: TrackPlayerCore?

  private var isConfigured = false
  private var loadedTracks: [TrackItem] = []
  private var lastCurrentTrackId: String?
  // GoogleCast reads are main-thread-affine; Nitro sync getters run off-main, so
  // serve them from a cache refreshed on the main thread by the Cast callbacks.
  private var cachedState: CastState = .noDevicesAvailable
  private var cachedDeviceName: String?
  /// Last position reported by the receiver, used to resume locally on disconnect.
  private(set) var lastKnownRemotePosition: Double = 0
  private var progressTimer: Timer?

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
      GCKCastContext.setSharedInstanceWith(options)

      let context = GCKCastContext.sharedInstance()
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
    return isConfigured && GCKCastContext.sharedInstance().sessionManager.currentCastSession != nil
    #else
    return false
    #endif
  }

  /// Cached — safe to call from the JS thread.
  func currentCastState() -> CastState { cachedState }

  /// Cached — safe to call from the JS thread.
  func deviceName() -> String? { cachedDeviceName }

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

  func skipToPrevious() {
    #if canImport(GoogleCast)
    onMain { self.remoteClient?.queuePreviousItem() }
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

  func jump(toQueueIndex index: Int) {
    #if canImport(GoogleCast)
    onMain {
      guard let client = self.remoteClient,
            let status = client.mediaStatus,
            index >= 0, index < Int(status.queueItemCount) else { return }
      if let item = status.queueItem(at: UInt(index)) {
        client.queueJumpToItem(withID: item.itemID)
      }
    }
    #endif
  }

  // MARK: - Queue loading

  func loadQueue(tracks: [TrackItem], startIndex: Int, position: Double, autoplay: Bool) {
    #if canImport(GoogleCast)
    onMain {
      guard let client = self.remoteClient, !tracks.isEmpty else { return }
      self.loadedTracks = tracks
      let items = tracks.compactMap { self.makeQueueItem(for: $0, autoplay: autoplay) }
      guard !items.isEmpty else { return }

      let options = GCKMediaQueueLoadOptions()
      options.startIndex = UInt(max(0, min(startIndex, items.count - 1)))
      options.playPosition = position.isFinite ? position : 0
      options.repeatMode = .off
      client.queueLoad(items, with: options)
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
    let urlString = DownloadManagerCore.shared.getEffectiveUrl(track: track)
    guard let contentURL = URL(string: urlString) else { return nil }

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
    if position.isFinite { lastKnownRemotePosition = position }
    core?.emitCastProgress(position.isFinite ? position : 0, safeDuration)
    updateNowPlaying(position: position, duration: safeDuration)
  }

  /// Resolve the track currently playing on the receiver from its custom data.
  private func currentRemoteTrack(_ status: GCKMediaStatus?) -> TrackItem? {
    guard let status else { return nil }
    let item = status.queueItem(withItemID: status.currentItemID)
    let info = item?.mediaInformation ?? status.mediaInformation
    if let customData = info?.customData as? [String: Any],
       let trackId = customData["trackId"] as? String {
      return loadedTracks.first { $0.id == trackId }
    }
    if let url = info?.contentURL?.absoluteString {
      return loadedTracks.first { DownloadManagerCore.shared.getEffectiveUrl(track: $0) == url }
    }
    return nil
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
    guard let track = lastCurrentTrackId.flatMap({ id in loadedTracks.first { $0.id == id } }) else { return }
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
    core?.notifyCastStateChangeListeners(cachedState, cachedDeviceName)
  }

  /// Re-read live Cast state into the cache. MUST be called on the main thread.
  private func refreshCacheOnMain() {
    #if canImport(GoogleCast)
    guard isConfigured else {
      cachedState = .noDevicesAvailable
      cachedDeviceName = nil
      return
    }
    switch GCKCastContext.sharedInstance().castState {
    case .noDevicesAvailable: cachedState = .noDevicesAvailable
    case .notConnected: cachedState = .notConnected
    case .connecting: cachedState = .connecting
    case .connected: cachedState = .connected
    @unknown default: cachedState = .notConnected
    }
    cachedDeviceName = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.device.friendlyName
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
    lastCurrentTrackId = nil
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

    // Track change
    if let track = currentRemoteTrack(mediaStatus), track.id != lastCurrentTrackId {
      lastCurrentTrackId = track.id
      core.emitCastTrackChange(track)
    }

    // Playback state
    let state = mapPlayerState(mediaStatus?.playerState ?? .unknown)
    core.emitCastPlaybackState(state)
  }
}
#endif
