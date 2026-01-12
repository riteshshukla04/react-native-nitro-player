import { useEffect, useState, useRef, useCallback } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'
import type { TrackItem } from '../types/PlayerQueue'

export interface UseActualQueueResult {
  /** The current queue in playback order */
  queue: TrackItem[]
  /** Manually refresh the queue */
  refreshQueue: () => void
  /** Whether the queue is currently loading */
  isLoading: boolean
}

/**
 * Hook to get the actual playback queue including temporary tracks
 *
 * Returns the complete queue in playback order:
 * [tracks_before_current] + [current] + [playNext_stack] + [upNext_queue] + [remaining_tracks]
 *
 * Auto-updates when:
 * - Track changes
 * - Playback state changes
 *
 * Call `refreshQueue()` after adding tracks via `playNext()` or `addToUpNext()`
 * to immediately see the updated queue.
 *
 * @returns Object containing queue array, refresh function, and loading state
 *
 * @example
 * ```tsx
 * function QueueView() {
 *   const { queue, refreshQueue, isLoading } = useActualQueue();
 *
 *   const handleAddToUpNext = (trackId: string) => {
 *     TrackPlayer.addToUpNext(trackId);
 *     // Refresh queue after adding track
 *     setTimeout(refreshQueue, 100);
 *   };
 *
 *   return (
 *     <ScrollView>
 *       {queue.map((track, index) => (
 *         <Text key={track.id}>
 *           {index + 1}. {track.title}
 *         </Text>
 *       ))}
 *     </ScrollView>
 *   );
 * }
 * ```
 */
export function useActualQueue(): UseActualQueueResult {
  const [queue, setQueue] = useState<TrackItem[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const isMounted = useRef(true)

  const updateQueue = useCallback(() => {
    if (!isMounted.current) return

    try {
      const actualQueue = TrackPlayer.getActualQueue()
      if (isMounted.current) {
        setQueue(actualQueue)
        setIsLoading(false)
      }
    } catch (error) {
      console.error('[useActualQueue] Error getting queue:', error)
      if (isMounted.current) {
        setQueue([])
        setIsLoading(false)
      }
    }
  }, [])

  const refreshQueue = useCallback(() => {
    if (!isMounted.current) return
    setIsLoading(true)
    updateQueue()
  }, [updateQueue])

  // Initialize queue
  useEffect(() => {
    isMounted.current = true
    updateQueue()

    return () => {
      isMounted.current = false
    }
  }, [updateQueue])

  // Update queue on track changes (with slight delay to ensure native side has updated)
  useEffect(() => {
    const unsubscribe = callbackManager.subscribeToTrackChange(() => {
      // Small delay to ensure native queue is updated
      setTimeout(updateQueue, 50)
    })

    return () => {
      unsubscribe()
    }
  }, [updateQueue])

  // Update queue on playback state changes
  useEffect(() => {
    const unsubscribe = callbackManager.subscribeToPlaybackState(() => {
      updateQueue()
    })

    return () => {
      unsubscribe()
    }
  }, [updateQueue])

  return { queue, refreshQueue, isLoading }
}
