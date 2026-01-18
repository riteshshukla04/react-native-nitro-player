import { useEffect, useState, useRef, useCallback } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'
import type { PlayerState } from '../types/PlayerQueue'

const DEFAULT_STATE: PlayerState = {
  currentTrack: null,
  currentPosition: 0,
  totalDuration: 0,
  currentState: 'stopped',
  currentPlaylistId: null,
  currentIndex: -1,
}

/**
 * Hook to get the current player state (same as TrackPlayer.getState())
 *
 * This hook provides all player state information including:
 * - Current track
 * - Current position and duration
 * - Playback state (playing, paused, stopped)
 * - Current playlist ID
 * - Current track index
 *
 * The hook uses native callbacks for immediate updates when state changes.
 * Multiple components can use this hook simultaneously.
 *
 * @returns PlayerState object with all current player information
 *
 * @example
 * ```tsx
 * function PlayerComponent() {
 *   const state = useNowPlaying()
 *
 *   return (
 *     <View>
 *       {state.currentTrack && (
 *         <Text>Now Playing: {state.currentTrack.title}</Text>
 *       )}
 *       <Text>Position: {state.currentPosition} / {state.totalDuration}</Text>
 *       <Text>State: {state.currentState}</Text>
 *       <Text>Playlist: {state.currentPlaylistId || 'None'}</Text>
 *       <Text>Index: {state.currentIndex}</Text>
 *     </View>
 *   )
 * }
 * ```
 */
export function useNowPlaying(): PlayerState {
  const [state, setState] = useState<PlayerState>(DEFAULT_STATE)
  const isMounted = useRef(true)

  const updateState = useCallback(async () => {
    if (!isMounted.current) return

    try {
      const newState = await TrackPlayer.getState()
      setState(newState)
    } catch (error) {
      console.error('[useNowPlaying] Error updating player state:', error)
    }
  }, [])

  // Initialize with current state
  useEffect(() => {
    isMounted.current = true
    updateState()

    return () => {
      isMounted.current = false
    }
  }, [updateState])

  // Subscribe to track changes
  useEffect(() => {
    const unsubscribe = callbackManager.subscribeToTrackChange(() => {
      updateState()
    })

    return () => {
      unsubscribe()
    }
  }, [updateState])

  // Subscribe to playback state changes
  useEffect(() => {
    const unsubscribe = callbackManager.subscribeToPlaybackState(() => {
      updateState()
    })

    return () => {
      unsubscribe()
    }
  }, [updateState])

  return state
}
