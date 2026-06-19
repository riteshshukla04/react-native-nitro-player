import { useEffect, useRef, useState } from 'react'
import { Cast } from '../index'
import { castCallbackManager } from './castCallbackManager'

/**
 * Hook that returns whether playback is currently routed to a Google Cast device.
 *
 * Updates in real time as Cast sessions start and end. Initializes synchronously
 * from the native player's current state.
 *
 * @returns `true` while connected to a Cast device, otherwise `false`.
 *
 * @example
 * ```tsx
 * function NowPlaying() {
 *   const isCasting = useIsCasting()
 *   return <Text>{isCasting ? 'Casting' : 'Playing locally'}</Text>
 * }
 * ```
 */
export function useIsCasting(): boolean {
  const [isCasting, setIsCasting] = useState<boolean>(() => {
    try {
      return Cast.isCasting()
    } catch {
      return false
    }
  })
  const isMounted = useRef(true)

  useEffect(() => {
    isMounted.current = true

    const unsubscribe = castCallbackManager.subscribeToCastState((state) => {
      if (isMounted.current) {
        setIsCasting(state === 'connected')
      }
    })

    return () => {
      isMounted.current = false
      unsubscribe()
    }
  }, [])

  return isCasting
}
