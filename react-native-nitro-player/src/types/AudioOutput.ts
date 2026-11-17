/**
 * The kind of device a {@linkcode TAudioOutput} is.
 *
 * - `built_in_speaker`: the device's own loudspeaker
 * - `built_in_earpiece`: the earpiece used for calls (iOS "Receiver")
 * - `wired_headphones`: headphones or a headset on the headphone jack
 * - `line_out`: an analog or digital line output, e.g. a dock or car aux input
 * - `bluetooth`: any Bluetooth output (A2DP, hands-free, LE Audio, hearing aids)
 * - `usb`: a USB audio device, e.g. a USB-C DAC or headset
 * - `airplay`: an AirPlay receiver (iOS)
 * - `car_audio`: a car's audio system (CarPlay on iOS, the car's audio bus on Android Automotive)
 * - `hdmi`: HDMI or DisplayPort audio
 * - `unknown`: any other output
 *
 * @see {@linkcode TAudioOutput.type}
 */
export type TAudioOutputType =
  | 'built_in_speaker'
  | 'built_in_earpiece'
  | 'wired_headphones'
  | 'line_out'
  | 'bluetooth'
  | 'usb'
  | 'airplay'
  | 'car_audio'
  | 'hdmi'
  | 'unknown'

/**
 * An output device that media plays through, as reported by
 * `AudioDevices.getCurrentOutputs()` and `AudioDevices.onOutputsChange()`.
 */
export type TAudioOutput = {
  /**
   * Identifies the output, and stays the same when the device reconnects.
   * Bluetooth outputs are identified by their address: the full address on iOS,
   * its last two octets on Android (all Android 13+ shows apps without the
   * Nearby devices permission). Other outputs are identified by the port UID on
   * iOS and by type and name on Android, so two identical wired or USB devices
   * can share an id.
   */
  id: string
  /**
   * Human-readable name, e.g. `"WH-1000XM4"`. Wired outputs usually report a
   * generic name such as `"Headphones"` or `"USB Audio"`.
   */
  name: string
  /** The kind of device. */
  type: TAudioOutputType
}

/**
 * Why the outputs reported by `AudioDevices.onOutputsChange()` changed.
 *
 * - `device_connected`: a device was connected, e.g. Bluetooth headphones paired or headphones plugged in
 * - `device_disconnected`: the device media was playing through went away, e.g. headphones unplugged
 * - `route_changed`: the route changed for another reason, e.g. the user picked another output
 */
export type TAudioOutputChangeReason =
  | 'device_connected'
  | 'device_disconnected'
  | 'route_changed'
