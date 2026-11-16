//
//  NotificationButtonConfig.swift
//  NitroPlayer
//

import Foundation
import NitroModules
import UIKit

/// The iOS part of `PlayerConfig.notificationButtons`, checked so a bad config fails `configure`
/// instead of showing nothing.
struct IOSButtonConfig {
  let lockScreen: [LockScreenButton]
  let carPlay: [CarPlayButton]

  init(_ buttons: IOSNotificationButtons?) throws {
    lockScreen = buttons?.lockScreen ?? []
    carPlay = buttons?.carPlay ?? []

    if let id = Self.firstRepeated(lockScreen.map(\.id)) {
      throw RuntimeError.error(withMessage: "notificationButtons.ios.lockScreen: id '\(id)' is used more than once")
    }
    if let command = Self.firstRepeated(lockScreen.map(\.command.stringValue)) {
      throw RuntimeError.error(withMessage: "notificationButtons.ios.lockScreen: command '\(command)' is used more than once")
    }
    if let id = Self.firstRepeated(carPlay.map(\.id)) {
      throw RuntimeError.error(withMessage: "notificationButtons.ios.carPlay: id '\(id)' is used more than once")
    }
    for button in carPlay where (button.type ?? .image) == .image {
      guard let icon = button.icon else {
        throw RuntimeError.error(withMessage: "notificationButtons.ios.carPlay: '\(button.id)' needs an icon")
      }
      for name in [icon] + (button.activeIcon.map { [$0] } ?? []) where Self.image(named: name) == nil {
        throw RuntimeError.error(
          withMessage: "notificationButtons.ios.carPlay: icon '\(name)' of '\(button.id)' is neither an SF Symbol nor an image in the asset catalog")
      }
    }
  }

  /// An SF Symbol, or an image from the app's asset catalog
  static func image(named name: String) -> UIImage? {
    UIImage(systemName: name) ?? UIImage(named: name)
  }

  private static func firstRepeated(_ values: [String]) -> String? {
    var seen = Set<String>()
    return values.first { !seen.insert($0).inserted }
  }
}

/// On/off state of toggle buttons: per track, or for every track when set without track ids.
final class NotificationButtonStates {
  private struct Entry {
    var allTracks: Bool?
    var perTrack: [String: Bool] = [:]
  }

  private var entries: [String: Entry] = [:]

  func isActive(_ buttonId: String, trackId: String?) -> Bool {
    guard let entry = entries[buttonId] else { return false }
    if let trackId = trackId, let value = entry.perTrack[trackId] { return value }
    return entry.allTracks ?? false
  }

  func set(_ buttonId: String, trackIds: [String]?, isActive: Bool) {
    var entry = entries[buttonId] ?? Entry()
    if let trackIds = trackIds {
      for trackId in trackIds { entry.perTrack[trackId] = isActive }
    } else {
      entry.allTracks = isActive
      entry.perTrack.removeAll()
    }
    entries[buttonId] = entry
  }

  /// Records a press on `trackId`; for every track when the state was last set without track ids.
  func setFromPress(_ buttonId: String, trackId: String, isActive: Bool) {
    let entry = entries[buttonId]
    let forAllTracks = entry?.allTracks != nil && entry?.perTrack.isEmpty == true
    set(buttonId, trackIds: forAllTracks ? nil : [trackId], isActive: isActive)
  }
}
