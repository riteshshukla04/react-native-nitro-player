import type { HybridObject } from 'react-native-nitro-modules'
import type { TrackItem } from '../types/PlayerQueue'
import type {
  DownloadConfig,
  DownloadTask,
  DownloadProgress,
  DownloadedTrack,
  DownloadedPlaylist,
  DownloadState,
  DownloadStorageInfo,
  DownloadQueueStatus,
  DownloadError,
  PlaybackSource,
} from '../types/DownloadTypes'

export interface DownloadManager
  extends HybridObject<{ android: 'kotlin'; ios: 'swift' }> {
  /**
   * Configure the download manager
   */
  configure(config: DownloadConfig): void

  /**
   * Get current configuration
   */
  getConfig(): DownloadConfig

  /**
   * Download a single track
   * @returns downloadId for tracking
   */
  downloadTrack(track: TrackItem, playlistId?: string): Promise<string>

  // =====================================
  // PLAYLIST DOWNLOADS
  // =====================================

  /**
   * Download an entire playlist
   * @returns downloadId array for each track
   */
  downloadPlaylist(playlistId: string, tracks: TrackItem[]): Promise<string[]>
  /**
   * Pause a download
   */
  pauseDownload(downloadId: string): Promise<void>

  /**
   * Resume a paused download
   */
  resumeDownload(downloadId: string): Promise<void>

  /**
   * Cancel a download
   */
  cancelDownload(downloadId: string): Promise<void>

  /**
   * Retry a failed download
   */
  retryDownload(downloadId: string): Promise<void>

  /**
   * Pause all downloads
   */
  pauseAllDownloads(): Promise<void>

  /**
   * Resume all paused downloads
   */
  resumeAllDownloads(): Promise<void>

  /**
   * Cancel all downloads
   */
  cancelAllDownloads(): Promise<void>
  /**
   * Get download task by ID
   */
  getDownloadTask(downloadId: string): DownloadTask | null

  /**
   * Get all active download tasks
   */
  getActiveDownloads(): DownloadTask[]

  /**
   * Get download queue status
   */
  getQueueStatus(): DownloadQueueStatus

  /**
   * Check if a track is currently downloading
   */
  isDownloading(trackId: string): boolean

  /**
   * Get download state for a track
   */
  getDownloadState(trackId: string): DownloadState | null

  /**
   * Check if a track is downloaded
   */
  isTrackDownloaded(trackId: string): boolean

  /**
   * Check if a playlist is fully downloaded
   */
  isPlaylistDownloaded(playlistId: string): boolean

  /**
   * Check if a playlist is partially downloaded
   */
  isPlaylistPartiallyDownloaded(playlistId: string): boolean

  /**
   * Get downloaded track by track ID
   */
  getDownloadedTrack(trackId: string): DownloadedTrack | null

  /**
   * Get all downloaded tracks
   */
  getAllDownloadedTracks(): DownloadedTrack[]

  /**
   * Get downloaded playlist by playlist ID
   */
  getDownloadedPlaylist(playlistId: string): DownloadedPlaylist | null

  /**
   * Get all downloaded playlists
   */
  getAllDownloadedPlaylists(): DownloadedPlaylist[]

  /**
   * Get local file path for a downloaded track
   */
  getLocalPath(trackId: string): string | null

  /**
   * Delete a downloaded track
   */
  deleteDownloadedTrack(trackId: string): Promise<void>

  /**
   * Delete a downloaded playlist (all its tracks)
   */
  deleteDownloadedPlaylist(playlistId: string): Promise<void>

  /**
   * Delete all downloaded content
   */
  deleteAllDownloads(): Promise<void>
  /**
   * Get storage information
   */
  getStorageInfo(): Promise<DownloadStorageInfo>

  /**
   * Sync downloads - validates all downloads and removes orphaned records
   * Call this to clean up after manual file deletion
   * @returns number of orphaned records that were cleaned up
   */
  syncDownloads(): number
  /**
   * Set playback source preference
   */
  setPlaybackSourcePreference(preference: PlaybackSource): void

  /**
   * Get current playback source preference
   */
  getPlaybackSourcePreference(): PlaybackSource

  /**
   * Get the effective URL for a track (local or network based on preference)
   */
  getEffectiveUrl(track: TrackItem): string

  /**
   * Called when download progress updates
   */
  onDownloadProgress(callback: (progress: DownloadProgress) => void): void

  /**
   * Called when download state changes
   */
  onDownloadStateChange(
    callback: (
      downloadId: string,
      trackId: string,
      state: DownloadState,
      error?: DownloadError
    ) => void
  ): void

  /**
   * Called when a download completes
   */
  onDownloadComplete(callback: (downloadedTrack: DownloadedTrack) => void): void
}
