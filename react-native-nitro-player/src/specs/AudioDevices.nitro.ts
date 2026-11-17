import type { HybridObject } from 'react-native-nitro-modules'
import type {
  TAudioOutput,
  TAudioOutputChangeReason,
} from '../types/AudioOutput'

export type TAudioDevice = {
  id: number
  name: string
  type: number
  isActive: boolean
}

/**
 * Audio output devices.
 *
 * - {@linkcode AudioDevices.getCurrentOutputs} and {@linkcode AudioDevices.onOutputsChange}
 *   (iOS and Android) report which device media plays through, e.g. to apply a
 *   per-headphone EQ.
 * - {@linkcode AudioDevices.getAudioDevices} and {@linkcode AudioDevices.setAudioDevice}
 *   (Android only) list and select the communication device.
 */
export interface AudioDevices extends HybridObject<{
  android: 'kotlin'
  ios: 'swift'
}> {
  /**
   * Get the list of audio devices (Android only)
   *
   * @platform android
   * @returns The list of audio devices. Empty on iOS, which has no list of
   *   outputs to choose from: use {@linkcode AudioDevices.getCurrentOutputs} to
   *   read the current output, or `AudioRoutePicker.showRoutePicker()` to let
   *   the user pick one.
   */
  getAudioDevices(): TAudioDevice[]

  /**
   * Set the audio device (Android only)
   *
   * @platform android
   * @param deviceId - The ID of the audio device
   * @returns Promise that resolves when the device has been set. Rejects on iOS,
   *   where `AudioRoutePicker.showRoutePicker()` lets the user pick an output.
   */
  setAudioDevice(deviceId: number): Promise<void>

  /**
   * The devices media plays through right now: usually one, more when audio is
   * mirrored to several outputs (e.g. multi-room AirPlay).
   *
   * On Android 12 and below, Android can't be asked where media goes, so the
   * output is inferred from the connected devices: the Bluetooth, wired or USB
   * device connected last (on Android 10 and below, Bluetooth first), else the
   * speaker.
   */
  getCurrentOutputs(): TAudioOutput[]

  /**
   * Register a callback fired when the devices media plays through change, e.g.
   * Bluetooth headphones connect or disconnect, headphones or a USB DAC are
   * plugged in, or playback falls back to the speaker. It fires only when the
   * outputs actually change, with the new outputs and the reason.
   *
   * On Android it fires when a device connects or disconnects; switching between
   * devices that stay connected is reported when Android reconnects them.
   *
   * Each call adds a listener and there is no way to remove one, so register
   * once (e.g. at app start), not in a component effect; inside components use
   * `useAudioOutputs`.
   */
  onOutputsChange(
    callback: (
      outputs: TAudioOutput[],
      reason: TAudioOutputChangeReason
    ) => void
  ): void
}
