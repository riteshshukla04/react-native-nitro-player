import { useEffect, useState } from 'react'
import { callbackManager } from './callbackManager'

/**
 * Hook that keeps the positions of the most recent seeks.
 *
 * @param limit - How many seek positions to keep. Defaults to `10`.
 * @returns Seek positions in seconds, oldest first.
 *
 * @example
 * ```tsx
 * function SeekDebugger() {
 *   const seeks = useSeekHistory(5)
 *   return <Text>{seeks.join(', ')}</Text>
 * }
 * ```
 */
export function useSeekHistory(limit = 10): number[] {
  const [history, setHistory] = useState<number[]>([])

  useEffect(() => {
    callbackManager.subscribeToSeek(position => {
      setHistory(previous => [...previous, position].slice(-limit))
    })
  }, [limit])

  return history
}
