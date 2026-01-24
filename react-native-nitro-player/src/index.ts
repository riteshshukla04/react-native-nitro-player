// TODO: Export all HybridObjects here for the user

import { NitroModules } from 'react-native-nitro-modules'
import { Platform } from 'react-native'
import type {
  PlayerQueue as PlayerQueueType,
  TrackPlayer as TrackPlayerType,
} from './specs/TrackPlayer.nitro'
import type { AndroidAutoMediaLibrary as AndroidAutoMediaLibraryType } from './specs/AndroidAutoMediaLibrary.nitro'
import type { AudioDevices as AudioDevicesType } from './specs/AudioDevices.nitro'
import type { AudioRoutePicker as AudioRoutePickerType } from './specs/AudioRoutePicker.nitro'
import type { DownloadManager as DownloadManagerType } from './specs/DownloadManager.nitro'

export const PlayerQueue =
  NitroModules.createHybridObject<PlayerQueueType>('PlayerQueue')
export const TrackPlayer =
  NitroModules.createHybridObject<TrackPlayerType>('TrackPlayer')

// Android-only: Android Auto Media Library
export const AndroidAutoMediaLibrary =
  Platform.OS === 'android'
    ? NitroModules.createHybridObject<AndroidAutoMediaLibraryType>(
        'AndroidAutoMediaLibrary'
      )
    : null

// Android-only: Audio Devices
export const AudioDevices =
  Platform.OS === 'android'
    ? NitroModules.createHybridObject<AudioDevicesType>('AudioDevices')
    : null

// iOS-only: Audio Route Picker
export const AudioRoutePicker =
  Platform.OS === 'ios'
    ? NitroModules.createHybridObject<AudioRoutePickerType>('AudioRoutePicker')
    : null

// Download Manager
export const DownloadManager =
  NitroModules.createHybridObject<DownloadManagerType>('DownloadManager')

// Export hooks
export * from './hooks'

// Export types
export * from './types/PlayerQueue'
export * from './types/AndroidAutoMediaLibrary'
export * from './types/DownloadTypes'
export type { TAudioDevice } from './specs/AudioDevices.nitro'
export type { RepeatMode } from './specs/TrackPlayer.nitro'
// Export utilities
export { AndroidAutoMediaLibraryHelper } from './utils/androidAutoMediaLibrary'
