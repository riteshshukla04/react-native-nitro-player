//
//  NitroPlayerStorage.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 19/02/26.
//

import Foundation

enum NitroPlayerStorage {
  /// Reads raw data from a file in the NitroPlayer storage directory.
  /// Returns nil if the file does not exist or cannot be read.
  static func read(filename: String) -> Data? {
    let url = storageDirectory().appendingPathComponent(filename)
    return try? Data(contentsOf: url)
  }

  /// Atomically writes data to a file in the NitroPlayer storage directory.
  /// Writes to `<filename>.tmp` first, then renames to the final name —
  /// leaving the prior file untouched if the write crashes mid-way.
  static func write(filename: String, data: Data) throws {
    let dir = storageDirectory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(filename)
    let tmp = dir.appendingPathComponent(filename + ".tmp")
    try data.write(to: tmp)
    if FileManager.default.fileExists(atPath: dest.path) {
      _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
    } else {
      try FileManager.default.moveItem(at: tmp, to: dest)
    }
  }

  /// Returns the NitroPlayer subdirectory inside Application Support.
  /// Uses `FileManager` APIs — never hardcodes the UUID-based container path
  /// so this resolves correctly regardless of which device or simulator the
  /// app runs on.
  private static let storageDir: URL = {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    return appSupport.appendingPathComponent("NitroPlayer", isDirectory: true)
  }()

  private static func storageDirectory() -> URL { storageDir }
}
