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

/// Receiver state captured before the Cast session tears its caches down.
struct CastTransferSnapshot {
  let trackId: String?
  let position: Double
}

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
  func handleCastDisconnected(_ snapshot: CastTransferSnapshot) {
    playerQueue.async { [weak self] in
      guard let self else { return }
      guard self.isCasting else { return }
      let resumePosition = snapshot.position
      let remoteTrackId = snapshot.trackId
      self.isCasting = false

      // A backend transfer is not a track change.
      self.backendTransferTargetId = remoteTrackId
      let hadAnchor = self.currentTrackIndex >= 0
      let index = max(0, self.currentTrackIndex)

      // rebuildQueueFromPlaylistIndex wipes the temp lists — preserve them
      let savedPlayNext = self.playNextStack
      let savedUpNext = self.upNextQueue
      let remoteTemp = remoteTrackId.flatMap { id in
        savedPlayNext.first { $0.id == id } ?? savedUpNext.first { $0.id == id }
      }

      if self.currentTracks.isEmpty {
        // Playlist emptied while casting: bootstrap the local player from the remote temp.
        guard let player = self.player, let temp = remoteTemp,
          let item = self.createGaplessPlayerItem(for: temp, isPreload: false)
        else {
          self.backendTransferTargetId = nil
          return
        }
        self.removeAllItemsCancellingLoads(player)
        player.insert(item, after: nil)
        self.currentTemporaryType = savedPlayNext.contains { $0.id == temp.id } ? .playNext : .upNext
        self.currentTrackIndex = -1
        self.rebuildAVQueueFromCurrentPosition()
        self.notifyTemporaryQueueChange()
      } else {
        guard self.rebuildQueueFromPlaylistIndex(index: index, emitChange: false) else {
          self.backendTransferTargetId = nil
          return
        }
        if !savedPlayNext.isEmpty || !savedUpNext.isEmpty {
          self.playNextStack = savedPlayNext
          self.upNextQueue = savedUpNext
          self.rebuildAVQueueFromCurrentPosition()
          self.notifyTemporaryQueueChange()
        }

        // The temp stays in its list; the builder skips the current id and transitions drop it.
        if let target = remoteTrackId, target != self.player?.currentItem?.trackId {
          if self.playNextStack.first?.id == target {
            self.player?.advanceToNextItem()
            self.currentTemporaryType = .playNext
          } else if self.playNextStack.isEmpty, self.upNextQueue.first?.id == target {
            self.player?.advanceToNextItem()
            self.currentTemporaryType = .upNext
          }
          // The advance consumed track 0; re-queue it after the temps.
          if !hadAnchor, self.currentTemporaryType != .none {
            self.currentTrackIndex = -1
            self.rebuildAVQueueFromCurrentPosition()
          }
        }
      }

      // Only seek when the local current track is the one that was playing remotely
      if resumePosition.isFinite && resumePosition > 0,
        remoteTrackId != nil, self.player?.currentItem?.trackId == remoteTrackId {
        let time = CMTime(seconds: resumePosition, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        self.player?.seek(to: time)
      }
      if self.intendedToPlay {
        self.player?.rate = Float(self.currentPlaybackSpeed)
      }
      if self.player?.currentItem?.trackId == remoteTrackId { self.backendTransferTargetId = nil }
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

  /// The whole castable queue, so a shuffle can reorder items before the current one. Nil when the current is lazy.
  func castableQueue(_ actual: [TrackItem], currentIdx: Int) -> (tracks: [TrackItem], startIndex: Int)? {
    guard currentIdx >= 0, currentIdx < actual.count else { return nil }
    let after = castableUpcoming(Array(actual[currentIdx...]))
    guard !after.isEmpty else { return nil }
    let before = actual[..<currentIdx].filter { isTrackCastable($0) }
    return (before + after, before.count)
  }

  /// A removed track finishing is no longer in the logical queue, so the receiver's own current anchors it.
  func castDesiredQueue() -> (tracks: [TrackItem], currentId: String)? {
    guard let currentId = activeCurrentTrackId else { return nil }
    let actual = getActualQueueInternal()
    if let idx = actual.firstIndex(where: { $0.id == currentId }) {
      guard let built = castableQueue(actual, currentIdx: idx) else { return nil }
      return (built.tracks, currentId)
    }
    guard let remoteCurrent = castManager?.currentRemoteTrackItem else { return nil }
    castManager?.setQueueRepeatMode(.off)
    let rest = currentTrackIndex + 1 < currentTracks.count
      ? Array(currentTracks[(currentTrackIndex + 1)...]) : []
    return ([remoteCurrent] + castableUpcoming(playNextStack + upNextQueue + rest), remoteCurrent.id)
  }

  /// Atomically (re)load the receiver queue positioned at `index` in the actual queue (lazy targets stop the receiver and wait for updateTracks).
  func loadCastQueue(fromActualIndex index: Int, autoplay: Bool, position: Double) {
    let queue = getActualQueueInternal()
    guard index >= 0, index < queue.count else { return }

    guard let built = castableQueue(queue, currentIdx: index) else {
      // Lazy target — silence the receiver and wait for updateTracks to reload.
      castManager?.stop()
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      return
    }

    // Resume mid-track only when the receiver starts on the requested track.
    let startTrack = built.tracks[built.startIndex]
    let effectivePosition = startTrack.id == queue[index].id ? position : 0

    castManager?.setExpectedCurrentTrack(startTrack.id)
    castManager?.loadQueue(
      tracks: built.tracks,
      startIndex: built.startIndex,
      position: effectivePosition,
      autoplay: autoplay,
      repeatMode: isTransientPlayOut() ? .off : currentRepeatMode
    )
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  /// Current-preserving operations; the reconciler reloads only when receiver state is untrusted.
  func syncCastQueueAfterCurrent() {
    guard let cast = castManager else { return }
    guard cast.hasLoadedMedia else {
      // Nothing loaded remotely (e.g. the target was lazy) — full load from current.
      loadCastQueue(autoplay: intendedToPlay, position: 0)
      return
    }
    guard let desired = castDesiredQueue() else { return }
    cast.reconcileQueue(desired: desired.tracks, currentTrackId: desired.currentId)
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
      // No playlist track to return to: restart the temp without touching its list.
      if currentTracks.isEmpty {
        castManager?.seek(to: 0)
        return
      }
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
      // Cursor may be -1 (anchor removed): return to the resume slot.
      currentTrackIndex = max(0, currentTrackIndex)
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
