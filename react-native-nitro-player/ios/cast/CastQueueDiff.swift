// Pure receiver-queue diff: no Cast SDK types, no operation ever contains the current item.

import Foundation

enum CastQueueOp: Equatable {
  case remove([String])
  case insert([String])
  case moveToEnd([String])
  case moveBefore([String], anchor: String)
}

enum CastQueueDiff {
  /// Converges in at most 4 ops. Caller guarantees `currentId` occurs exactly once in both lists.
  static func nextOp(existing: [String], desired: [String], currentId: String) -> CastQueueOp? {
    let desiredSet = Set(desired)
    let existingSet = Set(existing)

    let toRemove = existing.filter { !desiredSet.contains($0) }
    if !toRemove.isEmpty { return .remove(toRemove) }

    let toInsert = desired.filter { !existingSet.contains($0) }
    if !toInsert.isEmpty { return .insert(toInsert) }

    if existing == desired { return nil }
    guard let cur = desired.firstIndex(of: currentId) else { return nil }

    let after = Array(desired[(cur + 1)...])
    if !after.isEmpty, Array(existing.suffix(after.count)) != after { return .moveToEnd(after) }

    let before = Array(desired[..<cur])
    if !before.isEmpty, Array(existing.prefix(before.count)) != before {
      return .moveBefore(before, anchor: currentId)
    }
    return nil
  }

  static func apply(_ op: CastQueueOp, to existing: [String]) -> [String] {
    switch op {
    case .remove(let ids):
      let dropped = Set(ids)
      return existing.filter { !dropped.contains($0) }
    case .insert(let ids):
      return existing + ids
    case .moveToEnd(let ids):
      let moved = Set(ids)
      return existing.filter { !moved.contains($0) } + ids
    case .moveBefore(let ids, let anchor):
      let moved = Set(ids)
      var out: [String] = []
      out.reserveCapacity(existing.count)
      for id in existing where !moved.contains(id) {
        if id == anchor { out.append(contentsOf: ids) }
        out.append(id)
      }
      return out
    }
  }
}
