//
//  PlaylistModel.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 10/12/25.
//

import Foundation
import NitroModules

/// Represents a playlist containing multiple tracks
/// Uses AVPlayer's native playlist functionality
class PlaylistModel {
  let id: String
  let name: String
  let description: String?
  let artwork: String?
  var tracks: [TrackItem]

  init(
    id: String, name: String, description: String? = nil, artwork: String? = nil,
    tracks: [TrackItem] = []
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.artwork = artwork
    self.tracks = tracks
  }

  func getTrackCount() -> Int {
    return tracks.count
  }

  func isEmpty() -> Bool {
    return tracks.isEmpty
  }

  // Convert to generated Playlist type
  func toGeneratedPlaylist() -> Playlist {
    return Playlist(
      id: self.id,
      name: self.name,
      description: self.description.map { Variant_NullType_String.second($0) },
      artwork: self.artwork.map { Variant_NullType_String.second($0) },
      tracks: self.tracks
    )
  }
}
