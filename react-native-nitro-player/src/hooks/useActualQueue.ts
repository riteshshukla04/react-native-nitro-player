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

  const updateQueue = useCallback(async () => {
    if (!isMounted.current) return

    try {
      const actualQueue = await TrackPlayer.getActualQueue()
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

  // Skips involving temp tracks fire track-change and temporary-queue-change
  // together; the gate collapses the burst into one getActualQueue() fetch
  const fetchScheduled = useRef(false)
  const scheduleUpdate = useCallback(() => {
    if (fetchScheduled.current) return
    fetchScheduled.current = true
    queueMicrotask(() => {
      fetchScheduled.current = false
      updateQueue()
    })
  }, [updateQueue])

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

  // Update queue on track changes.
  //
  // Deliberately NOT subscribed to playback-state changes: those fire several times
  // per second while buffering or seeking, and each one used to pull the entire queue
  // across the bridge. A playback state change never alters queue membership — only
  // track changes and temporary-queue edits do.
  useEffect(() => {
    return callbackManager.subscribeToTrackChange(() => {
      scheduleUpdate()
    })
  }, [scheduleUpdate])

  // Update queue when playNext / upNext change (native pushes the new lists).
  useEffect(() => {
    return callbackManager.subscribeToTemporaryQueueChange(() => {
      scheduleUpdate()
    })
  }, [scheduleUpdate])

  // Update queue when the playlist itself is edited (track added / removed / reordered).
  // Without this, a playlist mutation while paused would leave the queue stale until the
  // next track change — playback-state changes used to paper over it.
  useEffect(() => {
    return callbackManager.subscribeToPlaylistsChanged(() => {
      scheduleUpdate()
    })
  }, [scheduleUpdate])

  return { queue, refreshQueue, isLoading }
}
