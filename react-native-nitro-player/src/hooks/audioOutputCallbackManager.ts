import { AudioDevices } from '../index'
import type {
  TAudioOutput,
  TAudioOutputChangeReason,
} from '../types/AudioOutput'

type OutputsCallback = (
  outputs: TAudioOutput[],
  reason: TAudioOutputChangeReason
) => void

/**
 * Internal subscription manager that lets several hooks/components share the
 * single native `AudioDevices.onOutputsChange` listener, which can't be removed.
 * Mirrors {@link castCallbackManager}.
 */
class AudioOutputCallbackSubscriptionManager {
  private subscribers = new Set<OutputsCallback>()
  private isRegistered = false

  /**
   * Subscribe to output changes.
   * @returns Unsubscribe function
   */
  subscribe(callback: OutputsCallback): () => void {
    this.subscribers.add(callback)
    this.ensureRegistered()

    return () => {
      this.subscribers.delete(callback)
    }
  }

  private ensureRegistered(): void {
    if (this.isRegistered) return

    try {
      AudioDevices.onOutputsChange((outputs, reason) => {
        this.subscribers.forEach((subscriber) => {
          try {
            subscriber(outputs, reason)
          } catch (error) {
            console.error(
              '[AudioOutputCallbackManager] Error in outputs subscriber:',
              error
            )
          }
        })
      })
      this.isRegistered = true
    } catch (error) {
      console.error(
        '[AudioOutputCallbackManager] Failed to register outputs callback:',
        error
      )
    }
  }
}

export const audioOutputCallbackManager =
  new AudioOutputCallbackSubscriptionManager()
