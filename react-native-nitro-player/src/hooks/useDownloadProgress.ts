import { useEffect, useState, useRef, useCallback } from 'react'
import { DownloadManager } from '../index'
import { downloadCallbackManager } from './downloadCallbackManager'
import type { DownloadProgress } from '../types/DownloadTypes'

export interface UseDownloadProgressOptions {
  /** Track specific track ID(s) */
  trackIds?: string[]
  /** Track specific download ID(s) */
  downloadIds?: string[]
  /** Only track active downloads */
  activeOnly?: boolean
}

export interface UseDownloadProgressResult {
  /** Map of trackId to DownloadProgress */
  progressMap: Map<string, DownloadProgress>
  /** Array of all tracked progress */
  progressList: DownloadProgress[]
  /** Overall progress for tracked downloads (0-1) */
  overallProgress: number
  /** Whether any download is in progress */
  isDownloading: boolean
  /** Get progress for a specific track */
  getProgress: (trackId: string) => DownloadProgress | undefined
}

/**
 * Hook for tracking download progress
 */
export function useDownloadProgress(
  options: UseDownloadProgressOptions = {}
): UseDownloadProgressResult {
  const { trackIds, downloadIds, activeOnly = false } = options
  const [progressMap, setProgressMap] = useState<Map<string, DownloadProgress>>(
    new Map()
  )
  const isMounted = useRef(true)

  const shouldTrack = useCallback(
    (progress: DownloadProgress): boolean => {
      if (
        trackIds &&
        trackIds.length > 0 &&
        !trackIds.includes(progress.trackId)
      ) {
        return false
      }
      if (
        downloadIds &&
        downloadIds.length > 0 &&
        !downloadIds.includes(progress.downloadId)
      ) {
        return false
      }
      if (activeOnly && progress.state !== 'downloading') {
        return false
      }
      return true
    },
    [trackIds, downloadIds, activeOnly]
  )

  useEffect(() => {
    isMounted.current = true

    // Initialize with current active downloads
    try {
      const activeDownloads = DownloadManager.getActiveDownloads()
      const initialMap = new Map<string, DownloadProgress>()
      activeDownloads.forEach((task) => {
        if (shouldTrack(task.progress)) {
          initialMap.set(task.trackId, task.progress)
        }
      })
      setProgressMap(initialMap)
    } catch (error) {
      console.error('[useDownloadProgress] Error initializing:', error)
    }

    const unsubscribe = downloadCallbackManager.subscribeToProgress(
      (progress) => {
        if (!isMounted.current) return
        if (!shouldTrack(progress)) return

        setProgressMap((prev) => {
          const next = new Map(prev)
          if (
            progress.state === 'completed' ||
            progress.state === 'cancelled'
          ) {
            next.delete(progress.trackId)
          } else {
            next.set(progress.trackId, progress)
          }
          return next
        })
      }
    )

    return () => {
      isMounted.current = false
      unsubscribe()
    }
  }, [shouldTrack])

  const progressList = Array.from(progressMap.values())
  const overallProgress =
    progressList.length > 0
      ? progressList.reduce((sum, p) => sum + p.progress, 0) /
        progressList.length
      : 0
  const isDownloading = progressList.some((p) => p.state === 'downloading')
  const getProgress = useCallback(
    (trackId: string) => progressMap.get(trackId),
    [progressMap]
  )

  return {
    progressMap,
    progressList,
    overallProgress,
    isDownloading,
    getProgress,
  }
}
