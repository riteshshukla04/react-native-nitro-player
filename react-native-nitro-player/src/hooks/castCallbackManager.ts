import { Cast } from '../index'
import type { CastState } from '../specs/Cast.nitro'

type CastStateCallback = (state: CastState, deviceName: string | null) => void

/**
 * Internal subscription manager that allows multiple hooks/components to
 * subscribe to the single native `Cast.onCastStateChange` callback without
 * overwriting each other. Mirrors {@link callbackManager}.
 */
class CastCallbackSubscriptionManager {
  private castStateSubscribers = new Set<CastStateCallback>()
  private isCastStateRegistered = false

  /**
   * Subscribe to Cast connection state changes.
   * @returns Unsubscribe function
   */
  subscribeToCastState(callback: CastStateCallback): () => void {
    this.castStateSubscribers.add(callback)
    this.ensureCastStateRegistered()

    return () => {
      this.castStateSubscribers.delete(callback)
    }
  }

  private ensureCastStateRegistered(): void {
    if (this.isCastStateRegistered) return

    try {
      Cast.onCastStateChange((state, deviceName) => {
        this.castStateSubscribers.forEach((subscriber) => {
          try {
            subscriber(state, deviceName)
          } catch (error) {
            console.error(
              '[CastCallbackManager] Error in cast state subscriber:',
              error
            )
          }
        })
      })
      this.isCastStateRegistered = true
    } catch (error) {
      console.error(
        '[CastCallbackManager] Failed to register cast state callback:',
        error
      )
    }
  }
}

// Export singleton instance
export const castCallbackManager = new CastCallbackSubscriptionManager()
