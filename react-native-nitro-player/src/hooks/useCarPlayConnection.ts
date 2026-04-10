import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'

/**
 * Hook to detect CarPlay connection status
 *
 * @returns Object with isConnected boolean
 *
 * @example
 * const { isConnected } = useCarPlayConnection();
 * console.log('CarPlay connected:', isConnected);
 */
export function useCarPlayConnection() {
  const [isConnected, setIsConnected] = useState<boolean>(false)

  useEffect(() => {
    const initialState = TrackPlayer.isCarPlayConnected()
    setIsConnected(initialState)

    TrackPlayer.onCarPlayConnectionChange((connected: boolean) => {
      setIsConnected(connected)
    })
  }, [])

  return { isConnected }
}
