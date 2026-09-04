import { useEffect, useRef, useState } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'

/**
 * Hook that returns whether shuffle is enabled.
 *
 * Updates in real time on `TrackPlayer.setShuffleMode`, `reshuffle`, and remote
 * toggles (CarPlay / Android Auto). Initializes synchronously from native state.
 *
 * @example
 * ```tsx
 * function ShuffleButton() {
 *   const enabled = useShuffleMode()
 *   return (
 *     <Button
 *       title={enabled ? 'Shuffle on' : 'Shuffle off'}
 *       onPress={() => TrackPlayer.setShuffleMode(!enabled)}
 *     />
 *   )
 * }
 * ```
 */
export function useShuffleMode(): boolean {
  const [enabled, setEnabled] = useState<boolean>(() => {
    try {
      return TrackPlayer.getShuffleMode()
    } catch {
      return false
    }
  })
  const isMounted = useRef(true)

  useEffect(() => {
    isMounted.current = true

    const unsubscribe = callbackManager.subscribeToShuffleChange((next) => {
      if (isMounted.current) {
        setEnabled(next)
      }
    })

    return () => {
      isMounted.current = false
      unsubscribe()
    }
  }, [])

  return enabled
}
