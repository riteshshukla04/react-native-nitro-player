---
sidebar_position: 2
sidebar_label: '⬇️ Installation'
tags: [android, ios]
---

# Installation

Install `react-native-nitro-player` and its peer dependencies.

## Prerequisites

- React Native 0.76 or higher.
- [Nitro Modules](https://github.com/mrousavy/react-native-nitro-modules) must be installed.

## Step 1: Install the Package

```bash
npm install react-native-nitro-player
# or
yarn add react-native-nitro-player
# or
bun add react-native-nitro-player
```

## Step 2: Install Peer Dependencies

You need to install `react-native-nitro-modules` if you haven't already.

```bash
npm install react-native-nitro-modules
# or
yarn add react-native-nitro-modules
# or
bun add react-native-nitro-modules
```

## Step 3: Pod Install (iOS)

```bash
cd ios && pod install
```

## Step 4: Permissions (Optional)

### Android

If you want to read from external storage (for playing local files), add this to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<!-- For Android 13+ -->
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
```

### iOS

If you want to use the microphone or other features, add the keys to `Info.plist`. For basic playback, no special permissions are usually required unless you are using background audio.

For background audio, enable "Audio, AirPlay, and Picture in Picture" in your Xcode project's `Signing & Capabilities` tab under `Background Modes`.
