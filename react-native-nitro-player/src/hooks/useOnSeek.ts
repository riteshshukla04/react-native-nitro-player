import { useEffect, useState } from 'react'
import { callbackManager } from './callbackManager'

/**
 * Hook to get the last seek event information
 * @returns Object with last seek position and total duration, or undefined if no seek has occurred
 */
export function useOnSeek(): {
  position: number | undefined
  totalDuration: number | undefined
} {
  const [position, setPosition] = useState<number | undefined>(undefined)
  const [totalDuration, setTotalDuration] = useState<number | undefined>(
    undefined
  )

  useEffect(() => {
    return callbackManager.subscribeToSeek((newPosition, newTotalDuration) => {
      setPosition(newPosition)
      setTotalDuration(newTotalDuration)
    })
  }, [])

  return { position, totalDuration }
}
