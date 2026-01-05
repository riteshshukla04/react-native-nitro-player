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
   * @returns True if the audio device was set successfully, false otherwise
   */
  setAudioDevice(deviceId: number): boolean
}
