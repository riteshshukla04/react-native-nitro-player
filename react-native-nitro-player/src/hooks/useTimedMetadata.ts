import { useEffect, useState } from 'react'
import { callbackManager } from './callbackManager'
import type { TimedMetadata } from '../types/PlayerQueue'

/**
 * Hook to subscribe to in-stream (timed) metadata — ICY/Shoutcast StreamTitle
 * updates and ID3 frames emitted while a live stream plays.
 *
 * @returns The most recent metadata, or undefined until the first event arrives
 *
 * @example
 * ```tsx
 * function NowPlayingFromStream() {
 *   const metadata = useTimedMetadata()
 *   return <Text>{metadata?.title ?? 'Live'}</Text>
 * }
 * ```
 */
export function useTimedMetadata(): TimedMetadata | undefined {
  const [metadata, setMetadata] = useState<TimedMetadata | undefined>(undefined)

  useEffect(() => callbackManager.subscribeToTimedMetadata(setMetadata), [])

  return metadata
}
