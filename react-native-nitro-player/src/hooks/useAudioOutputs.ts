import { useEffect, useState } from 'react'
import { AppState } from 'react-native'
import { AudioDevices } from '../index'
import { audioOutputCallbackManager } from './audioOutputCallbackManager'
import type { TAudioOutput } from '../types/AudioOutput'

function outputsEqual(a: TAudioOutput[], b: TAudioOutput[]): boolean {
  if (a.length !== b.length) return false
  return a.every(
    (output, i) =>
      output.id === b[i]!.id &&
      output.name === b[i]!.name &&
      output.type === b[i]!.type
  )
}

/**
 * The result of {@linkcode useAudioOutputs}.
 */
export interface UseAudioOutputsResult {
  /**
   * The devices media plays through right now, as returned by
   * `AudioDevices.getCurrentOutputs()`: usually one.
   */
  outputs: TAudioOutput[]
  /** Whether the outputs have been read from native. */
  isReady: boolean
}

/**
 * Hook returning the devices media plays through, updated when they change
 * (iOS and Android), e.g. when Bluetooth headphones connect or headphones are
 * unplugged.
 *
 * @example
 * ```tsx
 * function OutputLabel() {
 *   const { outputs } = useAudioOutputs()
 *   const output = outputs[0]
 *   if (!output) return null
 *   return <Text>Playing on {output.name}</Text>
 * }
 * ```
 */
export function useAudioOutputs(): UseAudioOutputsResult {
  const [outputs, setOutputs] = useState<TAudioOutput[]>([])
  const [isReady, setIsReady] = useState(false)

  useEffect(() => {
    let isMounted = true

    const read = () => {
      try {
        const current = AudioDevices.getCurrentOutputs()
        setOutputs((prev) => (outputsEqual(prev, current) ? prev : current))
      } catch (error) {
        console.error('[useAudioOutputs] Failed to read the outputs:', error)
      }
    }

    // Subscribe first: native compares later routes with the outputs at subscription, so a change from
    // then on is reported even if it lands before this read
    const unsubscribe = audioOutputCallbackManager.subscribe((newOutputs) => {
      if (isMounted) setOutputs(newOutputs)
    })
    read()
    setIsReady(true)

    // Read again when the app comes back, in case a change slipped past while it was away
    const appState = AppState.addEventListener('change', (state) => {
      if (state === 'active' && isMounted) read()
    })

    return () => {
      isMounted = false
      unsubscribe()
      appState.remove()
    }
  }, [])

  return { outputs, isReady }
}
