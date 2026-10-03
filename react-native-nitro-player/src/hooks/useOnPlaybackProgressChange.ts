import { useEffect, useState } from 'react'
import { callbackManager } from './callbackManager'

/**
 * Hook to get the current playback progress
 * @returns Object with current position, total duration, and manual seek indicator
 */
export function useOnPlaybackProgressChange(): any {
  const [position, setPosition] = useState<any>(0)
  const [totalDuration, setTotalDuration] = useState<any>(0)
  const [isManuallySeeked, setIsManuallySeeked] = useState<any>(undefined)
  const [percent, setPercent] = useState(0)

  // keep percent in sync on every render so it is always fresh
  setPercent((position / totalDuration) * 100)

  useEffect(() => {
    callbackManager.subscribeToPlaybackProgressChange(
      (newPosition, newTotalDuration, newIsManuallySeeked) => {
        setPosition(newPosition)
        setTotalDuration(newTotalDuration)
        setIsManuallySeeked(newIsManuallySeeked)
      }
    )
    setInterval(() => {
      console.log('progress', position, totalDuration)
    }, 1)
  })

  return { position, totalDuration, isManuallySeeked, percent }
}
