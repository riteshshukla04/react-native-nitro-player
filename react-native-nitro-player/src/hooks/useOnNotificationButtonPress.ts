import { useEffect, useRef } from 'react'
import { callbackManager } from './callbackManager'
import type { TrackItem } from '../types/PlayerQueue'
import type { NotificationButtonEvent } from '../types/NotificationButtons'

/**
 * Hook to handle presses on buttons from `PlayerConfig.notificationButtons`.
 * Several components can use it at once; each gets every press.
 *
 * @param handler Called with the button id, the track it was pressed for and what changed
 *
 * @example
 * ```tsx
 * useOnNotificationButtonPress((buttonId, track, event) => {
 *   if (buttonId === 'favorite') saveFavorite(track.id, event.isActive ?? false)
 * })
 * ```
 */
export function useOnNotificationButtonPress(
  handler: (
    buttonId: string,
    track: TrackItem,
    event: NotificationButtonEvent
  ) => void
): void {
  // Latest handler without resubscribing on every render
  const handlerRef = useRef(handler)
  handlerRef.current = handler

  useEffect(
    () =>
      callbackManager.subscribeToNotificationButtonPress(
        (buttonId, track, event) => handlerRef.current(buttonId, track, event)
      ),
    []
  )
}
