import { iOS, type HybridObject } from 'react-native-nitro-modules'

export * from '#nitro/AudioRoutePicker'

@iOS({
  language: 'swift',
  implementation: { className: 'HybridAudioRoutePicker' },
})
export declare class AudioRoutePicker extends HybridObject {
  /**
   * Show the audio route picker view (iOS only)
   * This presents a native AVRoutePickerView for selecting audio output devices like AirPlay
   */
  static showRoutePicker(): void
}
