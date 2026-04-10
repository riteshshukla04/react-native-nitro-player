//
//  CarPlayMediaModels.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//


import Foundation

enum CarPlayLayoutType {
  case grid
  case list
}

enum CarPlayMediaType {
  case folder
  case audio
  case playlist
}

struct CarPlayMediaItem {
  let id: String
  let title: String
  let subtitle: String?
  let iconUrl: String?
  let isPlayable: Bool
  let mediaType: CarPlayMediaType
  let playlistId: String?
  let children: [CarPlayMediaItem]?
  let layoutType: CarPlayLayoutType?
}

struct CarPlayMediaLibraryModel {
  let layoutType: CarPlayLayoutType
  let rootItems: [CarPlayMediaItem]
  let appName: String?
  let appIconUrl: String?
}
