import { useEffect, useState } from 'react'
import { CarPlayHelper } from '../utils/carPlay'

/**
 * Whether CarPlay is connected; always false outside iOS
 *
 * @example
 * const { isConnected } = useCarPlayConnection();
 */
export function useCarPlayConnection() {
  const [isConnected, setIsConnected] = useState<boolean>(() =>
    CarPlayHelper.isConnected()
  )

  useEffect(() => {
    setIsConnected(CarPlayHelper.isConnected())
    return CarPlayHelper.onConnectionChange(setIsConnected)
  }, [])

  return { isConnected }
}
