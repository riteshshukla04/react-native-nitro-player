//
//  Queue.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 24/11/25.
//

import Foundation

/// Queue class that manages a list of tracks.
/// Thread-safe implementation using a serial dispatch queue.
class Queue {
  private var tracks: [TrackItem] = []
  private let queue = DispatchQueue(label: "com.margelo.nitro.nitroplayer.queue")

  /**
   * Get all tracks in the queue
   */
  func getTracks() -> [TrackItem] {
    return queue.sync {
      return Array(tracks)
    }
  }

  /**
   * Add a single track to the queue
   */
  func addTrack(_ track: TrackItem) {
    queue.sync {
      self.tracks.append(track)
    }
  }

  /**
   * Add a track at a specific index
   */
  func addTrackAtIndex(_ track: TrackItem, index: Int) {
    queue.sync {
      if index < 0 || index > self.tracks.count {
        self.tracks.append(track)
      } else {
        self.tracks.insert(track, at: index)
      }
    }
  }

  /**
   * Load multiple tracks into the queue (replaces existing queue)
   */
  func loadTracks(_ newTracks: [TrackItem]) {
    queue.sync {
      self.tracks.removeAll()
      self.tracks.append(contentsOf: newTracks)
    }
  }

  /**
   * Remove a track by ID
   * @return true if track was found and removed, false otherwise
   */
  func removeTrack(id: String) -> Bool {
    return queue.sync {
      let initialCount = self.tracks.count
      self.tracks.removeAll { $0.id == id }
      return self.tracks.count < initialCount
    }
  }

  /**
   * Clear all tracks from the queue
   */
  func clear() {
    queue.sync {
      self.tracks.removeAll()
    }
  }

  /**
   * Get the size of the queue
   */
  func size() -> Int {
    return queue.sync {
      return self.tracks.count
    }
  }

  /**
   * Check if the queue is empty
   */
  func isEmpty() -> Bool {
    return queue.sync {
      return self.tracks.isEmpty
    }
  }

  /**
   * Get a track by index
   */
  func getTrack(index: Int) -> TrackItem? {
    return queue.sync {
      if index >= 0 && index < self.tracks.count {
        return self.tracks[index]
      } else {
        return nil
      }
    }
  }

  /**
   * Get a track by ID
   */
  func getTrackById(id: String) -> TrackItem? {
    return queue.sync {
      return self.tracks.first { $0.id == id }
    }
  }

  /**
   * Get the index of a track by ID
   */
  func getTrackIndex(id: String) -> Int {
    return queue.sync {
      return self.tracks.firstIndex { $0.id == id } ?? -1
    }
  }
}
