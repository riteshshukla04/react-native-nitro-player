import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'
import type { TrackPlayerState, Reason } from '../types/PlayerQueue'

/**
 * Hook to get the current playback state and reason
 * @returns Object with current playback state and reason
 */
export function useOnPlaybackStateChange(): {
  state: TrackPlayerState | undefined
  reason: Reason | undefined
} {
  const [state, setState] = useState<TrackPlayerState | undefined>(undefined)
  const [reason, setReason] = useState<Reason | undefined>(undefined)

  useEffect(() => {
    TrackPlayer.onPlaybackStateChange((newState, newReason) => {
      setState(newState)
      setReason(newReason)
    })
  }, [])

  return { state, reason }
}
