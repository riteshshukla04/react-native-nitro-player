//
//  CarPlayMediaLibraryManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//


import Foundation

class CarPlayMediaLibraryManager {
  static let shared = CarPlayMediaLibraryManager()

  private var mediaLibrary: CarPlayMediaLibraryModel?

  private init() {}

  func setMediaLibrary(_ library: CarPlayMediaLibraryModel) {
    mediaLibrary = library
    NitroPlayerLogger.log("CarPlayMediaLibraryManager", "Media library set with \(library.rootItems.count) root items")
  }

  func getMediaLibrary() -> CarPlayMediaLibraryModel? {
    return mediaLibrary
  }

  func getMediaItemById(_ itemId: String) -> CarPlayMediaItem? {
    guard let library = mediaLibrary else { return nil }
    return findMediaItemRecursive(library.rootItems, targetId: itemId)
  }

  private func findMediaItemRecursive(_ items: [CarPlayMediaItem], targetId: String) -> CarPlayMediaItem? {
    for item in items {
      if item.id == targetId {
        return item
      }
      if let children = item.children {
        if let found = findMediaItemRecursive(children, targetId: targetId) {
          return found
        }
      }
    }
    return nil
  }

  func getChildrenById(_ parentId: String) -> [CarPlayMediaItem]? {
    let item = getMediaItemById(parentId)
    return item?.children
  }

  func clear() {
    mediaLibrary = nil
    NitroPlayerLogger.log("CarPlayMediaLibraryManager", "Media library cleared")
  }
}
