//
//  TrackPlayerPlayback.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import AVFoundation
import Foundation
import MediaPlayer

extension TrackPlayerCore {

  // MARK: - Public commands
  //
  // Each command has a `…OnQueue` form that MUST run on `playerQueue` and an `async`
  // shim for callers that are not already there (media-session remote commands).
  // HybridTrackPlayer dispatches the `…OnQueue` form directly from the JS thread so
  // the serial queue's FIFO order equals the JS call order — see HybridTrackPlayer.
  //
  // Reading `isCasting` inside the queue block (not before it) keeps every cast-vs-local
  // decision on the thread that owns that flag.

  func playOnQueue() {
    if isCasting {
      intendedToPlay = true
      castManager?.play()
      return
    }
    playInternal()
  }
  func play() async { await withPlayerQueueNoThrow { self.playOnQueue() } }

  func pauseOnQueue() {
    if isCasting {
      intendedToPlay = false
      castManager?.pause()
      return
    }
    pauseInternal()
  }
  func pause() async { await withPlayerQueueNoThrow { self.pauseOnQueue() } }

  func seekOnQueue(position: Double) {
    if isCasting {
      castManager?.seek(to: position)
      return
    }
    seekInternal(position: position)
  }
  func seek(position: Double) async {
    await withPlayerQueueNoThrow { self.seekOnQueue(position: position) }
  }

  func skipToNextOnQueue() {
    if isCasting {
      castManager?.skipToNext()
      return
    }
    skipToNextInternal()
  }
  func skipToNext() async { await withPlayerQueueNoThrow { self.skipToNextOnQueue() } }

  func skipToPreviousOnQueue() {
    if isCasting {
      // The receiver queue starts at the current track, so queuePreviousItem has nothing behind it — use core state instead.
      skipToPreviousCastInternal()
      return
    }
    skipToPreviousInternal()
  }
  func skipToPrevious() async { await withPlayerQueueNoThrow { self.skipToPreviousOnQueue() } }

  func setRepeatModeOnQueue(mode: RepeatMode) {
    let previousMode = currentRepeatMode
    currentRepeatMode = mode
    player?.actionAtItemEnd = .advance
    if isCasting { castManager?.setQueueRepeatMode(mode) }
    if !isCasting, previousMode != mode, player?.currentItem != nil {
      rebuildAVQueueFromCurrentPosition()
    }
    NitroPlayerLogger.log("TrackPlayerCore", "🔁 setRepeatMode: \(mode)")
  }
  func setRepeatMode(mode: RepeatMode) async {
    await withPlayerQueueNoThrow { self.setRepeatModeOnQueue(mode: mode) }
  }

  func setVolumeOnQueue(volume: Double) {
    let clamped = max(0.0, min(100.0, volume))
    if isCasting {
      castManager?.setVolume(Float(clamped / 100.0))
      return
    }
    let normalized = Float(clamped / 100.0)
    player?.volume = normalized
    NitroPlayerLogger.log(
      "TrackPlayerCore", "🔊 Volume set to \(Int(clamped))% (normalized: \(normalized))")
  }
  func setVolume(volume: Double) async {
    await withPlayerQueueNoThrow { self.setVolumeOnQueue(volume: volume) }
  }

  func configureOnQueue(
    androidAutoEnabled: Bool?, carPlayEnabled: Bool?,
    showInNotification: Bool?, lookaheadCount: Int?,
    remoteSkipForwardInterval: Double?, remoteSkipBackwardInterval: Double?
  ) {
    if let la = lookaheadCount {
      self.lookaheadCount = la
      NitroPlayerLogger.log("TrackPlayerCore", "🔄 Lookahead count set to: \(la)")
    }
    let playbackSpeed = currentPlaybackSpeed
    DispatchQueue.main.async { [weak self] in
      self?.mediaSessionManager?.configure(
        androidAutoEnabled: androidAutoEnabled,
        carPlayEnabled: carPlayEnabled,
        showInNotification: showInNotification,
        remoteSkipForwardInterval: remoteSkipForwardInterval,
        remoteSkipBackwardInterval: remoteSkipBackwardInterval,
        playbackSpeed: playbackSpeed
      )
    }
  }
  func configure(
    androidAutoEnabled: Bool?, carPlayEnabled: Bool?,
    showInNotification: Bool?, lookaheadCount: Int?,
    remoteSkipForwardInterval: Double?, remoteSkipBackwardInterval: Double?
  ) async {
    await withPlayerQueueNoThrow {
      self.configureOnQueue(
        androidAutoEnabled: androidAutoEnabled, carPlayEnabled: carPlayEnabled,
        showInNotification: showInNotification, lookaheadCount: lookaheadCount,
        remoteSkipForwardInterval: remoteSkipForwardInterval,
        remoteSkipBackwardInterval: remoteSkipBackwardInterval)
    }
  }

  func setPlaybackSpeedOnQueue(_ speed: Double) throws {
    guard speed.isFinite, speed > 0 else {
      throw NSError(
        domain: "NitroPlayer",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Speed must be finite and greater than 0"]
      )
    }
    currentPlaybackSpeed = speed
    defer { refreshMediaSession() }
    if isCasting {
      castManager?.setPlaybackRate(Float(speed))
      return
    }
    // Only update rate if currently playing; pause keeps rate at 0 until play() is called
    if let player = self.player, player.rate != 0 {
      player.rate = Float(speed)
    }
  }
  func setPlaybackSpeed(_ speed: Double) async throws {
    try await withPlayerQueue { try self.setPlaybackSpeedOnQueue(speed) }
  }

  func seekByOnQueue(offset: Double) {
    if isCasting {
      let position = castManager?.lastKnownRemotePosition ?? 0
      let duration = castManager?.lastKnownRemoteDuration ?? 0
      var target = max(0, position + offset)
      if duration > 0, duration.isFinite { target = min(target, duration) }
      castManager?.seek(to: target)
      return
    }
    guard let player = self.player else { return }
    let position = player.currentTime().seconds
    guard position.isFinite else { return }
    var target = max(0, position + offset)
    if let duration = player.currentItem?.duration.seconds, duration > 0, duration.isFinite {
      target = min(target, duration)
    }
    seekInternal(position: target)
  }
  func seekBy(offset: Double) async {
    await withPlayerQueueNoThrow { self.seekByOnQueue(offset: offset) }
  }

  func getPlaybackSpeed() async -> Double {
    await withPlayerQueueNoThrow { self.currentPlaybackSpeed }
  }

  func playSong(songId: String, fromPlaylist: String?) async {
    await withPlayerQueueNoThrow { self.playSongInternal(songId: songId, fromPlaylist: fromPlaylist) }
  }

  // MARK: - Internal (run on playerQueue)

  func playInternal() {
    NitroPlayerLogger.log("TrackPlayerCore", "▶️ play() called")
    activateAudioSessionIfNeeded()
    self.intendedToPlay = true
    // An explicit play() is the ground truth for intent — clear any stale
    // interruption flag so a missed AVAudioSession `.ended` can't permanently
    // wedge recovery off.
    self.isInterrupted = false
    if let player = self.player {
      NitroPlayerLogger.log("TrackPlayerCore", "▶️ Player status: \(player.status.rawValue)")
      if let currentItem = player.currentItem {
        NitroPlayerLogger.log("TrackPlayerCore", "▶️ Current item status: \(currentItem.status.rawValue)")
        if let error = currentItem.error {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Current item error: \(error.localizedDescription)")
        }
      }
      player.rate = Float(currentPlaybackSpeed)
      playerQueue.asyncAfter(deadline: .now() + Constants.stateChangeDelay) { [weak self] in
        self?.emitStateChange()
      }
    } else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ No player available")
    }
  }

  func pauseInternal() {
    NitroPlayerLogger.log("TrackPlayerCore", "⏸️ pause() called")
    // User-initiated pause — cancel any pending stall auto-resume.
    self.intendedToPlay = false
    self.isRecoveringFromStall = false
    self.player?.pause()
    playerQueue.asyncAfter(deadline: .now() + Constants.stateChangeDelay) { [weak self] in
      self?.emitStateChange()
    }
  }

  func seekInternal(position: Double) {
    guard let player = self.player else { return }
    self.isManuallySeeked = true
    let time = CMTime(seconds: position, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    player.seek(to: time) { _ in
       // HackFix I dont know how to fix this, but it works.
      let rate = Double(player.rate)
      DispatchQueue.main.async {
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
          info[MPNowPlayingInfoPropertyPlaybackRate] = rate
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
      // No notifySeek here — the same seek fires AVPlayerItemTimeJumped,
      // whose handler already emits it; calling both doubled every onSeek.
    }
  }

  func skipToNextInternal() {
    guard let queuePlayer = self.player else { return }

    // Lazy-load: AVQueuePlayer is empty because updatePlayerQueue deferred population.
    if queuePlayer.items().isEmpty && !currentTracks.isEmpty {
      let nextIndex = currentTrackIndex + 1
      if nextIndex < currentTracks.count {
        _ = skipToIndexInternal(index: nextIndex)
      }
      checkUpcomingTracksForUrls(lookahead: lookaheadCount)
      return
    }

    if currentRepeatMode == .track {
      let items = queuePlayer.items()
      if items.count > 1, let copyId = items[1].trackId, copyId == items[0].trackId {
        queuePlayer.remove(items[1])
      }
      rebuildAVQueueFromCurrentPosition(skipRepeatCopy: true)
    }

    // Remove current temp track from its list before advancing
    if let trackId = queuePlayer.currentItem?.trackId {
      if currentTemporaryType == .playNext {
        if let idx = playNextStack.firstIndex(where: { $0.id == trackId }) {
          playNextStack.remove(at: idx)
          notifyTemporaryQueueChange()
        }
      } else if currentTemporaryType == .upNext {
        if let idx = upNextQueue.firstIndex(where: { $0.id == trackId }) {
          upNextQueue.remove(at: idx)
          notifyTemporaryQueueChange()
        }
      }
    }

    // The AVQueuePlayer is windowed, so items().count is not the logical queue length.
    // Top up first so there is always something to advance to while tracks remain.
    if hasUpcomingTrack() {
      if queuePlayer.items().count <= 1 { rebuildAVQueueFromCurrentPosition() }
    }

    if queuePlayer.items().count > 1 {
      queuePlayer.advanceToNextItem()
    } else if currentRepeatMode == .playlist, !currentTracks.isEmpty {
      // Manual skip at the last track wraps, matching natural-end behavior
      _ = skipToIndexInternal(index: 0)
    } else {
      // No next track — no-op and keep playing, matching Android
      NitroPlayerLogger.log("TrackPlayerCore", "⏭️ skipToNext at last track — nothing to advance to")
    }

    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  func skipToPreviousInternal() {
    guard let queuePlayer = self.player else { return }

    let currentTime = queuePlayer.currentTime()
    if currentTime.seconds > Constants.skipToPreviousThreshold {
      // If more than threshold seconds in, restart current track
      queuePlayer.seek(to: .zero)
    } else if self.currentTemporaryType != .none {
      // Playing temporary track — remove from its list, then go back to original track
      if let trackId = queuePlayer.currentItem?.trackId {
        if currentTemporaryType == .playNext, let idx = playNextStack.firstIndex(where: { $0.id == trackId }) {
          playNextStack.remove(at: idx)
          notifyTemporaryQueueChange()
        } else if currentTemporaryType == .upNext, let idx = upNextQueue.firstIndex(where: { $0.id == trackId }) {
          upNextQueue.remove(at: idx)
          notifyTemporaryQueueChange()
        }
      }
      // Go back to current original track position (skip back from temp)
      _ = rebuildQueueFromPlaylistIndex(index: self.currentTrackIndex)
    } else if self.currentTrackIndex > 0 {
      // Go to previous track in original playlist
      _ = rebuildQueueFromPlaylistIndex(index: self.currentTrackIndex - 1)
    } else {
      // Already at first track, restart it
      queuePlayer.seek(to: .zero)
    }

    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
  }

  func playSongInternal(songId: String, fromPlaylist: String?) {
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

      if let currentId = self.currentPlaylistId,
        let currentPlaylist = self.playlistManager.getPlaylist(playlistId: currentId)
      {
        if let index = currentPlaylist.tracks.firstIndex(where: { $0.id == songId }) {
          targetPlaylistId = currentId
          songIndex = index
          NitroPlayerLogger.log("TrackPlayerCore", "✅ Found song at index \(index) in current playlist \(currentId)")
        }
      }

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

        if songIndex == -1 && !allPlaylists.isEmpty {
          targetPlaylistId = allPlaylists[0].id
          songIndex = 0
          NitroPlayerLogger.log("TrackPlayerCore", "⚠️ Song not found in any playlist, using first playlist and starting at index 0")
        }
      }
    }

    guard let playlistId = targetPlaylistId, songIndex >= 0 else {
      NitroPlayerLogger.log("TrackPlayerCore", "❌ Could not determine playlist or song index")
      return
    }

    if self.currentPlaylistId != playlistId {
      NitroPlayerLogger.log("TrackPlayerCore", "🔄 Loading new playlist: \(playlistId)")
      if let playlist = self.playlistManager.getPlaylist(playlistId: playlistId) {
        self.currentPlaylistId = playlistId
        self.updatePlayerQueue(tracks: playlist.tracks)
      }
    }

    NitroPlayerLogger.log("TrackPlayerCore", "▶️ Playing from index: \(songIndex)")
    self.playFromIndexInternal(index: songIndex)
  }
}
