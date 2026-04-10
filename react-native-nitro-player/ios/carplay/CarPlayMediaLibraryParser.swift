//
//  CarPlayMediaLibraryParser.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//

import Foundation

enum CarPlayMediaLibraryParser {
  static func fromJson(_ json: String) -> CarPlayMediaLibraryModel? {
    guard let data = json.data(using: .utf8),
          let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    let layoutType: CarPlayLayoutType
    if let layoutStr = jsonObject["layoutType"] as? String, layoutStr.lowercased() == "grid" {
      layoutType = .grid
    } else {
      layoutType = .list
    }

    let rootItems = parseMediaItems(jsonObject["rootItems"] as? [[String: Any]])

    return CarPlayMediaLibraryModel(
      layoutType: layoutType,
      rootItems: rootItems,
      appName: jsonObject["appName"] as? String,
      appIconUrl: jsonObject["appIconUrl"] as? String
    )
  }

  private static func parseMediaItems(_ jsonArray: [[String: Any]]?) -> [CarPlayMediaItem] {
    guard let jsonArray = jsonArray else { return [] }
    return jsonArray.compactMap { parseMediaItem($0) }
  }

  private static func parseMediaItem(_ dict: [String: Any]) -> CarPlayMediaItem? {
    guard let id = dict["id"] as? String,
          let title = dict["title"] as? String
    else {
      return nil
    }

    let mediaTypeStr = (dict["mediaType"] as? String)?.lowercased() ?? "folder"
    let mediaType: CarPlayMediaType
    switch mediaTypeStr {
    case "audio": mediaType = .audio
    case "playlist": mediaType = .playlist
    default: mediaType = .folder
    }

    let layoutType: CarPlayLayoutType?
    if let layoutStr = (dict["layoutType"] as? String)?.lowercased() {
      switch layoutStr {
      case "grid": layoutType = .grid
      case "list": layoutType = .list
      default: layoutType = nil
      }
    } else {
      layoutType = nil
    }

    let children = parseMediaItems(dict["children"] as? [[String: Any]])

    return CarPlayMediaItem(
      id: id,
      title: title,
      subtitle: dict["subtitle"] as? String,
      iconUrl: dict["iconUrl"] as? String,
      isPlayable: dict["isPlayable"] as? Bool ?? false,
      mediaType: mediaType,
      playlistId: dict["playlistId"] as? String,
      children: children.isEmpty ? nil : children,
      layoutType: layoutType
    )
  }
}
