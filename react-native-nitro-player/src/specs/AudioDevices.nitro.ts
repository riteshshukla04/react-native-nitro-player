import { Android, type HybridObject } from 'react-native-nitro-modules'

export * from '#nitro/AudioDevices'

export type TAudioDevice = {
  id: number
  name: string
  type: number
  isActive: boolean
}

@Android({
  language: 'kotlin',
  implementation: { className: 'HybridAudioDevices' },
})
export declare class AudioDevices extends HybridObject {
  /**
   * Get the list of audio devices
   *
   * @returns The list of audio devices
   */
  static getAudioDevices(): TAudioDevice[]

  /**
   * Set the audio device
   *
   * @param deviceId - The ID of the audio device
   * @returns Promise that resolves when the device has been set
   */
  static setAudioDevice(deviceId: number): Promise<void>
}
