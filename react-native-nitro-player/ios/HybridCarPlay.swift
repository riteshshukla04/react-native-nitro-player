//
//  HybridCarPlay.swift
//  NitroPlayer
//

import Foundation
import NitroModules

final class HybridCarPlay: HybridCarPlaySpec {
  private let manager = CarPlayManager.shared
  private var connectionListenerIds: [Int64] = []

  func setRoot(rootJson: String) throws {
    try manager.setRoot(json: rootJson)
  }

  func pushTemplate(templateJson: String) throws {
    try manager.push(json: templateJson)
  }

  func popTemplate() throws {
    manager.pop()
  }

  func popToRoot() throws {
    manager.popToRoot()
  }

  func showNowPlaying() throws {
    manager.showNowPlaying()
  }

  func updateTemplate(templateJson: String) throws {
    try manager.update(json: templateJson)
  }

  func reload(templateId: String?) throws {
    manager.reload(templateId: templateId)
  }

  func isConnected() throws -> Bool {
    manager.isConnected
  }

  func onConnectionChange(callback: @escaping (_ connected: Bool) -> Void) throws {
    connectionListenerIds.append(manager.addConnectionListener(callback))
  }

  func onSelect(callback: @escaping (_ id: String, _ templateId: String) -> Void) throws {
    manager.setSelectHandler(callback)
  }

  func onLoadTemplate(callback: @escaping (_ requestId: String, _ itemId: String) -> Void) throws {
    manager.setLoadHandler(callback)
  }

  func resolveTemplate(requestId: String, templateJson: String) throws {
    manager.resolveTemplate(requestId: requestId, json: templateJson)
  }

  func onAlbumArtistPress(callback: @escaping (_ track: TrackItem) -> Void) throws {
    manager.setAlbumArtistHandler(callback)
  }

  deinit {
    connectionListenerIds.forEach { manager.removeConnectionListener(id: $0) }
  }
}
