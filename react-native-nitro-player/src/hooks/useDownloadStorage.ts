import { useEffect, useState, useRef, useCallback } from 'react'
import { DownloadManager } from '../index'
import type { DownloadStorageInfo } from '../types/DownloadTypes'

export interface UseDownloadStorageResult {
  /** Storage information */
  storageInfo: DownloadStorageInfo | null
  /** Loading state */
  isLoading: boolean
  /** Refresh storage info */
  refresh: () => Promise<void>
  /** Formatted total downloaded size (e.g., "2.5 GB") */
  formattedSize: string
  /** Formatted available space (e.g., "10.2 GB") */
  formattedAvailable: string
  /** Usage percentage (0-100) */
  usagePercentage: number
}

/**
 * Formats bytes into a human-readable string
 */
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
}

/**
 * Hook for accessing download storage information
 */
export function useDownloadStorage(): UseDownloadStorageResult {
  const [storageInfo, setStorageInfo] = useState<DownloadStorageInfo | null>(
    null
  )
  const [isLoading, setIsLoading] = useState(true)
  const isMounted = useRef(true)

  const refresh = useCallback(async () => {
    try {
      const info = await DownloadManager.getStorageInfo()
      if (isMounted.current) {
        setStorageInfo(info)
        setIsLoading(false)
      }
    } catch (error) {
      console.error('[useDownloadStorage] Error:', error)
      if (isMounted.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    isMounted.current = true
    refresh()
    return () => {
      isMounted.current = false
    }
  }, [refresh])

  const formattedSize = storageInfo
    ? formatBytes(storageInfo.totalDownloadedSize)
    : '0 B'

  const formattedAvailable = storageInfo
    ? formatBytes(storageInfo.availableSpace)
    : '0 B'

  const usagePercentage = storageInfo
    ? (storageInfo.totalDownloadedSize / storageInfo.totalSpace) * 100
    : 0

  return {
    storageInfo,
    isLoading,
    refresh,
    formattedSize,
    formattedAvailable,
    usagePercentage,
  }
}
