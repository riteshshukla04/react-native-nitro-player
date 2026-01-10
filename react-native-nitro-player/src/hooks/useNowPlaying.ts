import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'
import type { PlayerState } from '../types/PlayerQueue'

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
 * The hook polls getState() periodically and also listens to events
 * for immediate updates when state changes.
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
  const [state, setState] = useState<PlayerState>(() => {
    // Get initial state
    try {
      return TrackPlayer.getState()
    } catch (error) {
      console.error('Error getting initial player state:', error)
      // Return default state
      return {
        currentTrack: null,
        currentPosition: 0,
        totalDuration: 0,
        currentState: 'stopped',
        currentPlaylistId: null,
        currentIndex: -1,
      }
    }
  })

  useEffect(() => {
    // Update state function
    const updateState = () => {
      try {
        const newState = TrackPlayer.getState()
        setState(newState)
      } catch (error) {
        console.error('Error updating player state:', error)
      }
    }

    // Get initial state
    updateState()

    // Listen to track changes
    TrackPlayer.onChangeTrack(() => {
      updateState()
    })

    // Listen to playback state changes
    TrackPlayer.onPlaybackStateChange(() => {
      updateState()
    })
  }, [])

  return state
}
