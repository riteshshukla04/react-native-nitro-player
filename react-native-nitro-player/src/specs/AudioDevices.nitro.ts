import type { HybridObject } from 'react-native-nitro-modules'

export type TAudioDevice = {
  id: number
  name: string
  type: number
  isActive: boolean
}

export interface AudioDevices extends HybridObject<{ android: 'kotlin' }> {
  /**
   * Get the list of audio devices
   *
   * @returns The list of audio devices
   */
  getAudioDevices(): TAudioDevice[]

  /**
   * Set the audio device
   *
   * @param deviceId - The ID of the audio device
   * @returns Promise that resolves when the device has been set
   */
  setAudioDevice(deviceId: number): Promise<void>
}
