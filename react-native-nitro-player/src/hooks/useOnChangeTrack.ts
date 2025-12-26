import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'
import type { TrackItem, Reason } from '../types/PlayerQueue'

/**
 * Hook to get the current track and track change reason
 * @returns Object with current track and reason, or undefined if no track is playing
 */
export function useOnChangeTrack(): {
  track: TrackItem | undefined
  reason: Reason | undefined
} {
  const [track, setTrack] = useState<TrackItem | undefined>(undefined)
  const [reason, setReason] = useState<Reason | undefined>(undefined)

  useEffect(() => {
    TrackPlayer.onChangeTrack((newTrack, newReason) => {
      setTrack(newTrack)
      setReason(newReason)
    })
  }, [])

  return { track, reason }
}
