//
//  QueueManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 24/11/25.
//

import Foundation

/// Wrapper class to store listeners with unique IDs for removal
private class ListenerWrapper {
  let id: UUID
  let listener: ([TrackItem], QueueOperation?) -> Void

  init(id: UUID = UUID(), listener: @escaping ([TrackItem], QueueOperation?) -> Void) {
    self.id = id
    self.listener = listener
  }
}

/// QueueManager is a singleton that manages the queue state across the app session.
/// It provides thread-safe access to the queue and notifies listeners of queue changes.
class QueueManager {
  private let queue = Queue()
  private var listeners: [ListenerWrapper] = []
  private let listenersQueue = DispatchQueue(label: "com.margelo.nitro.nitroplayer.listeners")

  static let shared = QueueManager()

  private init() {}

  /**
   * Get the current queue
   */
  func getQueue() -> Queue {
    return queue
  }

  /**
   * Get all tracks in the queue
   */
  func getTracks() -> [TrackItem] {
    return queue.getTracks()
  }

  /**
   * Load multiple tracks into the queue (replaces existing queue)
   */
  func loadQueue(_ tracks: [TrackItem]) {
    queue.loadTracks(tracks)
    notifyListeners(.add)
  }

  /**
   * Load a single track at a specific index
   */
  func loadSingleTrack(_ track: TrackItem, index: Double?) {
    let insertIndex = index.map { Int($0) }
    if let insertIndex = insertIndex, insertIndex >= 0 {
      queue.addTrackAtIndex(track, index: insertIndex)
    } else {
      queue.addTrack(track)
    }
    notifyListeners(.add)
  }

  /**
   * Delete a track by ID
   */
  func deleteTrack(id: String) {
    let removed = queue.removeTrack(id: id)
    if removed {
      notifyListeners(.remove)
    }
  }

  /**
   * Clear all tracks from the queue
   */
  func clearQueue() {
    queue.clear()
    notifyListeners(.clear)
  }

  /**
   * Add a listener for queue changes
   * @param listener Callback that receives (queue, operation)
   * @return A function to remove the listener
   */
  func addQueueChangeListener(
    _ listener: @escaping (_ queue: [TrackItem], _ operation: QueueOperation?) -> Void
  ) -> () -> Void {
    let wrapper = ListenerWrapper(listener: listener)
    listenersQueue.sync {
      listeners.append(wrapper)
    }

    return { [weak self, wrapper] in
      self?.listenersQueue.sync {
        self?.listeners.removeAll { $0.id == wrapper.id }
      }
    }
  }

  /**
   * Notify all listeners of queue changes
   */
  private func notifyListeners(_ operation: QueueOperation?) {
    let currentTracks = queue.getTracks()
    listenersQueue.sync {
      let listenersCopy = listeners
      for wrapper in listenersCopy {
        do {
          wrapper.listener(currentTracks, operation)
        } catch {
          // Log error but don't break other listeners
          print("Error in queue change listener: \(error)")
        }
      }
    }
  }

  /**
   * Get queue size
   */
  func getQueueSize() -> Int {
    return queue.size()
  }

  /**
   * Check if queue is empty
   */
  func isQueueEmpty() -> Bool {
    return queue.isEmpty()
  }

  /**
   * Get a track by index
   */
  func getTrack(index: Int) -> TrackItem? {
    return queue.getTrack(index: index)
  }

  /**
   * Get a track by ID
   */
  func getTrackById(id: String) -> TrackItem? {
    return queue.getTrackById(id: id)
  }

  /**
   * Get the index of a track by ID
   */
  func getTrackIndex(id: String) -> Int {
    return queue.getTrackIndex(id: id)
  }
}
