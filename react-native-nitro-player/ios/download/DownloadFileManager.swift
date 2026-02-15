//
//  DownloadFileManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 2026-01-23..
//

import Foundation
import NitroModules

/// Manages file operations for downloaded tracks
final class DownloadFileManager {

  // MARK: - Singleton

  static let shared = DownloadFileManager()

  // MARK: - Constants

  private static let privateDownloadsFolderName = "NitroPlayerDownloads"
  private static let publicDownloadsFolderName = "NitroPlayerMusic"

  // MARK: - Properties

  private let fileManager = FileManager.default

  private lazy var privateDownloadsDirectory: URL = {
    let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let downloadsPath = documentsPath.appendingPathComponent(Self.privateDownloadsFolderName)

    if !fileManager.fileExists(atPath: downloadsPath.path) {
      try? fileManager.createDirectory(at: downloadsPath, withIntermediateDirectories: true)
    }

    return downloadsPath
  }()

  private lazy var publicDownloadsDirectory: URL = {
    // On iOS, we can't write to a truly public folder, but we can use the shared container
    // or the Documents folder which is accessible via Files app
    let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let publicPath = documentsPath.appendingPathComponent(Self.publicDownloadsFolderName)

    if !fileManager.fileExists(atPath: publicPath.path) {
      try? fileManager.createDirectory(at: publicPath, withIntermediateDirectories: true)
    }

    return publicPath
  }()

  // MARK: - Initialization

  private init() {}

  // MARK: - File Operations

  func saveDownloadedFile(
    from temporaryLocation: URL, trackId: String, storageLocation: StorageLocation,
    originalURL: String? = nil,
    suggestedFilename: String? = nil,
    httpResponse: HTTPURLResponse? = nil
  ) -> String? {
    print("🎯 DownloadFileManager: saveDownloadedFile called for trackId=\(trackId)")
    print("   From: \(temporaryLocation.path)")
    print("   Original URL: \(originalURL ?? "nil")")
    print("   Suggested Filename: \(suggestedFilename ?? "nil")")

    let destinationDirectory =
      storageLocation == .private ? privateDownloadsDirectory : publicDownloadsDirectory
    print("   Destination directory: \(destinationDirectory.path)")

    // Determine file extension using headers first, then URL path, then default
    let fileExtension = Self.resolveFileExtension(
      httpResponse: httpResponse,
      suggestedFilename: suggestedFilename,
      originalURL: originalURL
    )
    print("   File extension: \(fileExtension)")

    let fileName = "\(trackId).\(fileExtension)"
    let destinationURL = destinationDirectory.appendingPathComponent(fileName)
    print("   Destination: \(destinationURL.path)")

    // Verify source file exists
    guard fileManager.fileExists(atPath: temporaryLocation.path) else {
      print("❌ DownloadFileManager: Source file does not exist at \(temporaryLocation.path)")
      return nil
    }

    do {
      // Remove existing file if present
      if fileManager.fileExists(atPath: destinationURL.path) {
        print("   Removing existing file at destination")
        try fileManager.removeItem(at: destinationURL)
      }

      // Move from temporary location to permanent location
      try fileManager.moveItem(at: temporaryLocation, to: destinationURL)

      print("✅ DownloadFileManager: File saved successfully")
      return destinationURL.path
    } catch {
      print("❌ DownloadFileManager: Failed to save file: \(error)")
      return nil
    }
  }

  // MARK: - Extension Resolution

  private static let mimeTypeToExtension: [String: String] = [
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/mp4": "m4a",
    "audio/m4a": "m4a",
    "audio/x-m4a": "m4a",
    "audio/aac": "aac",
    "audio/ogg": "ogg",
    "audio/flac": "flac",
    "audio/x-flac": "flac",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/webm": "webm",
    "audio/opus": "opus",
  ]

  /// Resolves the audio file extension from HTTP response headers, suggested filename, or URL.
  /// Priority: Content-Disposition filename → Content-Type MIME → suggestedFilename → URL path ext → "mp3"
  private static func resolveFileExtension(
    httpResponse: HTTPURLResponse?,
    suggestedFilename: String?,
    originalURL: String?
  ) -> String {
    // 1. Content-Disposition: attachment; filename="track.mp3"
    if let disposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition") {
      if let ext = extensionFromContentDisposition(disposition), !ext.isEmpty {
        print("   [ExtResolve] Content-Disposition → .\(ext)")
        return ext
      }
    }

    // 2. Content-Type MIME type
    if let contentType = httpResponse?.value(forHTTPHeaderField: "Content-Type") {
      let mime = contentType.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? contentType
      if let ext = mimeTypeToExtension[mime.lowercased()] {
        print("   [ExtResolve] Content-Type '\(mime)' → .\(ext)")
        return ext
      }
    }

    // 3. Suggested filename from URLSession
    if let name = suggestedFilename, !name.isEmpty {
      let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
      if !ext.isEmpty && isAudioExtension(ext) {
        print("   [ExtResolve] suggestedFilename → .\(ext)")
        return ext
      }
    }

    // 4. URL path extension (only if it looks like an audio format, not e.g. ".view")
    if let urlString = originalURL, let url = URL(string: urlString) {
      let ext = url.pathExtension.lowercased()
      if !ext.isEmpty && isAudioExtension(ext) {
        print("   [ExtResolve] URL path ext → .\(ext)")
        return ext
      }
    }

    print("   [ExtResolve] fallback → .mp3")
    return "mp3"
  }

  private static func extensionFromContentDisposition(_ disposition: String) -> String? {
    // Match: filename="foo.mp3" or filename=foo.mp3
    let patterns = [
      #"filename\*?=(?:UTF-8'')?\"?([^\";\r\n]+)\"?"#,
    ]
    for pattern in patterns {
      if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
        let range = NSRange(disposition.startIndex..., in: disposition)
        if let match = regex.firstMatch(in: disposition, range: range),
          let filenameRange = Range(match.range(at: 1), in: disposition)
        {
          let filename = String(disposition[filenameRange]).trimmingCharacters(in: .whitespaces)
          let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
          if !ext.isEmpty { return ext }
        }
      }
    }
    return nil
  }

  private static func isAudioExtension(_ ext: String) -> Bool {
    let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "ogg", "flac", "wav", "webm", "opus", "mp4"]
    return audioExtensions.contains(ext)
  }

  func deleteFile(at path: String) {
    do {
      if fileManager.fileExists(atPath: path) {
        try fileManager.removeItem(atPath: path)
      }
    } catch {
      print("[DownloadFileManager] Failed to delete file: \(error)")
    }
  }

  func getFileSize(at path: String) -> Int64 {
    do {
      let attributes = try fileManager.attributesOfItem(atPath: path)
      return attributes[.size] as? Int64 ?? 0
    } catch {
      return 0
    }
  }

  func getStorageInfo() -> DownloadStorageInfo {
    // Calculate total downloaded size
    var totalDownloadedSize: Int64 = 0
    var trackCount = 0
    var playlistCount = 0

    // Count files in private directory
    if let enumerator = fileManager.enumerator(
      at: privateDownloadsDirectory, includingPropertiesForKeys: [.fileSizeKey])
    {
      for case let fileURL as URL in enumerator {
        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalDownloadedSize += Int64(fileSize)
          trackCount += 1
        }
      }
    }

    // Count files in public directory
    if let enumerator = fileManager.enumerator(
      at: publicDownloadsDirectory, includingPropertiesForKeys: [.fileSizeKey])
    {
      for case let fileURL as URL in enumerator {
        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalDownloadedSize += Int64(fileSize)
          trackCount += 1
        }
      }
    }

    // Get device storage info
    let systemAttributes: [FileAttributeKey: Any]
    do {
      systemAttributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
    } catch {
      systemAttributes = [:]
    }

    let availableSpace = (systemAttributes[.systemFreeSize] as? Int64) ?? 0
    let totalSpace = (systemAttributes[.systemSize] as? Int64) ?? 0

    // Get playlist count from database
    playlistCount = DownloadDatabase.shared.getAllDownloadedPlaylists().count

    return DownloadStorageInfo(
      totalDownloadedSize: Double(totalDownloadedSize),
      trackCount: Double(trackCount),
      playlistCount: Double(playlistCount),
      availableSpace: Double(availableSpace),
      totalSpace: Double(totalSpace)
    )
  }

  func cleanupOrphanedFiles() -> Int64 {
    var bytesFreed: Int64 = 0

    let downloadedTrackIds = Set(
      DownloadDatabase.shared.getAllDownloadedTracks().map { $0.trackId })

    // Check private directory
    bytesFreed += cleanupDirectory(privateDownloadsDirectory, keepingTrackIds: downloadedTrackIds)

    // Check public directory
    bytesFreed += cleanupDirectory(publicDownloadsDirectory, keepingTrackIds: downloadedTrackIds)

    return bytesFreed
  }

  private func cleanupDirectory(_ directory: URL, keepingTrackIds: Set<String>) -> Int64 {
    var bytesFreed: Int64 = 0

    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.fileSizeKey])
    else {
      return 0
    }

    for fileURL in contents {
      let fileName = fileURL.deletingPathExtension().lastPathComponent
      if !keepingTrackIds.contains(fileName) {
        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          bytesFreed += Int64(fileSize)
        }
        try? fileManager.removeItem(at: fileURL)
      }
    }

    return bytesFreed
  }

  func getLocalPath(for trackId: String) -> String? {
    // Check private directory first
    let privateFiles =
      (try? fileManager.contentsOfDirectory(
        at: privateDownloadsDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in privateFiles {
      if file.deletingPathExtension().lastPathComponent == trackId {
        return file.path
      }
    }

    // Check public directory
    let publicFiles =
      (try? fileManager.contentsOfDirectory(
        at: publicDownloadsDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in publicFiles {
      if file.deletingPathExtension().lastPathComponent == trackId {
        return file.path
      }
    }

    return nil
  }
}
