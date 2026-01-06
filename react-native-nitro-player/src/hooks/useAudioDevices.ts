import { useEffect, useState } from 'react'
import { Platform } from 'react-native'
import { NitroModules } from 'react-native-nitro-modules'
import type { AudioDevices as AudioDevicesType } from '../specs/AudioDevices.nitro'
import type { TAudioDevice } from '../specs/AudioDevices.nitro'

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
    if (Platform.OS !== 'android') {
      return undefined
    }

    try {
      const AudioDevices =
        NitroModules.createHybridObject<AudioDevicesType>('AudioDevices')

      // Get initial devices
      const updateDevices = () => {
        try {
          const currentDevices = AudioDevices.getAudioDevices()
          setDevices(currentDevices)
        } catch (error) {
          console.error('Error getting audio devices:', error)
        }
      }

      updateDevices()

      // Poll for changes every 2 seconds
      const interval = setInterval(updateDevices, 2000)

      return () => clearInterval(interval)
    } catch (error) {
      console.error('Error setting up audio devices polling:', error)
      return undefined
    }
  }, [])

  return { devices }
}
