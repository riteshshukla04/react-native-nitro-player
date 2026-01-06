import type { HybridObject } from 'react-native-nitro-modules'

export interface AudioRoutePicker extends HybridObject<{ ios: 'swift' }> {
  /**
   * Show the audio route picker view (iOS only)
   * This presents a native AVRoutePickerView for selecting audio output devices like AirPlay
   */
  showRoutePicker(): void
}
