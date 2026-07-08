//
//  TrackPlayerCast.swift
//  NitroPlayer
//
//  Google Cast backend integration for TrackPlayerCore.
//
//  Casting is modelled as routing: while `isCasting` is true, the public
//  playback methods forward to the CastSessionManager (remote device) instead of
//  the local AVQueuePlayer, the local player is paused, and the queue is mirrored
//  to the receiver. The same queue model (currentTracks / temp queues) stays the
//  single source of truth, so disconnect can restore local playback seamlessly.
//
//  Receivers auto-skip failed loads (AVPlayer waits), so only receiver-loadable tracks are ever enqueued remotely.
//

import AVFoundation
import Foundation

extension TrackPlayerCore {

  // MARK: - Cast-safety helpers

  /// A track the Cast receiver can actually load: non-empty remote (non-local) URL.
  func isTrackCastable(_ track: TrackItem) -> Bool {
    !track.url.isEmpty && !track.url.hasPrefix("/") && !track.url.hasPrefix("file:")
  }

  /// Receiver-safe run: keeps castable tracks, skips local-only ones, stops at the first lazy (empty-URL) track whose resolution is pending.
  func castableUpcoming(_ tracks: [TrackItem]) -> [TrackItem] {
    var result: [TrackItem] = []
    for track in tracks {
      if isTrackCastable(track) {
        result.append(track)
      } else if track.url.isEmpty {
        break
      }
      // local-only → skip and keep scanning
    }
    return result
  }

  /// Track ID playing on the ACTIVE backend — receiver while casting, local AVQueuePlayer otherwise.
  var activeCurrentTrackId: String? {
    isCasting ? castManager?.currentRemoteTrackId : player?.currentItem?.trackId
  }

  // MARK: - Session lifecycle (called by CastSessionManager)

  /// A Cast session became active — transfer current playback to the device.
  func handleCastConnected() {
    playerQueue.async { [weak self] in
      guard let self else { return }
      let wasPlaying = (self.player?.rate ?? 0) > 0 || self.intendedToPlay
      let rawPosition = self.player?.currentTime().seconds ?? 0
      let position = rawPosition.isFinite ? rawPosition : 0

      self.isCasting = true
      self.player?.pause() // silence local output — audio now comes from the device

      self.loadCastQueue(autoplay: wasPlaying, position: position)
    }
  }

  /// The Cast session ended — rebuild local playback at the last remote position.
  func handleCastDisconnected() {
    playerQueue.async { [weak self] in
      guard let self else { return }
      guard self.isCasting else { return }
      let resumePosition = self.castManager?.lastKnownRemotePosition ?? 0
      self.isCasting = false

      let index = self.currentTrackIndex
      guard index >= 0 && index < self.currentTracks.count else { return }

      _ = self.rebuildQueueFromPlaylistIndex(index: index)
      if resumePosition.isFinite && resumePosition > 0 {
        let time = CMTime(seconds: resumePosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        self.player?.seek(to: time)
      }
      if self.intendedToPlay {
        self.player?.rate = Float(self.currentPlaybackSpeed)
      }
    }
  }

  // MARK: - Receiver queue loading (all on playerQueue)

  /// Load the receiver queue starting at the current track.
  func loadCastQueue(autoplay: Bool, position: Double) {
    let queue = getActualQueueInternal()
    guard !queue.isEmpty else { return }
    let current = getCurrentTrack()
    let startIndex = current
      .flatMap { c in queue.firstIndex(where: { $0.id == c.id }) }
      ?? max(0, min(currentTrackIndex, queue.count - 1))
    loadCastQueue(fromActualIndex: startIndex, autoplay: autoplay, position: position)
  }

  /// Atomically (re)load the receiver queue from `index` in the actual queue (lazy targets stop the receiver and wait for updateTracks).
  func loadCastQueue(fromActualIndex index: Int, autoplay: Bool, position: Double) {
    let queue = getActualQueueInternal()
    guard index >= 0, index < queue.count else { return }
    let slice = Array(queue[index...])
    let playable = castableUpcoming(slice)

    guard !playable.isEmpty else {
      // Lazy target — silence the receiver and wait for updateTracks to reload.
      castManager?.stop()
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      return
    }

    // Resume mid-track only when the receiver starts on the requested track.
    let effectivePosition = playable[0].id == slice[0].id ? position : 0

    castManager?.setExpectedCurrentTrack(playable[0].id)
    castManager?.loadQueue(
      tracks: playable,
      position: effectivePosition,
      autoplay: autoplay,
      repeatMode: currentRepeatMode
    )
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  /// Sync the receiver's upcoming items: append-only extensions don't interrupt playback; anything else reloads at the current position.
  func syncCastQueueAfterCurrent() {
    guard let cast = castManager else { return }
    guard cast.hasLoadedMedia else {
      // Nothing loaded remotely (e.g. the target was lazy) — full load from current.
      loadCastQueue(autoplay: intendedToPlay, position: 0)
      return
    }

    let queue = getActualQueueInternal()
    guard let current = getCurrentTrack(),
      let currentIdx = queue.firstIndex(where: { $0.id == current.id })
    else { return }

    let desired = castableUpcoming(Array(queue[(currentIdx + 1)...]))
    let desiredIds = desired.map { $0.id }

    let loaded = cast.loadedTrackIds
    let existingUpcoming: [String]
    if let ei = loaded.firstIndex(of: current.id) {
      existingUpcoming = Array(loaded[(ei + 1)...])
    } else {
      existingUpcoming = []
    }

    if desiredIds == existingUpcoming { return } // already in sync

    if desiredIds.count > existingUpcoming.count,
      Array(desiredIds.prefix(existingUpcoming.count)) == existingUpcoming {
      // Strict tail extension — append without touching current playback.
      let toAppend = Array(desired.suffix(desiredIds.count - existingUpcoming.count))
      castManager?.appendToQueue(tracks: toAppend)
    } else {
      // Order changed / items removed — atomic reload preserving position.
      loadCastQueue(
        fromActualIndex: currentIdx,
        autoplay: intendedToPlay,
        position: cast.lastKnownRemotePosition
      )
    }
  }

  // MARK: - Cast-mode navigation (mirrors the local skip logic, minus AVQueuePlayer)

  /// skipToIndex while casting: apply the local path's list/index mutations, then reload the receiver at the target.
  func skipToIndexCastInternal(index: Int) -> Bool {
    let actualQueue = getActualQueueInternal()
    guard index >= 0 && index < actualQueue.count else { return false }

    // Same section boundaries as the local skipToIndexInternal.
    let currentPos = currentTemporaryType != .none ? currentTrackIndex + 1 : currentTrackIndex
    let effectivePlayNextSize = currentTemporaryType == .playNext
      ? max(0, playNextStack.count - 1) : playNextStack.count
    let effectiveUpNextSize = currentTemporaryType == .upNext
      ? max(0, upNextQueue.count - 1) : upNextQueue.count
    let playNextStart = currentPos + 1
    let playNextEnd = playNextStart + effectivePlayNextSize
    let upNextEnd = playNextEnd + effectiveUpNextSize

    if index == currentPos {
      castManager?.seek(to: 0)
      return true
    }

    let target = actualQueue[index]

    // Skipping away from a playing temp track removes it from its list (mirrors the local handler).
    if currentTemporaryType != .none, let currentId = activeCurrentTrackId {
      if currentTemporaryType == .playNext,
        let i = playNextStack.firstIndex(where: { $0.id == currentId }) {
        playNextStack.remove(at: i)
      } else if currentTemporaryType == .upNext,
        let i = upNextQueue.firstIndex(where: { $0.id == currentId }) {
        upNextQueue.remove(at: i)
      }
    }

    if index < currentPos || index >= upNextEnd {
      // Original-playlist target — temps are cleared, same as the local path.
      guard let originalIndex = currentTracks.firstIndex(where: { $0.id == target.id }) else { return false }
      playNextStack.removeAll()
      upNextQueue.removeAll()
      currentTemporaryType = .none
      currentTrackIndex = originalIndex
    } else if index < playNextEnd {
      // playNext section: everything before the target is dropped.
      if let t = playNextStack.firstIndex(where: { $0.id == target.id }), t > 0 {
        playNextStack.removeSubrange(0..<t)
      }
      currentTemporaryType = .playNext
    } else {
      // upNext section: playNext is consumed, earlier upNext entries dropped.
      playNextStack.removeAll()
      if let t = upNextQueue.firstIndex(where: { $0.id == target.id }), t > 0 {
        upNextQueue.removeSubrange(0..<t)
      }
      currentTemporaryType = .upNext
    }

    castManager?.setExpectedCurrentTrack(target.id)
    notifyTemporaryQueueChange()
    onChangeTrackListeners.forEach { $0(target, .skip) }

    // Reload the receiver from the target's position in the refreshed queue.
    let newQueue = getActualQueueInternal()
    let newIndex = newQueue.firstIndex(where: { $0.id == target.id }) ?? 0
    loadCastQueue(fromActualIndex: newIndex, autoplay: intendedToPlay, position: 0)
    return true
  }

  /// skipToPrevious while casting: restart after the threshold, otherwise step back through temp/original tracks.
  func skipToPreviousCastInternal() {
    let position = castManager?.lastKnownRemotePosition ?? 0
    if position > Constants.skipToPreviousThreshold {
      castManager?.seek(to: 0)
      return
    }

    if currentTemporaryType != .none {
      // Leaving a temp track removes it, then return to the current original.
      if let currentId = activeCurrentTrackId {
        if currentTemporaryType == .playNext,
          let i = playNextStack.firstIndex(where: { $0.id == currentId }) {
          playNextStack.remove(at: i)
        } else if currentTemporaryType == .upNext,
          let i = upNextQueue.firstIndex(where: { $0.id == currentId }) {
          upNextQueue.remove(at: i)
        }
      }
      currentTemporaryType = .none
      notifyTemporaryQueueChange()
    } else if currentTrackIndex > 0 {
      currentTrackIndex -= 1
    } else {
      castManager?.seek(to: 0)
      return
    }

    guard let target = currentTracks[safe: currentTrackIndex] else { return }
    castManager?.setExpectedCurrentTrack(target.id)
    onChangeTrackListeners.forEach { $0(target, .skip) }
    loadCastQueue(autoplay: intendedToPlay, position: 0)
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  // MARK: - Emit (cast-derived events → JS listeners; run on playerQueue)

  /// Track change from the receiver: temp-list bookkeeping, index/type classification, and the JS event.
  func emitCastTrackChange(_ track: TrackItem, previousTrackId: String? = nil) {
    // Leaving a temp track removes it from its list (mirrors the local handler).
    if let prev = previousTrackId, prev != track.id {
      if let i = playNextStack.firstIndex(where: { $0.id == prev }) {
        playNextStack.remove(at: i)
        notifyTemporaryQueueChange()
      } else if let i = upNextQueue.firstIndex(where: { $0.id == prev }) {
        upNextQueue.remove(at: i)
        notifyTemporaryQueueChange()
      }
    }

    // Classify the new current track — temp lists take priority (matches determineCurrentTemporaryType).
    if playNextStack.contains(where: { $0.id == track.id }) {
      currentTemporaryType = .playNext
    } else if upNextQueue.contains(where: { $0.id == track.id }) {
      currentTemporaryType = .upNext
    } else {
      currentTemporaryType = .none
      if let idx = currentTracks.firstIndex(where: { $0.id == track.id }) {
        currentTrackIndex = idx
      }
    }

    onChangeTrackListeners.forEach { $0(track, .skip) }
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  func emitCastPlaybackState(_ state: TrackPlayerState) {
    onPlaybackStateChangeListeners.forEach { $0(state, nil) }
  }

  func emitCastProgress(_ position: Double, _ duration: Double) {
    onProgressListeners.forEach { $0(position, duration, nil) }
  }

  func notifyCastStateChangeListeners(_ state: CastState, _ deviceName: String?) {
    onCastStateChangeListeners.forEach { $0(state, deviceName) }
  }

  // MARK: - Accessors (used by HybridCast)

  func castConfigure(receiverApplicationId: String?) {
    castManager?.configure(receiverApplicationId: receiverApplicationId)
  }

  func castGetState() -> CastState {
    if isCasting { return .connected }
    return castManager?.currentCastState() ?? .noDevicesAvailable
  }

  func castGetDeviceName() -> String? { castManager?.deviceName() }

  func castShowPicker() { castManager?.showCastPicker() }

  func castEndSession() { castManager?.endSession() }
}
