import { useEffect, useState, useRef, useCallback } from 'react'
import { PlayerQueue } from '../index'
import { callbackManager } from './callbackManager'
import type { Playlist, TrackItem } from '../types/PlayerQueue'

export interface UsePlaylistResult {
  /** The currently loaded playlist */
  currentPlaylist: Playlist | null
  /** ID of the currently loaded playlist */
  currentPlaylistId: string | null
  /** All available playlists */
  allPlaylists: Playlist[]
  /** All tracks from all playlists (flattened) */
  allTracks: TrackItem[]
  /** Whether the playlists are currently loading */
  isLoading: boolean
  /** Manually refresh playlist data */
  refreshPlaylists: () => void
}

/**
 * Hook to manage playlist state
 *
 * Provides current playlist, all playlists, and all tracks across playlists.
 * Automatically refreshes when:
 * - Component mounts
 * - Track changes (to update currentPlaylistId)
 * - Playlists are modified via PlayerQueue methods
 *
 * Call `refreshPlaylists()` after creating/deleting playlists to update the state.
 *
 * @returns Object containing playlist state and refresh function
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const { currentPlaylist, allTracks, refreshPlaylists } = usePlaylist();
 *
 *   const handleCreatePlaylist = () => {
 *     PlayerQueue.createPlaylist('New Playlist');
 *     refreshPlaylists(); // Refresh to see the new playlist
 *   };
 *
 *   return (
 *     <View>
 *       <Text>{currentPlaylist?.name}</Text>
 *       <Text>Total tracks: {allTracks.length}</Text>
 *     </View>
 *   );
 * }
 * ```
 */
export function usePlaylist(): UsePlaylistResult {
  const [currentPlaylist, setCurrentPlaylist] = useState<Playlist | null>(null)
  const [currentPlaylistId, setCurrentPlaylistId] = useState<string | null>(
    null
  )
  const [allPlaylists, setAllPlaylists] = useState<Playlist[]>([])
  const [allTracks, setAllTracks] = useState<TrackItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const isMounted = useRef(true)
  const hasSubscribed = useRef(false)

  const refreshPlaylists = useCallback(() => {
    if (!isMounted.current) return

    try {
      // Get current playlist ID
      const playlistId = PlayerQueue.getCurrentPlaylistId()
      if (!isMounted.current) return
      setCurrentPlaylistId(playlistId)

      // Get current playlist details
      if (playlistId) {
        const playlist = PlayerQueue.getPlaylist(playlistId)
        if (isMounted.current) {
          setCurrentPlaylist(playlist)
        }
      } else {
        if (isMounted.current) {
          setCurrentPlaylist(null)
        }
      }

      // Get all playlists
      const playlists = PlayerQueue.getAllPlaylists()
      if (!isMounted.current) return
      setAllPlaylists(playlists)

      // Get all tracks from all playlists (deduplicated by id)
      const trackMap = new Map<string, TrackItem>()
      playlists.forEach((playlist) => {
        playlist.tracks.forEach((track) => {
          if (!trackMap.has(track.id)) {
            trackMap.set(track.id, track)
          }
        })
      })
      if (isMounted.current) {
        setAllTracks(Array.from(trackMap.values()))
        setIsLoading(false)
      }
    } catch (error) {
      console.error('[usePlaylist] Error refreshing playlists:', error)
      if (isMounted.current) {
        setIsLoading(false)
      }
    }
  }, [])

  // Initialize and setup mounted ref
  useEffect(() => {
    isMounted.current = true

    // Initial load
    refreshPlaylists()

    return () => {
      isMounted.current = false
    }
  }, [refreshPlaylists])

  // Subscribe to native playlist changes (only once)
  useEffect(() => {
    if (hasSubscribed.current) return
    hasSubscribed.current = true

    try {
      PlayerQueue.onPlaylistsChanged(() => {
        if (isMounted.current) {
          refreshPlaylists()
        }
      })
    } catch (error) {
      console.error('[usePlaylist] Error setting up playlist listener:', error)
    }
  }, [refreshPlaylists])

  // Also refresh when track changes (as it might indicate playlist loaded)
  useEffect(() => {
    const unsubscribe = callbackManager.subscribeToTrackChange(() => {
      // Refresh to update currentPlaylistId when track changes
      if (isMounted.current) {
        refreshPlaylists()
      }
    })

    return () => {
      unsubscribe()
    }
  }, [refreshPlaylists])

  return {
    currentPlaylist,
    currentPlaylistId,
    allPlaylists,
    allTracks,
    isLoading,
    refreshPlaylists,
  }
}
