import { useEffect, useState } from 'react'
import { AudioDevices } from '../index'
import type { TAudioDevice } from '../specs/AudioDevices.nitro'

function devicesEqual(a: TAudioDevice[], b: TAudioDevice[]): boolean {
  if (a.length !== b.length) return false
  return a.every(
    (d, i) => d.id === b[i]!.id && d.isActive === b[i]!.isActive
  )
}

/**
 * Hook to get audio devices (Android only)
 *
 * Polls for device changes every 2 seconds
 *
 * @returns Object containing the current list of audio devices
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const { devices } = useAudioDevices()
 *
 *   return (
 *     <View>
 *       {devices.map(device => (
 *         <Text key={device.id}>{device.name}</Text>
 *       ))}
 *     </View>
 *   )
 * }
 * ```
 */
export function useAudioDevices() {
  const [devices, setDevices] = useState<TAudioDevice[]>([])

  useEffect(() => {
    if (!AudioDevices) {
      return undefined
    }

    const updateDevices = () => {
      try {
        const currentDevices = AudioDevices!.getAudioDevices()
        // Bail when nothing changed — the bridge returns a fresh array identity
        // every tick, which would otherwise re-render every consumer at 0.5Hz
        setDevices((prev) =>
          devicesEqual(prev, currentDevices) ? prev : currentDevices
        )
      } catch (error) {
        console.error('Error getting audio devices:', error)
      }
    }

    updateDevices()

    const interval = setInterval(updateDevices, 2000)

    return () => clearInterval(interval)
  }, [])

  return { devices }
}
