// TODO: Export all HybridObjects here for the user

import { NitroModules } from 'react-native-nitro-modules'
import type {
  PlayerQueue as PlayerQueueType,
  TrackPlayer as TrackPlayerType,
} from './specs/TrackPlayer.nitro'

export const PlayerQueue =
  NitroModules.createHybridObject<PlayerQueueType>('PlayerQueue')
export const TrackPlayer =
  NitroModules.createHybridObject<TrackPlayerType>('TrackPlayer')

// Export hooks
export * from './hooks'

// Export types
export * from './types/PlayerQueue'
