//
//  HybridCarPlayMediaLibrary.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//

import Foundation
import NitroModules

final class HybridCarPlayMediaLibrary: HybridCarPlayMediaLibrarySpec {
  private let core: TrackPlayerCore

  override init() {
    core = TrackPlayerCore.shared
    super.init()
  }

  func setMediaLibrary(libraryJson: String) throws -> Promise<Void> {
    Promise.async {
      await self.core.setCarPlayMediaLibrary(libraryJson)
    }
  }

  func clearMediaLibrary() throws -> Promise<Void> {
    Promise.async {
      await self.core.clearCarPlayMediaLibrary()
    }
  }
}
