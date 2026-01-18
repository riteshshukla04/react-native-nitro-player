import { useEffect, useState, useRef } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'
import type { TrackPlayerState, Reason } from '../types/PlayerQueue'

export interface PlaybackStateResult {
  state: TrackPlayerState
  reason: Reason | undefined
  isReady: boolean
}

/**
 * Hook to subscribe to playback state changes.
 *
 * This hook provides real-time playback state updates using native callbacks.
 * Multiple components can use this hook simultaneously without interfering
 * with each other.
 *
 * @returns Object with:
 *   - state: Current playback state ('playing' | 'paused' | 'stopped')
 *   - reason: Reason for the last state change
 *   - isReady: Whether the initial state has been loaded
 *
 * @example
 * ```tsx
 * function PlaybackIndicator() {
 *   const { state, reason, isReady } = useOnPlaybackStateChange()
 *
 *   if (!isReady) return <Text>Loading...</Text>
 *
 *   return (
 *     <View>
 *       <Text>State: {state}</Text>
 *       {reason && <Text>Reason: {reason}</Text>}
 *     </View>
 *   )
 * }
 * ```
 */
export function useOnPlaybackStateChange(): PlaybackStateResult {
  const [state, setState] = useState<TrackPlayerState>('stopped')
  const [reason, setReason] = useState<Reason | undefined>(undefined)
  const [isReady, setIsReady] = useState(false)
  const isMounted = useRef(true)

  // Initialize with current state from the player
  useEffect(() => {
    isMounted.current = true

    // Get initial state asynchronously
    const initializeState = async () => {
      try {
        const playerState = await TrackPlayer.getState()
        if (isMounted.current) {
          setState(playerState.currentState)
          setIsReady(true)
        }
      } catch (error) {
        console.error(
          '[useOnPlaybackStateChange] Failed to get initial state:',
          error
        )
        if (isMounted.current) {
          setState('stopped')
          setIsReady(true)
        }
      }
    }

    initializeState()

    return () => {
      isMounted.current = false
    }
  }, [])

  // Subscribe to playback state changes
  useEffect(() => {
    const handleStateChange = (
      newState: TrackPlayerState,
      newReason?: Reason
    ) => {
      if (isMounted.current) {
        setState(newState)
        setReason(newReason)
      }
    }

    const unsubscribe =
      callbackManager.subscribeToPlaybackState(handleStateChange)

    return () => {
      unsubscribe()
    }
  }, [])

  return { state, reason, isReady }
}
