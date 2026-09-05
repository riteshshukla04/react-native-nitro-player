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

export interface ShufflePlaylistOptions {
  /** Move the playing track to index 0 and shuffle the rest behind it (default: true). */
  keepCurrentTrackFirst?: boolean
}

export type TrackPlayerState = 'playing' | 'paused' | 'stopped' | 'buffering'

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

/** In-stream metadata emitted while a stream plays (ICY/Shoutcast StreamTitle, ID3 frames) */
export interface TimedMetadata {
  title?: string
  /** Split out of `title` when the stream sends only `"Artist - Title"` */
  artist?: string
  album?: string
  /**
   * ICY `StreamUrl` / ID3 webpage frame. Radio providers commonly put the
   * current track's artwork URL here (Live365, StreamGuys), but some send a
   * station or artist page instead — check the value before treating it as art.
   */
  url?: string
  /** Artwork URL the stream tagged as artwork, when it sends one explicitly */
  artworkUrl?: string
}

export interface PlayerConfig {
  androidAutoEnabled?: boolean
  carPlayEnabled?: boolean
  showInNotification?: boolean
  /**
   * Fixed interval, in seconds, for remote skip-forward controls (default: 15)
   */
  remoteSkipForwardInterval?: number
  /**
   * Fixed interval, in seconds, for remote skip-backward controls (default: 15)
   */
  remoteSkipBackwardInterval?: number
  /**
   * Number of upcoming tracks to preload URLs for (default: 5)
   * Higher values = more proactive loading, but more network requests
   */
  lookaheadCount?: number

  androidNotificationIcon?: string
}
