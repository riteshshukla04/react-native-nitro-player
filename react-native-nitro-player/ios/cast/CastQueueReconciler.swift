// Pure state machine: one receiver request in flight at a time, newest desired state wins.

import Foundation

typealias CastItemID = UInt

struct CastQueueLoad {
  let tracks: [TrackItem]
  let startIndex: Int
  let position: Double
  let autoplay: Bool
  let repeatMode: RepeatMode
}

enum CastQueueEffect {
  case none
  case send(CastQueueOp)
  case sendLoad(CastQueueLoad)
  case sendUnload
  case recover(String)
}

final class CastQueueReconciler {

  private struct Busy {
    enum Kind {
      case load(CastQueueLoad)
      case unload
      case op(CastQueueOp)
    }
    let kind: Kind
    let expected: [String]
    var request: Int?
    var completed = false
    var observed = false
  }

  private struct Desired {
    let generation: UInt64
    let ids: [String]
    let currentId: String
  }

  private enum PendingLoad {
    case load(CastQueueLoad)
    case unload
  }

  private(set) var order: [CastItemID] = []
  /// Learned from our own completed operations, never guessed.
  private(set) var trackOf: [CastItemID: String] = [:]
  private(set) var unverified: Set<CastItemID> = []

  private var valid = false
  private var busy: Busy?
  private var pendingLoad: PendingLoad?
  private var latest: Desired?
  private var generationCounter: UInt64 = 0

  var orderedTrackIds: [String] { order.compactMap { trackOf[$0] } }

  var hasInFlightRequest: Bool { busy != nil }

  // MARK: - Inputs

  func desired(ids: [String], currentId: String) -> CastQueueEffect {
    generationCounter &+= 1
    latest = Desired(generation: generationCounter, ids: ids, currentId: currentId)
    guard busy == nil else { return .none }
    return dispatch()
  }

  func loadRequested(_ load: CastQueueLoad) -> CastQueueEffect {
    pendingLoad = .load(load)
    guard busy == nil else { return .none }
    return dispatch()
  }

  func unloadRequested() -> CastQueueEffect {
    pendingLoad = .unload
    guard busy == nil else { return .none }
    return dispatch()
  }

  func requestAssigned(_ requestId: Int) {
    busy?.request = requestId
  }

  func requestCompleted(_ requestId: Int) -> CastQueueEffect {
    guard var current = busy, current.request == requestId else { return .none }
    current.completed = true
    busy = current
    return finishIfReady()
  }

  func requestFailed(_ requestId: Int, reason: String) -> CastQueueEffect {
    guard let current = busy, current.request == requestId else { return .none }
    busy = nil
    valid = false
    return .recover(reason)
  }

  func queueObserved(_ ids: [CastItemID]) -> CastQueueEffect {
    guard var current = busy else {
      // Another sender changed the queue: reconstruct from the map rather than reloading.
      if ids.contains(where: { trackOf[$0] == nil }) {
        valid = false
        return .recover("foreign receiver item")
      }
      order = ids
      return latest == nil ? .none : plan()
    }

    guard ids.count == current.expected.count else { return .none }
    var learned: [CastItemID: String] = [:]
    for (index, id) in ids.enumerated() {
      if let known = trackOf[id] {
        if known != current.expected[index] { return .none }
      } else {
        learned[id] = current.expected[index]
      }
    }
    let introduced = introducedCount(current)
    if learned.count != introduced {
      if learned.isEmpty {
        order = ids
        return .none
      }
      busy = nil
      valid = false
      return .recover("foreign receiver item")
    }
    for (id, trackId) in learned {
      trackOf[id] = trackId
      unverified.insert(id)
    }
    order = ids
    current.observed = true
    busy = current
    return finishIfReady()
  }

  func verified(_ id: CastItemID, trackId: String) -> CastQueueEffect {
    guard let known = trackOf[id] else { return .none }
    unverified.remove(id)
    guard known != trackId else { return .none }
    busy = nil
    valid = false
    return .recover("id map mismatch")
  }

  func sessionEnded() {
    order = []
    trackOf = [:]
    unverified = []
    valid = false
    busy = nil
    pendingLoad = nil
    latest = nil
  }

  // MARK: - Internals

  private func introducedCount(_ current: Busy) -> Int {
    switch current.kind {
    case .load: return current.expected.count
    case .unload: return 0
    case .op(let op):
      if case .insert(let ids) = op { return ids.count }
      return 0
    }
  }

  private func finishIfReady() -> CastQueueEffect {
    guard let current = busy, current.completed, current.observed else { return .none }
    busy = nil
    return dispatch()
  }

  /// Loads win over diffs: they are jumps or recoveries, and they reset the id map.
  private func dispatch() -> CastQueueEffect {
    guard busy == nil else { return .none }
    if let pending = pendingLoad {
      pendingLoad = nil
      order = []
      trackOf = [:]
      unverified = []
      valid = true
      switch pending {
      case .load(let load):
        busy = Busy(kind: .load(load), expected: load.tracks.map(\.id))
        return .sendLoad(load)
      case .unload:
        busy = Busy(kind: .unload, expected: [])
        return .sendUnload
      }
    }
    return plan()
  }

  private func plan() -> CastQueueEffect {
    while true {
      guard valid, let target = latest else { return .none }
      let existing = orderedTrackIds
      guard existing.count == order.count else {
        valid = false
        return .recover("unmapped receiver item")
      }
      guard existing.filter({ $0 == target.currentId }).count == 1,
        target.ids.filter({ $0 == target.currentId }).count == 1
      else {
        valid = false
        return .recover("current id precondition")
      }
      guard
        let op = CastQueueDiff.nextOp(
          existing: existing, desired: target.ids, currentId: target.currentId)
      else {
        // Clear only the generation we planned for; a newer one is planned instead.
        guard let newest = latest, newest.generation == target.generation else { continue }
        latest = nil
        return .none
      }
      busy = Busy(kind: .op(op), expected: CastQueueDiff.apply(op, to: existing))
      return .send(op)
    }
  }
}
