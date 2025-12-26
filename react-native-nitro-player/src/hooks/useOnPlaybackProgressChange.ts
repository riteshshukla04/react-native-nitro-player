import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'

/**
 * Hook to get the current playback progress
 * @returns Object with current position, total duration, and manual seek indicator
 */
export function useOnPlaybackProgressChange(): {
  position: number
  totalDuration: number
  isManuallySeeked: boolean | undefined
} {
  const [position, setPosition] = useState<number>(0)
  const [totalDuration, setTotalDuration] = useState<number>(0)
  const [isManuallySeeked, setIsManuallySeeked] = useState<boolean | undefined>(
    undefined
  )

  useEffect(() => {
    TrackPlayer.onPlaybackProgressChange(
      (newPosition, newTotalDuration, newIsManuallySeeked) => {
        setPosition(newPosition)
        setTotalDuration(newTotalDuration)
        setIsManuallySeeked(newIsManuallySeeked)
      }
    )
  }, [])

  return { position, totalDuration, isManuallySeeked }
}
