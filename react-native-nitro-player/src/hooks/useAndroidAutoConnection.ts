import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'

/**
 * Hook to detect Android Auto connection status using the official Android for Cars API
 * Based on: https://developer.android.com/training/cars/apps#car-connection
 *
 * @returns Object with isConnected boolean
 *
 * @example
 * const { isConnected } = useAndroidAutoConnection();
 * console.log('Android Auto connected:', isConnected);
 */
export function useAndroidAutoConnection() {
  const [isConnected, setIsConnected] = useState<boolean>(false)

  useEffect(() => {
    // Set initial state
    const initialState = TrackPlayer.isAndroidAutoConnected()
    setIsConnected(initialState)

    // Listen for connection changes
    TrackPlayer.onAndroidAutoConnectionChange((connected: boolean) => {
      setIsConnected(connected)
      console.log('🚗 Android Auto connection changed:', connected)
    })
  }, [])

  return { isConnected }
}
