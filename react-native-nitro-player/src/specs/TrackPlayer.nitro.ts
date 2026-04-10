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

export interface PlayerQueue extends HybridObject<{
  android: 'kotlin'
  ios: 'swift'
}> {
  // Playlist management
  createPlaylist(
    name: string,
    description?: string,
    artwork?: string
  ): Promise<string>
  deletePlaylist(playlistId: string): Promise<void>
  updatePlaylist(
    playlistId: string,
    name?: string,
    description?: string,
    artwork?: string
  ): Promise<void>
  getPlaylist(playlistId: string): Playlist | null
  getAllPlaylists(): Playlist[]

  // Track management within playlists
  addTrackToPlaylist(
    playlistId: string,
    track: TrackItem,
    index?: number
  ): Promise<void>
  addTracksToPlaylist(
    playlistId: string,
    tracks: TrackItem[],
    index?: number
  ): Promise<void>
  removeTrackFromPlaylist(playlistId: string, trackId: string): Promise<void>
  reorderTrackInPlaylist(
    playlistId: string,
    trackId: string,
    newIndex: number
  ): Promise<void>

  // Playback control
  loadPlaylist(playlistId: string): Promise<void>
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

export interface TrackPlayer extends HybridObject<{
  android: 'kotlin'
  ios: 'swift'
}> {
  play(): Promise<void>
  pause(): Promise<void>
  playSong(songId: string, fromPlaylist?: string): Promise<void>
  skipToNext(): Promise<void>
  skipToIndex(index: number): Promise<boolean>
  skipToPrevious(): Promise<void>
  seek(position: number): Promise<void>
  addToUpNext(trackId: string): Promise<void>
  playNext(trackId: string): Promise<void>
  getActualQueue(): Promise<TrackItem[]>
  getState(): Promise<PlayerState>
  setRepeatMode(mode: RepeatMode): Promise<void>
  getRepeatMode(): RepeatMode
  configure(config: PlayerConfig): Promise<void>
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
  onCarPlayConnectionChange(callback: (connected: boolean) => void): void
  isCarPlayConnected(): boolean
  setVolume(volume: number): Promise<void>

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
  onTracksNeedUpdate(
    callback: (tracks: TrackItem[], lookahead: number) => void
  ): void

  /**
   * Get the current track index in the active playlist
   * @returns Promise resolving to 0-based index, or -1 if no track playing
   */
  setPlaybackSpeed(speed: number): Promise<void>

  /**
   * Get the current playback speed
   * @returns Promise resolving to playback speed
   */
  getPlaybackSpeed(): Promise<number>

  // =========================================================
  // Temporary queue management (v2)
  // =========================================================

  /** Remove a track from the playNext stack by ID. Returns true if found and removed. */
  removeFromPlayNext(trackId: string): Promise<boolean>

  /** Remove a track from the upNext queue by ID. Returns true if found and removed. */
  removeFromUpNext(trackId: string): Promise<boolean>

  /** Clear the entire playNext stack */
  clearPlayNext(): Promise<void>

  /** Clear the entire upNext queue */
  clearUpNext(): Promise<void>

  /**
   * Reorder a temporary track within the combined virtual queue
   * (playNextStack + upNextQueue). newIndex is 0-based within that combined list.
   * Returns true if the track was found and moved.
   */
  reorderTemporaryTrack(trackId: string, newIndex: number): Promise<boolean>

  /** Get the current playNext stack (LIFO order, index 0 plays first) */
  getPlayNextQueue(): Promise<TrackItem[]>

  /** Get the current upNext queue (FIFO order, index 0 plays first) */
  getUpNextQueue(): Promise<TrackItem[]>

  /**
   * Register callback that fires whenever the temporary queue (playNext or upNext) changes.
   */
  onTemporaryQueueChange(
    callback: (playNextQueue: TrackItem[], upNextQueue: TrackItem[]) => void
  ): void
}
