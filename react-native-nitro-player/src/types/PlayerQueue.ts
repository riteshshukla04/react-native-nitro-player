import type { AnyMap } from 'react-native-nitro-modules'

export type CurrentPlayingType =
  | 'playlist'
  | 'up-next'
  | 'play-next'
  | 'not-playing'
export interface TrackItem {
  id: string
  title: string
  artist: string
  album: string
  duration: number
  url: string
  artwork?: string | null
  extraPayload?: AnyMap
}

export interface Playlist {
  id: string
  name: string
  description?: string | null
  artwork?: string | null
  tracks: TrackItem[]
}

export type QueueOperation = 'add' | 'remove' | 'clear' | 'update'

export type TrackPlayerState = 'playing' | 'paused' | 'stopped'

export type Reason = 'user_action' | 'skip' | 'end' | 'error' | 'repeat'

export interface PlayerState {
  currentTrack: TrackItem | null
  currentPosition: number
  totalDuration: number
  currentState: TrackPlayerState
  currentPlaylistId: string | null
  currentIndex: number
  currentPlayingType: CurrentPlayingType
}

export interface PlayerConfig {
  androidAutoEnabled?: boolean
  carPlayEnabled?: boolean
  showInNotification?: boolean
}
