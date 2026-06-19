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

import AVFoundation
import Foundation

extension TrackPlayerCore {

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
      self.isCasting = false

      let resumePosition = self.castManager?.lastKnownRemotePosition ?? 0
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

  /// Mirror the current effective queue to the Cast device, starting at the current track.
  /// Must be called on `playerQueue`.
  func loadCastQueue(autoplay: Bool, position: Double) {
    let queue = getActualQueueInternal()
    guard !queue.isEmpty else { return }
    let current = getCurrentTrack()
    let startIndex = current
      .flatMap { c in queue.firstIndex(where: { $0.id == c.id }) }
      ?? max(0, currentTrackIndex)
    castManager?.loadQueue(tracks: queue, startIndex: startIndex, position: position, autoplay: autoplay)
  }

  // MARK: - Emit (cast-derived events → JS listeners)
  // These bypass getStateInternal()/notify* which read the (paused) local player.

  func emitCastTrackChange(_ track: TrackItem) {
    if let idx = currentTracks.firstIndex(where: { $0.id == track.id }) {
      currentTrackIndex = idx
      currentTemporaryType = .none
    }
    onChangeTrackListeners.forEach { $0(track, .skip) }
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
