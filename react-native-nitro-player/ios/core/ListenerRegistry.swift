//
//  ListenerRegistry.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 25/03/26.
//

import Foundation

final class ListenerRegistry<T> {
  private struct Entry {
    let id: Int64
    let callback: T
  }

  private let queue = DispatchQueue(label: "com.nitroplayer.registry")
  private var entries: [Entry] = []
  private var nextId: Int64 = 0

  /// Register a callback and return its stable ID for later removal.
  @discardableResult
  func add(_ callback: T) -> Int64 {
    var id: Int64 = 0
    queue.sync {
      nextId += 1
      id = nextId
      entries.append(Entry(id: id, callback: callback))
    }
    return id
  }

  /// Remove the callback with the given ID. Returns true if found.
  @discardableResult
  func remove(id: Int64) -> Bool {
    var found = false
    queue.sync {
      if let idx = entries.firstIndex(where: { $0.id == id }) {
        entries.remove(at: idx)
        found = true
      }
    }
    return found
  }

  /// Remove all registered callbacks.
  func clear() {
    queue.sync { entries.removeAll() }
  }

  /// Invoke action for every registered callback (snapshot iteration — safe under mutation).
  func forEach(_ action: (T) -> Void) {
    let snap = queue.sync { entries.map(\.callback) }
    snap.forEach(action)
  }

  /// True when no callbacks are registered.
  var isEmpty: Bool {
    queue.sync { entries.isEmpty }
  }
}
