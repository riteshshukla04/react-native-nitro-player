import { AppRegistry, Platform } from 'react-native'
import {
  PlayerQueue as HybridPlayerQueue,
  TrackPlayer as HybridTrackPlayer,
} from './specs/TrackPlayer.nitro'
import { AndroidAutoMediaLibrary as HybridAndroidAutoMediaLibrary } from './specs/AndroidAutoMediaLibrary.nitro'
import { AudioDevices as HybridAudioDevices } from './specs/AudioDevices.nitro'
import { AudioRoutePicker as HybridAudioRoutePicker } from './specs/AudioRoutePicker.nitro'
import { Cast as HybridCast } from './specs/Cast.nitro'
import { DownloadManager as HybridDownloadManager } from './specs/DownloadManager.nitro'
import { Equalizer as HybridEqualizer } from './specs/Equalizer.nitro'

// Native runs this while it needs JS without a resumed activity (car, screen off): it keeps JS timers ticking
if (Platform.OS === 'android') {
  AppRegistry.registerHeadlessTask(
    'NitroPlayerKeepAlive',
    () => () => new Promise<void>(() => {})
  )
}

// One instance per JS runtime: each instance removes its native listeners when the runtime tears it down
export const PlayerQueue = new HybridPlayerQueue()
export const TrackPlayer = new HybridTrackPlayer()

// Android-only: Android Auto Media Library
export const AndroidAutoMediaLibrary =
  Platform.OS === 'android' ? new HybridAndroidAutoMediaLibrary() : null

// Android-only: Audio Devices (static methods, no instance)
export const AudioDevices =
  Platform.OS === 'android' ? HybridAudioDevices : null

// iOS-only: Audio Route Picker (static methods, no instance)
export const AudioRoutePicker =
  Platform.OS === 'ios' ? HybridAudioRoutePicker : null

// Google Cast (iOS + Android)
export const Cast = new HybridCast()

// Download Manager
export const DownloadManager = new HybridDownloadManager()

// Equalizer
export const Equalizer = new HybridEqualizer()

// Export hooks
export * from './hooks'

// Export components
export { CastButton } from './components/CastButton'
export type { CastButtonProps } from './components/CastButton'

// Export types
export type { CastState } from './specs/Cast.nitro'
export * from './types/PlayerQueue'
export * from './types/AndroidAutoMediaLibrary'
export * from './types/DownloadTypes'
export * from './types/EqualizerTypes'
export type { TAudioDevice } from './specs/AudioDevices.nitro'
export type { RepeatMode } from './specs/TrackPlayer.nitro'
// Export utilities
export { AndroidAutoMediaLibraryHelper } from './utils/androidAutoMediaLibrary'
