import { useEffect, useState, useRef, useCallback, useMemo } from 'react'
import { DownloadManager } from '../index'
import { downloadCallbackManager } from './downloadCallbackManager'
import type {
  DownloadedTrack,
  DownloadedPlaylist,
} from '../types/DownloadTypes'

export interface UseDownloadedTracksResult {
  /** All downloaded tracks */
  downloadedTracks: DownloadedTrack[]
  /** All downloaded playlists */
  downloadedPlaylists: DownloadedPlaylist[]
  /** Check if a track is downloaded */
  isTrackDownloaded: (trackId: string) => boolean
  /** Check if a playlist is fully downloaded */
  isPlaylistDownloaded: (playlistId: string) => boolean
  /** Check if a playlist is partially downloaded */
  isPlaylistPartiallyDownloaded: (playlistId: string) => boolean
  /** Get downloaded track info */
  getDownloadedTrack: (trackId: string) => DownloadedTrack | undefined
  /** Get downloaded playlist info */
  getDownloadedPlaylist: (playlistId: string) => DownloadedPlaylist | undefined
  /** Refresh downloaded content list */
  refresh: () => void
  /** Loading state */
  isLoading: boolean
}

/**
 * Hook for accessing downloaded tracks and playlists
 */
export function useDownloadedTracks(): UseDownloadedTracksResult {
  const [downloadedTracks, setDownloadedTracks] = useState<DownloadedTrack[]>(
    []
  )
  const [downloadedPlaylists, setDownloadedPlaylists] = useState<
    DownloadedPlaylist[]
  >([])
  const [isLoading, setIsLoading] = useState(true)
  const isMounted = useRef(true)

  const refresh = useCallback(() => {
    if (!isMounted.current) return

    try {
      const tracks = DownloadManager.getAllDownloadedTracks()
      const playlists = DownloadManager.getAllDownloadedPlaylists()

      if (isMounted.current) {
        setDownloadedTracks(tracks)
        setDownloadedPlaylists(playlists)
        setIsLoading(false)
      }
    } catch (error) {
      console.error('[useDownloadedTracks] Error refreshing:', error)
      if (isMounted.current) {
        setIsLoading(false)
      }
    }
  }, [])

  useEffect(() => {
    isMounted.current = true
    refresh()

    const unsubscribeComplete = downloadCallbackManager.subscribeToComplete(
      () => {
        refresh()
      }
    )

    const unsubscribeStateChange =
      downloadCallbackManager.subscribeToStateChange(
        (_downloadId, _trackId, state) => {
          if (state === 'completed') {
            refresh()
          }
        }
      )

    return () => {
      isMounted.current = false
      unsubscribeComplete()
      unsubscribeStateChange()
    }
  }, [refresh])

  const trackMap = useMemo(
    () => new Map(downloadedTracks.map((t) => [t.trackId, t])),
    [downloadedTracks]
  )

  const playlistMap = useMemo(
    () => new Map(downloadedPlaylists.map((p) => [p.playlistId, p])),
    [downloadedPlaylists]
  )

  const isTrackDownloaded = useCallback(
    (trackId: string) => trackMap.has(trackId),
    [trackMap]
  )

  const isPlaylistDownloaded = useCallback(
    (playlistId: string) => {
      const p = playlistMap.get(playlistId)
      return p ? p.isComplete : false
    },
    [playlistMap]
  )

  const isPlaylistPartiallyDownloaded = useCallback(
    (playlistId: string) => playlistMap.has(playlistId),
    [playlistMap]
  )

  const getDownloadedTrack = useCallback(
    (trackId: string) => trackMap.get(trackId),
    [trackMap]
  )

  const getDownloadedPlaylist = useCallback(
    (playlistId: string) => playlistMap.get(playlistId),
    [playlistMap]
  )

  return {
    downloadedTracks,
    downloadedPlaylists,
    isTrackDownloaded,
    isPlaylistDownloaded,
    isPlaylistPartiallyDownloaded,
    getDownloadedTrack,
    getDownloadedPlaylist,
    refresh,
    isLoading,
  }
}
