import { DownloadManager } from '../index'
import type {
  DownloadProgress,
  DownloadState,
  DownloadedTrack,
  DownloadError,
} from '../types/DownloadTypes'

type ProgressCallback = (progress: DownloadProgress) => void
type StateChangeCallback = (
  downloadId: string,
  trackId: string,
  state: DownloadState,
  error?: DownloadError
) => void
type CompleteCallback = (downloadedTrack: DownloadedTrack) => void

/**
 * Internal subscription manager for download callbacks.
 * Allows multiple hooks to subscribe to a single native callback.
 */
class DownloadCallbackSubscriptionManager {
  private progressSubscribers = new Set<ProgressCallback>()
  private stateChangeSubscribers = new Set<StateChangeCallback>()
  private completeSubscribers = new Set<CompleteCallback>()

  private isProgressRegistered = false
  private isStateChangeRegistered = false
  private isCompleteRegistered = false

  /**
   * Subscribe to download progress updates
   * @returns Unsubscribe function
   */
  subscribeToProgress(callback: ProgressCallback): () => void {
    this.progressSubscribers.add(callback)
    this.ensureProgressRegistered()

    return () => {
      this.progressSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to download state changes
   * @returns Unsubscribe function
   */
  subscribeToStateChange(callback: StateChangeCallback): () => void {
    this.stateChangeSubscribers.add(callback)
    this.ensureStateChangeRegistered()

    return () => {
      this.stateChangeSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to download completions
   * @returns Unsubscribe function
   */
  subscribeToComplete(callback: CompleteCallback): () => void {
    this.completeSubscribers.add(callback)
    this.ensureCompleteRegistered()

    return () => {
      this.completeSubscribers.delete(callback)
    }
  }

  private ensureProgressRegistered(): void {
    if (this.isProgressRegistered) return

    try {
      DownloadManager.onDownloadProgress((progress) => {
        this.progressSubscribers.forEach((subscriber) => {
          try {
            subscriber(progress)
          } catch (error) {
            console.error(
              '[DownloadCallbackManager] Error in progress subscriber:',
              error
            )
          }
        })
      })
      this.isProgressRegistered = true
    } catch (error) {
      console.error(
        '[DownloadCallbackManager] Failed to register progress callback:',
        error
      )
    }
  }

  private ensureStateChangeRegistered(): void {
    if (this.isStateChangeRegistered) return

    try {
      DownloadManager.onDownloadStateChange(
        (downloadId, trackId, state, error) => {
          this.stateChangeSubscribers.forEach((subscriber) => {
            try {
              subscriber(downloadId, trackId, state, error)
            } catch (err) {
              console.error(
                '[DownloadCallbackManager] Error in state change subscriber:',
                err
              )
            }
          })
        }
      )
      this.isStateChangeRegistered = true
    } catch (error) {
      console.error(
        '[DownloadCallbackManager] Failed to register state change callback:',
        error
      )
    }
  }

  private ensureCompleteRegistered(): void {
    if (this.isCompleteRegistered) return

    try {
      DownloadManager.onDownloadComplete((downloadedTrack) => {
        this.completeSubscribers.forEach((subscriber) => {
          try {
            subscriber(downloadedTrack)
          } catch (error) {
            console.error(
              '[DownloadCallbackManager] Error in complete subscriber:',
              error
            )
          }
        })
      })
      this.isCompleteRegistered = true
    } catch (error) {
      console.error(
        '[DownloadCallbackManager] Failed to register complete callback:',
        error
      )
    }
  }
}

// Export singleton instance
export const downloadCallbackManager = new DownloadCallbackSubscriptionManager()
