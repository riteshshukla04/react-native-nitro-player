//
//  TrackPlayerQueue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation
import Foundation

extension TrackPlayerCore {

  func getState() async -> PlayerState {
    await withPlayerQueueNoThrow { self.getStateInternal() }
  }

  func getActualQueue() async -> [TrackItem] {
    await withPlayerQueueNoThrow { self.getActualQueueInternal() }
  }

  @discardableResult
  func skipToIndexOnQueue(index: Int) -> Bool {
    isCasting ? skipToIndexCastInternal(index: index) : skipToIndexInternal(index: index)
  }

  func skipToIndex(index: Int) async -> Bool {
    await withPlayerQueueNoThrow { self.skipToIndexOnQueue(index: index) }
  }

  func playFromIndex(index: Int) async {
    await withPlayerQueueNoThrow { self.playFromIndexInternal(index: index) }
  }

  func getCurrentTrackIndex() async -> Int {
    await withPlayerQueueNoThrow { self.currentTrackIndex }
  }

  // MARK: - Internal (run on playerQueue)

  func getStateInternal() -> PlayerState {
    // While casting, report the receiver's cached state — the local AVQueuePlayer is paused/stale.
    if isCasting, let cast = castManager {
      let currentTrack = getCurrentTrack()
      let playingType: CurrentPlayingType
      if currentTrack == nil { playingType = .notPlaying }
      else {
        switch currentTemporaryType {
        case .none: playingType = .playlist
        case .playNext: playingType = .playNext
        case .upNext: playingType = .upNext
        }
      }
      return PlayerState(
        currentTrack: currentTrack.map { Variant_NullType_TrackItem.second($0) },
        currentPosition: cast.lastKnownRemotePosition,
        totalDuration: cast.lastKnownRemoteDuration,
        currentState: cast.cachedPlaybackState,
        currentPlaylistId: currentPlaylistId.map { Variant_NullType_String.second($0) },
        currentIndex: currentTrackIndex >= 0 ? Double(currentTrackIndex) : -1.0,
        currentPlayingType: playingType
      )
    }

    guard let player else {
      return PlayerState(
        currentTrack: nil, currentPosition: 0.0, totalDuration: 0.0,
        currentState: .stopped,
        currentPlaylistId: currentPlaylistId.map { Variant_NullType_String.second($0) },
        currentIndex: -1.0, currentPlayingType: .notPlaying
      )
    }
    let currentTrack = getCurrentTrack()
    let currentPosition = player.currentTime().seconds
    let rawDuration = player.currentItem?.duration.seconds ?? 0.0
    let totalDuration = (rawDuration > 0 && !rawDuration.isNaN && !rawDuration.isInfinite) ? rawDuration : 0.0

    let state: TrackPlayerState
    if player.timeControlStatus == .playing { state = .playing }
    else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate { state = .buffering }
    else if player.rate == 0 { state = .paused }
    else { state = .stopped }

    let currentIndex: Double = currentTrackIndex >= 0 ? Double(currentTrackIndex) : -1.0

    let playingType: CurrentPlayingType
    if currentTrack == nil { playingType = .notPlaying }
    else {
      switch currentTemporaryType {
      case .none: playingType = .playlist
      case .playNext: playingType = .playNext
      case .upNext: playingType = .upNext
      }
    }

    return PlayerState(
      currentTrack: currentTrack.map { Variant_NullType_TrackItem.second($0) },
      currentPosition: currentPosition,
      totalDuration: totalDuration,
      currentState: state,
      currentPlaylistId: currentPlaylistId.map { Variant_NullType_String.second($0) },
      currentIndex: currentIndex,
      currentPlayingType: playingType
    )
  }

  func getActualQueueInternal() -> [TrackItem] {
    var queue: [TrackItem] = []
    queue.reserveCapacity(currentTracks.count + playNextStack.count + upNextQueue.count)

    // Add tracks before current (original playlist)
    // When a temp track is playing, include the original track at currentTrackIndex
    let beforeEnd = currentTemporaryType != .none
      ? min(currentTrackIndex + 1, currentTracks.count) : currentTrackIndex
    if beforeEnd > 0 { queue.append(contentsOf: currentTracks[0..<beforeEnd]) }

    // Add current track (temp or original)
    if let current = getCurrentTrack() { queue.append(current) }

    // Add playNext stack — skip the currently playing track by ID (already added as current)
    let currentId = activeCurrentTrackId
    if currentTemporaryType == .playNext, let currentId = currentId {
      var skipped = false
      for track in playNextStack {
        if !skipped && track.id == currentId { skipped = true; continue }
        queue.append(track)
      }
    } else if currentTemporaryType != .playNext {
      queue.append(contentsOf: playNextStack)
    }

    // Add upNext queue — skip the currently playing track by ID (already added as current)
    if currentTemporaryType == .upNext, let currentId = currentId {
      var skipped = false
      for track in upNextQueue {
        if !skipped && track.id == currentId { skipped = true; continue }
        queue.append(track)
      }
    } else if currentTemporaryType != .upNext {
      queue.append(contentsOf: upNextQueue)
    }

    // Add remaining original tracks
    if currentTrackIndex + 1 < currentTracks.count {
      queue.append(contentsOf: currentTracks[(currentTrackIndex + 1)...])
    }
    return queue
  }

  /// Length of the logical queue and the current track's position in it, derived
  /// arithmetically. `getActualQueueInternal()` copies every TrackItem to answer the
  /// same two questions — too expensive to run on every playback-state change.
  func actualQueueMetrics() -> (count: Int, position: Int) {
    let before: Int
    if currentTemporaryType != .none {
      before = min(currentTrackIndex + 1, currentTracks.count)
    } else {
      before = max(0, currentTrackIndex)
    }
    let hasCurrent = getCurrentTrack() != nil
    let playNextCount =
      currentTemporaryType == .playNext ? max(0, playNextStack.count - 1) : playNextStack.count
    let upNextCount =
      currentTemporaryType == .upNext ? max(0, upNextQueue.count - 1) : upNextQueue.count
    let after =
      currentTrackIndex + 1 < currentTracks.count ? currentTracks.count - (currentTrackIndex + 1) : 0

    let count = before + (hasCurrent ? 1 : 0) + playNextCount + upNextCount + after
    return (count, hasCurrent ? before : -1)
  }

  func getCurrentTrack() -> TrackItem? {
    if currentTemporaryType != .none, let trackId = activeCurrentTrackId {
      if currentTemporaryType == .playNext { return playNextStack.first(where: { $0.id == trackId }) }
      if currentTemporaryType == .upNext { return upNextQueue.first(where: { $0.id == trackId }) }
    }
    guard currentTrackIndex >= 0 && currentTrackIndex < currentTracks.count else { return nil }
    return currentTracks[currentTrackIndex]
  }

  @discardableResult
  func skipToIndexInternal(index: Int) -> Bool {
    let actualQueue = getActualQueueInternal()
    guard index >= 0 && index < actualQueue.count else { return false }

    // Calculate queue section boundaries using effective sizes
    // (reduced by 1 when current track is from that temp list)
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
      _ = rebuildQueueFromPlaylistIndex(index: index)
      return true
    }

    // Case 2: Target is current - seek to beginning
    if index == currentPos {
      player?.seek(to: .zero)
      return true
    }

    // Case 3: Target is in playNext section
    if index >= playNextStart && index < playNextEnd {
      let targetTrack = actualQueue[index]
      // Remove all playNext tracks before the target (by ID lookup, not position)
      if let targetIdx = playNextStack.firstIndex(where: { $0.id == targetTrack.id }), targetIdx > 0 {
        // Remove tracks before target, but keep the currently playing track
        // (rebuildAVQueueFromCurrentPosition will skip it by ID)
        playNextStack.removeSubrange(0..<targetIdx)
      }
      if let player = player, currentRepeatMode == .track {
        dropRepeatCopyBeforeManualSkip(player)
      } else {
        rebuildAVQueueFromCurrentPosition()
      }
      player?.advanceToNextItem()
      return true
    }

    // Case 4: Target is in upNext section
    if index >= upNextStart && index < upNextEnd {
      let targetTrack = actualQueue[index]
      playNextStack.removeAll()
      // Remove all upNext tracks before the target (by ID lookup, not position)
      if let targetIdx = upNextQueue.firstIndex(where: { $0.id == targetTrack.id }), targetIdx > 0 {
        upNextQueue.removeSubrange(0..<targetIdx)
      }
      if let player = player, currentRepeatMode == .track {
        dropRepeatCopyBeforeManualSkip(player)
      } else {
        rebuildAVQueueFromCurrentPosition()
      }
      player?.advanceToNextItem()
      return true
    }

    // Case 5: Target is in remaining original tracks
    if index >= originalRemainingStart {
      let targetTrack = actualQueue[index]
      guard let originalIndex = currentTracks.firstIndex(where: { $0.id == targetTrack.id }) else { return false }

      playNextStack.removeAll()
      upNextQueue.removeAll()
      currentTemporaryType = .none

      let result = rebuildQueueFromPlaylistIndex(index: originalIndex)
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      return result
    }

    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
    return false
  }

  func playFromIndexInternal(index: Int) {
    playNextStack.removeAll()
    upNextQueue.removeAll()
    currentTemporaryType = .none
    _ = rebuildQueueFromPlaylistIndex(index: index)
  }

  func determineCurrentTemporaryType() -> TemporaryType {
    guard let trackId = activeCurrentTrackId else { return .none }
    if playNextStack.contains(where: { $0.id == trackId }) { return .playNext }
    if upNextQueue.contains(where: { $0.id == trackId }) { return .upNext }
    return .none
  }
}
