//
//  TrackPlayerShuffle.swift
//  NitroPlayer
//

import Foundation

extension TrackPlayerCore {

  func seedShuffleOrder(_ tracks: [TrackItem], firstId: String? = nil) {
    let rest = tracks.map(\.id).filter { $0 != firstId }.shuffled()
    shuffleOrder = (firstId.map { [$0] } ?? []) + rest
  }

  /// Identity when shuffle is off; otherwise reorders `tracks` by `shuffleOrder` — stale ids drop out, new ids join a random upcoming slot.
  func applyShuffleOrder(_ tracks: [TrackItem]) -> [TrackItem] {
    guard shuffleEnabled else { return tracks }
    // ponytail: duplicate ids collapse to one entry, already unsupported everywhere else
    let byId = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    shuffleOrder.removeAll { byId[$0] == nil }
    var known = Set(shuffleOrder)
    let lo = min(max(currentTrackIndex + 1, 0), shuffleOrder.count)
    for track in tracks {
      guard known.insert(track.id).inserted else { continue }
      shuffleOrder.insert(track.id, at: Int.random(in: lo...shuffleOrder.count))
    }
    return shuffleOrder.compactMap { byId[$0] }
  }

  private func applyShuffleState() {
    let source = currentPlaylistId.flatMap { playlistManager.getPlaylist(playlistId: $0)?.tracks } ?? currentTracks
    let anchorId = currentTracks[safe: currentTrackIndex]?.id
    if shuffleEnabled { seedShuffleOrder(source, firstId: anchorId) }
    currentTracks = applyShuffleOrder(source)
    currentTrackIndex = anchorId.flatMap { id in currentTracks.firstIndex { $0.id == id } } ?? -1
    if isCasting || player?.currentItem != nil { rebuildAVQueueFromCurrentPosition() }
    checkUpcomingTracksForUrls(lookahead: lookaheadCount)
    notifyShuffleChange(shuffleEnabled)
  }

  func setShuffleModeOnQueue(enabled: Bool) {
    guard enabled != shuffleEnabled else { return }
    shuffleEnabled = enabled
    applyShuffleState()
  }

  func setShuffleMode(enabled: Bool) async {
    await withPlayerQueueNoThrow { self.setShuffleModeOnQueue(enabled: enabled) }
  }

  func reshuffleOnQueue() {
    shuffleEnabled = true
    applyShuffleState()
  }
}
