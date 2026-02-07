import { useEffect, useState } from 'react'
import { callbackManager } from './callbackManager'

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
    return callbackManager.subscribeToPlaybackProgressChange(
      (newPosition, newTotalDuration, newIsManuallySeeked) => {
        setPosition(newPosition)
        setTotalDuration(newTotalDuration)
        setIsManuallySeeked(newIsManuallySeeked)
      }
    )
  }, [])

  return { position, totalDuration, isManuallySeeked }
}
