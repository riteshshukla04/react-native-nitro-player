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
  getRepeatMode(): RepeatMode
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

  /**
   * Update entire track objects across all playlists
   * Matches by track.id and updates all properties (url, artwork, title, etc.)
   * Note: Empty string "" is valid for TrackItem.url to support lazy loading
   * @param tracks Array of full TrackItem objects to update
   * @returns Promise that resolves when updates complete
   */
  updateTracks(tracks: TrackItem[]): Promise<void>

  /**
   * Get tracks by IDs from all playlists
   * @param trackIds Array of track IDs to fetch
   * @returns Promise resolving to array of matching tracks
   */
  getTracksById(trackIds: string[]): Promise<TrackItem[]>

  /**
   * Get tracks with missing/empty URLs from current playlist
   * @returns Promise resolving to array of tracks needing URLs
   */
  getTracksNeedingUrls(): Promise<TrackItem[]>

  /**
   * Get next N tracks from current position in playlist
   * Useful for preloading URLs before they're needed
   * @param count Number of upcoming tracks to return
   * @returns Promise resolving to array of next tracks
   */
  getNextTracks(count: number): Promise<TrackItem[]>

  /**
   * Get current track index in the active playlist
   * @returns Promise resolving to 0-based index, or -1 if no track playing
   */
  getCurrentTrackIndex(): Promise<number>

  /**
   * Register callback that fires when tracks will be needed soon
   * Useful for proactive URL resolution in Android Auto/CarPlay
   * @param callback Function called with tracks needing URLs and lookahead count
   */
  onTracksNeedUpdate(callback: (tracks: TrackItem[], lookahead: number) => void): void
}
