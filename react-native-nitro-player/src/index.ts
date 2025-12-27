// TODO: Export all HybridObjects here for the user

import { NitroModules } from 'react-native-nitro-modules'
import { Platform } from 'react-native'
import type {
  PlayerQueue as PlayerQueueType,
  TrackPlayer as TrackPlayerType,
} from './specs/TrackPlayer.nitro'
import type { AndroidAutoMediaLibrary as AndroidAutoMediaLibraryType } from './specs/AndroidAutoMediaLibrary.nitro'

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

// Export hooks
export * from './hooks'

// Export types
export * from './types/PlayerQueue'
export * from './types/AndroidAutoMediaLibrary'

// Export utilities
export { AndroidAutoMediaLibraryHelper } from './utils/androidAutoMediaLibrary'
