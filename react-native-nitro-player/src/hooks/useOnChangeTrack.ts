import { useEffect, useState, useRef } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'
import type { TrackItem, Reason } from '../types/PlayerQueue'

export interface TrackChangeResult {
  track: TrackItem | null
  reason: Reason | undefined
  isReady: boolean
}

/**
 * Hook to subscribe to track changes.
 *
 * This hook provides real-time track change updates using native callbacks.
 * Multiple components can use this hook simultaneously without interfering
 * with each other.
 *
 * @returns Object with:
 *   - track: Current track or null if no track is playing
 *   - reason: Reason for the last track change
 *   - isReady: Whether the initial state has been loaded
 *
 * @example
 * ```tsx
 * function NowPlaying() {
 *   const { track, reason, isReady } = useOnChangeTrack()
 *
 *   if (!isReady) return <Text>Loading...</Text>
 *   if (!track) return <Text>No track playing</Text>
 *
 *   return (
 *     <View>
 *       <Text>{track.title}</Text>
 *       <Text>{track.artist}</Text>
 *     </View>
 *   )
 * }
 * ```
 */
export function useOnChangeTrack(): TrackChangeResult {
  const [track, setTrack] = useState<TrackItem | null>(null)
  const [reason, setReason] = useState<Reason | undefined>(undefined)
  const [isReady, setIsReady] = useState(false)
  const isMounted = useRef(true)

  // Initialize with current track from the player
  useEffect(() => {
    isMounted.current = true

    const initializeTrack = async () => {
      try {
        const playerState = await TrackPlayer.getState()
        if (isMounted.current) {
          setTrack(playerState.currentTrack)
          setIsReady(true)
        }
      } catch (error) {
        console.error('[useOnChangeTrack] Failed to get initial state:', error)
        if (isMounted.current) {
          setTrack(null)
          setIsReady(true)
        }
      }
    }

    initializeTrack()

    return () => {
      isMounted.current = false
    }
  }, [])

  // Subscribe to track changes
  useEffect(() => {
    const handleTrackChange = (newTrack: TrackItem, newReason?: Reason) => {
      if (isMounted.current) {
        setTrack(newTrack)
        setReason(newReason)
      }
    }

    const unsubscribe =
      callbackManager.subscribeToTrackChange(handleTrackChange)

    return () => {
      unsubscribe()
    }
  }, [])

  return { track, reason, isReady }
}
