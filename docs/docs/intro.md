---
sidebar_position: 1
sidebar_label: '🏠 Introduction'
tags: [android, ios]
---

# Introduction

**React Native Nitro Player** is a powerful, high-performance audio player library for React Native.

## Features

- 🎵 **High Performance**: Built with [Nitro Modules](https://github.com/mrousavy/react-native-nitro-modules) for maximum speed and efficiency.
- 📋 **Playlist Management**: Robust playlist support with full queue management.
- 🚗 **Car Integration**: Native support for **Android Auto** and **CarPlay**.
- 🎛️ **Equalizer**: 5-band equalizer with presets and custom settings.
- 📥 **Offline Downloads**: Download tracks and playlists for offline playback.
- 📱 **Background Playback**: Seamless playback when the app is in the background.
- 🎚️ **Lock Screen Controls**: Native lock screen and notification controls.

## Async command APIs

**Playback and queue mutations** on `TrackPlayer` and `PlayerQueue` return **Promises**. They resolve after native work completes and **reject** when the operation fails (for example invalid track id, bad state). Prefer `await` inside `async` functions, and use `try/catch` or `.catch()` when you need to handle errors:

```ts
await TrackPlayer.play()
await PlayerQueue.loadPlaylist(playlistId)
```

In event handlers or `useEffect` where you cannot `await`, it is fine to **fire-and-forget** with `void` (and optional `.catch()` for logging):

```ts
void TrackPlayer.configure({ showInNotification: true })
```

**DownloadManager** splits APIs by cost: active-task queries (`getActiveDownloads`, `isDownloading`, …) stay **synchronous** on in-memory state; **downloaded-file** checks and `getEffectiveUrl` use **async** I/O. See the [DownloadManager](./api/download-manager) page for the full list.

## Architecture

React Native Nitro Player uses the latest React Native technologies:

- **Nitro Modules**: For extremely fast native communication.
- **Hybrid Objects**: Exposes native objects directly to JavaScript.
- **Swift & Kotlin**: Modern native implementation.

## Getting Started

Check out the [Installation](./installation.md) guide to get started.
