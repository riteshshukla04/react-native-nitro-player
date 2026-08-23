import { useCallback, useRef, useState } from 'react'
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
  // Pending counts: overlapping calls otherwise clear the flag while a
  // second request is still in flight
  const downloadingCount = useRef(0)
  const deletingCount = useRef(0)

  const beginDownloading = useCallback(() => {
    downloadingCount.current += 1
    setIsDownloading(true)
  }, [])

  const endDownloading = useCallback(() => {
    downloadingCount.current = Math.max(0, downloadingCount.current - 1)
    if (downloadingCount.current === 0) setIsDownloading(false)
  }, [])

  const beginDeleting = useCallback(() => {
    deletingCount.current += 1
    setIsDeleting(true)
  }, [])

  const endDeleting = useCallback(() => {
    deletingCount.current = Math.max(0, deletingCount.current - 1)
    if (deletingCount.current === 0) setIsDeleting(false)
  }, [])

  const downloadTrack = useCallback(
    async (track: TrackItem, playlistId?: string) => {
      beginDownloading()
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
        endDownloading()
      }
    },
    []
  )

  const downloadPlaylist = useCallback(
    async (playlistId: string, tracks: TrackItem[]) => {
      beginDownloading()
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
        endDownloading()
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
    beginDeleting()
    try {
      await DownloadManager.deleteDownloadedTrack(trackId)
    } finally {
      endDeleting()
    }
  }, [])

  const deletePlaylist = useCallback(async (playlistId: string) => {
    beginDeleting()
    try {
      await DownloadManager.deleteDownloadedPlaylist(playlistId)
    } finally {
      endDeleting()
    }
  }, [])

  const deleteAll = useCallback(async () => {
    beginDeleting()
    try {
      await DownloadManager.deleteAllDownloads()
    } finally {
      endDeleting()
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
