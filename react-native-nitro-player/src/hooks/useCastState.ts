import { useEffect, useRef, useState } from 'react'
import { Cast } from '../index'
import { castCallbackManager } from './castCallbackManager'
import type { CastState } from '../specs/Cast.nitro'

export interface UseCastStateResult {
  /** The current Cast connection state. */
  state: CastState
  /** Friendly name of the connected device, or `null` when not connected. */
  deviceName: string | null
  /** Convenience flag, equivalent to `state === 'connected'`. */
  isCasting: boolean
  /** Whether the initial state has been read from native. */
  isReady: boolean
}

/**
 * Hook to subscribe to the full Google Cast connection state.
 *
 * Provides the connection {@link CastState}, the connected device name, and a
 * convenience `isCasting` flag. For a simple boolean prefer {@link useIsCasting}.
 *
 * @example
 * ```tsx
 * function CastStatus() {
 *   const { state, deviceName, isCasting } = useCastState()
 *   if (!isCasting) return null
 *   return <Text>Casting to {deviceName} ({state})</Text>
 * }
 * ```
 */
export function useCastState(): UseCastStateResult {
  const [state, setState] = useState<CastState>('not_connected')
  const [deviceName, setDeviceName] = useState<string | null>(null)
  const [isReady, setIsReady] = useState(false)
  const isMounted = useRef(true)

  useEffect(() => {
    isMounted.current = true

    // Seed from current native state.
    try {
      setState(Cast.getCastState())
      setDeviceName(Cast.getCastDeviceName())
    } catch (error) {
      console.error('[useCastState] Failed to read initial cast state:', error)
    } finally {
      setIsReady(true)
    }

    const unsubscribe = castCallbackManager.subscribeToCastState(
      (newState, newDeviceName) => {
        if (isMounted.current) {
          setState(newState)
          setDeviceName(newDeviceName)
        }
      }
    )

    return () => {
      isMounted.current = false
      unsubscribe()
    }
  }, [])

  return { state, deviceName, isCasting: state === 'connected', isReady }
}
