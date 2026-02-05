import { Equalizer } from '../index'
import type { EqualizerBand } from '../types/EqualizerTypes'

type EnabledChangeCallback = (enabled: boolean) => void
type BandChangeCallback = (bands: EqualizerBand[]) => void
type PresetChangeCallback = (presetName: string | null) => void

/**
 * Internal subscription manager that allows multiple hooks to subscribe
 * to equalizer callbacks. This solves the problem where registering
 * a new callback overwrites the previous one.
 */
class EqualizerCallbackSubscriptionManager {
  private enabledChangeSubscribers = new Set<EnabledChangeCallback>()
  private bandChangeSubscribers = new Set<BandChangeCallback>()
  private presetChangeSubscribers = new Set<PresetChangeCallback>()
  private isEnabledChangeRegistered = false
  private isBandChangeRegistered = false
  private isPresetChangeRegistered = false

  /**
   * Subscribe to enabled state changes
   * @returns Unsubscribe function
   */
  subscribeToEnabledChange(callback: EnabledChangeCallback): () => void {
    this.enabledChangeSubscribers.add(callback)
    this.ensureEnabledChangeRegistered()

    return () => {
      this.enabledChangeSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to band changes
   * @returns Unsubscribe function
   */
  subscribeToBandChange(callback: BandChangeCallback): () => void {
    this.bandChangeSubscribers.add(callback)
    this.ensureBandChangeRegistered()

    return () => {
      this.bandChangeSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to preset changes
   * @returns Unsubscribe function
   */
  subscribeToPresetChange(callback: PresetChangeCallback): () => void {
    this.presetChangeSubscribers.add(callback)
    this.ensurePresetChangeRegistered()

    return () => {
      this.presetChangeSubscribers.delete(callback)
    }
  }

  private ensureEnabledChangeRegistered(): void {
    if (this.isEnabledChangeRegistered) return

    try {
      Equalizer.onEnabledChange((enabled) => {
        this.enabledChangeSubscribers.forEach((subscriber) => {
          try {
            subscriber(enabled)
          } catch (error) {
            console.error(
              '[EqualizerCallbackManager] Error in enabled change subscriber:',
              error
            )
          }
        })
      })
      this.isEnabledChangeRegistered = true
    } catch (error) {
      console.error(
        '[EqualizerCallbackManager] Failed to register enabled change callback:',
        error
      )
    }
  }

  private ensureBandChangeRegistered(): void {
    if (this.isBandChangeRegistered) return

    try {
      Equalizer.onBandChange((bands) => {
        this.bandChangeSubscribers.forEach((subscriber) => {
          try {
            subscriber(bands)
          } catch (error) {
            console.error(
              '[EqualizerCallbackManager] Error in band change subscriber:',
              error
            )
          }
        })
      })
      this.isBandChangeRegistered = true
    } catch (error) {
      console.error(
        '[EqualizerCallbackManager] Failed to register band change callback:',
        error
      )
    }
  }

  private ensurePresetChangeRegistered(): void {
    if (this.isPresetChangeRegistered) return

    try {
      Equalizer.onPresetChange((presetName) => {
        this.presetChangeSubscribers.forEach((subscriber) => {
          try {
            subscriber(presetName)
          } catch (error) {
            console.error(
              '[EqualizerCallbackManager] Error in preset change subscriber:',
              error
            )
          }
        })
      })
      this.isPresetChangeRegistered = true
    } catch (error) {
      console.error(
        '[EqualizerCallbackManager] Failed to register preset change callback:',
        error
      )
    }
  }
}

// Export singleton instance
export const equalizerCallbackManager =
  new EqualizerCallbackSubscriptionManager()
