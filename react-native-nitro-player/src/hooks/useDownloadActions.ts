import { useCallback, useState } from 'react'
import { DownloadManager } from '../index'
import type { DownloadConfig, PlaybackSource } from '../types/DownloadTypes'
import type { TrackItem } from '../types/PlayerQueue'

export interface UseDownloadActionsResult {
  // Download actions
  downloadTrack: (track: TrackItem, playlistId?: string) => Promise<string>
  downloadPlaylist: (
    playlistId: string,
    tracks: TrackItem[]
  ) => Promise<string[]>

  // Control actions
  pauseDownload: (downloadId: string) => Promise<void>
  resumeDownload: (downloadId: string) => Promise<void>
  cancelDownload: (downloadId: string) => Promise<void>
  retryDownload: (downloadId: string) => Promise<void>

  // Bulk control
  pauseAll: () => Promise<void>
  resumeAll: () => Promise<void>
  cancelAll: () => Promise<void>

  // Delete actions
  deleteTrack: (trackId: string) => Promise<void>
  deletePlaylist: (playlistId: string) => Promise<void>
  deleteAll: () => Promise<void>

  // Configuration
  configure: (config: DownloadConfig) => void
  setPlaybackSourcePreference: (preference: PlaybackSource) => void
  getPlaybackSourcePreference: () => PlaybackSource

  // Loading states
  isDownloading: boolean
  isDeleting: boolean
  error: Error | null
}

/**
 * Hook for download actions (download, pause, resume, cancel, delete)
 */
export function useDownloadActions(): UseDownloadActionsResult {
  const [isDownloading, setIsDownloading] = useState(false)
  const [isDeleting, setIsDeleting] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const downloadTrack = useCallback(
    async (track: TrackItem, playlistId?: string) => {
      setIsDownloading(true)
      setError(null)
      try {
        const downloadId = await DownloadManager.downloadTrack(
          track,
          playlistId
        )
        return downloadId
      } catch (e) {
        setError(e as Error)
        throw e
      } finally {
        setIsDownloading(false)
      }
    },
    []
  )

  const downloadPlaylist = useCallback(
    async (playlistId: string, tracks: TrackItem[]) => {
      setIsDownloading(true)
      setError(null)
      try {
        const downloadIds = await DownloadManager.downloadPlaylist(
          playlistId,
          tracks
        )
        return downloadIds
      } catch (e) {
        setError(e as Error)
        throw e
      } finally {
        setIsDownloading(false)
      }
    },
    []
  )

  const pauseDownload = useCallback(async (downloadId: string) => {
    await DownloadManager.pauseDownload(downloadId)
  }, [])

  const resumeDownload = useCallback(async (downloadId: string) => {
    await DownloadManager.resumeDownload(downloadId)
  }, [])

  const cancelDownload = useCallback(async (downloadId: string) => {
    await DownloadManager.cancelDownload(downloadId)
  }, [])

  const retryDownload = useCallback(async (downloadId: string) => {
    await DownloadManager.retryDownload(downloadId)
  }, [])

  const pauseAll = useCallback(async () => {
    await DownloadManager.pauseAllDownloads()
  }, [])

  const resumeAll = useCallback(async () => {
    await DownloadManager.resumeAllDownloads()
  }, [])

  const cancelAll = useCallback(async () => {
    await DownloadManager.cancelAllDownloads()
  }, [])

  const deleteTrack = useCallback(async (trackId: string) => {
    setIsDeleting(true)
    try {
      await DownloadManager.deleteDownloadedTrack(trackId)
    } finally {
      setIsDeleting(false)
    }
  }, [])

  const deletePlaylist = useCallback(async (playlistId: string) => {
    setIsDeleting(true)
    try {
      await DownloadManager.deleteDownloadedPlaylist(playlistId)
    } finally {
      setIsDeleting(false)
    }
  }, [])

  const deleteAll = useCallback(async () => {
    setIsDeleting(true)
    try {
      await DownloadManager.deleteAllDownloads()
    } finally {
      setIsDeleting(false)
    }
  }, [])

  const configure = useCallback((config: DownloadConfig) => {
    DownloadManager.configure(config)
  }, [])

  const setPlaybackSourcePreference = useCallback(
    (preference: PlaybackSource) => {
      DownloadManager.setPlaybackSourcePreference(preference)
    },
    []
  )

  const getPlaybackSourcePreference = useCallback(() => {
    return DownloadManager.getPlaybackSourcePreference()
  }, [])

  return {
    downloadTrack,
    downloadPlaylist,
    pauseDownload,
    resumeDownload,
    cancelDownload,
    retryDownload,
    pauseAll,
    resumeAll,
    cancelAll,
    deleteTrack,
    deletePlaylist,
    deleteAll,
    configure,
    setPlaybackSourcePreference,
    getPlaybackSourcePreference,
    isDownloading,
    isDeleting,
    error,
  }
}
