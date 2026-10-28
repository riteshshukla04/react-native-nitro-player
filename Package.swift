// swift-tools-version: 5.9
import PackageDescription

// Host tests for command routing, independent of UIKit and a running player.
let package = Package(
  name: "NitroPlayerRemoteCommandTests",
  targets: [
    .target(
      name: "RemoteTrackCommands",
      path: "react-native-nitro-player/ios/media",
      exclude: ["MediaSessionManager.swift"],
      sources: ["RemoteTrackCommands.swift"]
    ),
    .testTarget(
      name: "RemoteTrackCommandsTests",
      dependencies: ["RemoteTrackCommands"],
      path: "tests/RemoteTrackCommandsTests"
    ),
  ]
)
