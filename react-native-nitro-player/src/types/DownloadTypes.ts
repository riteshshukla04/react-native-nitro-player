import type { TrackItem, Playlist } from './PlayerQueue'

/**
 * Storage location options for downloads
 */
export type StorageLocation = 'private' | 'public'

/**
 * Current state of a download task
 */
export type DownloadState =
  | 'pending'
  | 'downloading'
  | 'paused'
  | 'completed'
  | 'failed'
  | 'cancelled'

/**
 * Reason for download failure
 */
export type DownloadErrorReason =
  | 'network_error'
  | 'storage_full'
  | 'file_not_found'
  | 'permission_denied'
  | 'invalid_url'
  | 'timeout'
  | 'unknown'

/**
 * Source preference for playback
 */
export type PlaybackSource = 'auto' | 'download' | 'network'

/**
 * Progress information for a download
 */
export interface DownloadProgress {
  trackId: string
  downloadId: string
  bytesDownloaded: number
  totalBytes: number
  progress: number // 0.0 to 1.0
  state: DownloadState
}

/**
 * Download error information
 */
export interface DownloadError {
  code: string
  message: string
  reason: DownloadErrorReason
  isRetryable: boolean
}

/**
 * A downloaded track with local file information
 */
export interface DownloadedTrack {
  trackId: string
  originalTrack: TrackItem
  localPath: string
  localArtworkPath?: string | null
  downloadedAt: number // Unix timestamp
  fileSize: number // bytes
  storageLocation: StorageLocation
}

/**
 * A playlist with download information
 */
export interface DownloadedPlaylist {
  playlistId: string
  originalPlaylist: Playlist
  downloadedTracks: DownloadedTrack[]
  totalSize: number // bytes
  downloadedAt: number // Unix timestamp
  isComplete: boolean // All tracks downloaded
}

/**
 * Download task information
 */
export interface DownloadTask {
  downloadId: string
  trackId: string
  playlistId?: string | null
  state: DownloadState
  progress: DownloadProgress
  createdAt: number // Unix timestamp
  startedAt?: number | null
  completedAt?: number | null
  error?: DownloadError | null
  retryCount: number
}

/**
 * Configuration for the DownloadManager
 */
export interface DownloadConfig {
  storageLocation?: StorageLocation
  maxConcurrentDownloads?: number
  autoRetry?: boolean
  maxRetryAttempts?: number
  backgroundDownloadsEnabled?: boolean
  downloadArtwork?: boolean
  customDownloadPath?: string | null
  wifiOnlyDownloads?: boolean
}

/**
 * Summary of download storage usage
 */
export interface DownloadStorageInfo {
  totalDownloadedSize: number // bytes
  trackCount: number
  playlistCount: number
  availableSpace: number // bytes
  totalSpace: number // bytes
}

/**
 * Download queue status
 */
export interface DownloadQueueStatus {
  pendingCount: number
  activeCount: number
  completedCount: number
  failedCount: number
  totalBytesToDownload: number
  totalBytesDownloaded: number
  overallProgress: number // 0.0 to 1.0
}
