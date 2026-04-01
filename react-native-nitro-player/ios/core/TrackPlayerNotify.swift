//
//  TrackPlayerNotify.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//


import Foundation

extension TrackPlayerCore {

  // Called on playerQueue — invoke listeners directly (Nitro handles JS thread hop)
  func notifyTrackChange(_ track: TrackItem, _ reason: Reason?) {
    onChangeTrackListeners.forEach { $0(track, reason) }
    // Capture state + queue now (on playerQueue), pass pre-computed values to main
    let state = getStateInternal()
    let queue = getActualQueueInternal()
    DispatchQueue.main.async { [weak self] in
      self?.mediaSessionManager?.updateFromPlayerQueue(track: track, state: state, queue: queue)
    }
  }

  func notifyPlaybackStateChange(_ state: TrackPlayerState, _ reason: Reason?) {
    onPlaybackStateChangeListeners.forEach { $0(state, reason) }
    let playerState = getStateInternal()
    let queue = getActualQueueInternal()
    let track = getCurrentTrack()
    DispatchQueue.main.async { [weak self] in
      guard let track = track else { return }
      self?.mediaSessionManager?.updateFromPlayerQueue(track: track, state: playerState, queue: queue)
    }
  }

  func notifySeek(_ position: Double, _ duration: Double) {
    onSeekListeners.forEach { $0(position, duration) }
  }

  func notifyPlaybackProgress(_ position: Double, _ duration: Double, _ isManuallySeeked: Bool?) {
    onProgressListeners.forEach { $0(position, duration, isManuallySeeked) }
  }

  func notifyTracksNeedUpdate(tracks: [TrackItem], lookahead: Int) {
    onTracksNeedUpdateListeners.forEach { $0(tracks, lookahead) }
  }

  func notifyTemporaryQueueChange() {
    let pn = playNextStack
    let un = upNextQueue
    onTemporaryQueueChangeListeners.forEach { $0(pn, un) }
  }
}
