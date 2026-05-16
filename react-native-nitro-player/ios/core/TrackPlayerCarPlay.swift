//
//  TrackPlayerCarPlay.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//


import Foundation

// MARK: - CarPlay support

extension TrackPlayerCore {
  // MARK: - CarPlay connection state

  func isCarPlayConnected() -> Bool {
    return _isCarPlayConnectedField
  }

  func notifyCarPlayConnectionChange(_ connected: Bool) {
    _isCarPlayConnectedField = connected
    onCarPlayConnectionChangeListeners.forEach { $0(connected) }
  }

  // MARK: - Listener management

  @discardableResult
  func addOnCarPlayConnectionChangeListener(_ cb: @escaping (Bool) -> Void) -> Int64 {
    onCarPlayConnectionChangeListeners.add(cb)
  }

  @discardableResult
  func removeOnCarPlayConnectionChangeListener(id: Int64) -> Bool {
    onCarPlayConnectionChangeListeners.remove(id: id)
  }

  // MARK: - Media library

  func setCarPlayMediaLibrary(_ json: String) async {
    guard let library = CarPlayMediaLibraryParser.fromJson(json) else {
      NitroPlayerLogger.log("TrackPlayerCarPlay", "Failed to parse CarPlay media library JSON")
      return
    }
    CarPlayMediaLibraryManager.shared.setMediaLibrary(library)
    #if canImport(CarPlay)
    DispatchQueue.main.async {
      CarPlayManager.shared?.rebuildTemplates()
    }
    #endif
  }

  func clearCarPlayMediaLibrary() async {
    CarPlayMediaLibraryManager.shared.clear()
    #if canImport(CarPlay)
    DispatchQueue.main.async {
      CarPlayManager.shared?.rebuildTemplates()
    }
    #endif
  }
}
