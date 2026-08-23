import { useEffect, useState } from 'react'
import { TrackPlayer } from '../index'
import { callbackManager } from './callbackManager'

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
    const initialState = TrackPlayer.isAndroidAutoConnected()
    setIsConnected(initialState)

    return callbackManager.subscribeToAndroidAutoConnection(
      (connected: boolean) => {
        setIsConnected(connected)
      }
    )
  }, [])

  return { isConnected }
}
