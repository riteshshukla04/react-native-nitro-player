import type { HybridObject } from 'react-native-nitro-modules'
import type {
  QueueOperation,
  Reason,
  TrackItem,
  TrackPlayerState,
  PlayerState,
  PlayerConfig,
  Playlist,
} from '../types/PlayerQueue'

export interface PlayerQueue
  extends HybridObject<{ android: 'kotlin'; ios: 'swift' }> {
  // Playlist management
  createPlaylist(name: string, description?: string, artwork?: string): string
  deletePlaylist(playlistId: string): void
  updatePlaylist(
    playlistId: string,
    name?: string,
    description?: string,
    artwork?: string
  ): void
  getPlaylist(playlistId: string): Playlist | null
  getAllPlaylists(): Playlist[]

  // Track management within playlists
  addTrackToPlaylist(playlistId: string, track: TrackItem, index?: number): void
  addTracksToPlaylist(
    playlistId: string,
    tracks: TrackItem[],
    index?: number
  ): void
  removeTrackFromPlaylist(playlistId: string, trackId: string): void
  reorderTrackInPlaylist(
    playlistId: string,
    trackId: string,
    newIndex: number
  ): void

  // Playback control
  loadPlaylist(playlistId: string): void
  getCurrentPlaylistId(): string | null

  // Events
  onPlaylistsChanged(
    callback: (playlists: Playlist[], operation?: QueueOperation) => void
  ): void
  onPlaylistChanged(
    callback: (
      playlistId: string,
      playlist: Playlist,
      operation?: QueueOperation
    ) => void
  ): void
}

export type RepeatMode = 'off' | 'Playlist' | 'track'

export interface TrackPlayer
  extends HybridObject<{ android: 'kotlin'; ios: 'swift' }> {
  play(): void
  pause(): void
  playSong(songId: string, fromPlaylist?: string): Promise<void>
  skipToNext(): void
  skipToIndex(index: number): Promise<boolean>
  skipToPrevious(): void
  seek(position: number): void
  addToUpNext(trackId: string): Promise<void>
  playNext(trackId: string): Promise<void>
  getActualQueue(): Promise<TrackItem[]>
  getState(): Promise<PlayerState>
  setRepeatMode(mode: RepeatMode): boolean
  configure(config: PlayerConfig): void
  onChangeTrack(callback: (track: TrackItem, reason?: Reason) => void): void
  onPlaybackStateChange(
    callback: (state: TrackPlayerState, reason?: Reason) => void
  ): void
  onSeek(callback: (position: number, totalDuration: number) => void): void
  onPlaybackProgressChange(
    callback: (
      position: number,
      totalDuration: number,
      isManuallySeeked?: boolean
    ) => void
  ): void
  onAndroidAutoConnectionChange(callback: (connected: boolean) => void): void
  isAndroidAutoConnected(): boolean
  setVolume(volume: number): boolean
}
