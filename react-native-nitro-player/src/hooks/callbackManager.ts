import { PlayerQueue, TrackPlayer } from '../index'
import type {
  TrackItem,
  TrackPlayerState,
  Reason,
  TimedMetadata,
} from '../types/PlayerQueue'

type PlaybackStateCallback = (state: TrackPlayerState, reason?: Reason) => void
type TrackChangeCallback = (track: TrackItem, reason?: Reason) => void
type PlaybackProgressCallback = (
  position: number,
  totalDuration: number,
  isManuallySeeked?: boolean
) => void
type SeekCallback = (position: number, totalDuration: number) => void
type TimedMetadataCallback = (metadata: TimedMetadata) => void
type TemporaryQueueCallback = (
  playNextQueue: TrackItem[],
  upNextQueue: TrackItem[]
) => void
type AndroidAutoConnectionCallback = (connected: boolean) => void

/**
 * Internal subscription manager that allows multiple hooks to subscribe
 * to a single native callback. This solves the problem where registering
 * a new callback overwrites the previous one.
 */
class CallbackSubscriptionManager {
  private playbackStateSubscribers = new Set<PlaybackStateCallback>()
  private trackChangeSubscribers = new Set<TrackChangeCallback>()
  private playbackProgressSubscribers = new Set<PlaybackProgressCallback>()
  private seekSubscribers = new Set<SeekCallback>()
  private timedMetadataSubscribers = new Set<TimedMetadataCallback>()
  private temporaryQueueSubscribers = new Set<TemporaryQueueCallback>()
  private playlistsChangedSubscribers = new Set<() => void>()
  private androidAutoConnectionSubscribers =
    new Set<AndroidAutoConnectionCallback>()
  private isPlaylistsChangedRegistered = false
  private playlistsChangedFanOutScheduled = false
  private isAndroidAutoConnectionRegistered = false
  private isPlaybackStateRegistered = false
  private isTrackChangeRegistered = false
  private isPlaybackProgressRegistered = false
  private isSeekRegistered = false
  private isTimedMetadataRegistered = false
  private isTemporaryQueueRegistered = false

  /**
   * Subscribe to playback state changes
   * @returns Unsubscribe function
   */
  subscribeToPlaybackState(callback: PlaybackStateCallback): () => void {
    this.playbackStateSubscribers.add(callback)
    this.ensurePlaybackStateRegistered()

    return () => {
      this.playbackStateSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to track changes
   * @returns Unsubscribe function
   */
  subscribeToTrackChange(callback: TrackChangeCallback): () => void {
    this.trackChangeSubscribers.add(callback)
    this.ensureTrackChangeRegistered()

    return () => {
      this.trackChangeSubscribers.delete(callback)
    }
  }

  private ensurePlaybackStateRegistered(): void {
    if (this.isPlaybackStateRegistered) return

    try {
      TrackPlayer.onPlaybackStateChange((state, reason) => {
        this.playbackStateSubscribers.forEach((subscriber) => {
          try {
            subscriber(state, reason)
          } catch (error) {
            console.error(
              '[CallbackManager] Error in playback state subscriber:',
              error
            )
          }
        })
      })
      this.isPlaybackStateRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register playback state callback:',
        error
      )
    }
  }

  private ensureTrackChangeRegistered(): void {
    if (this.isTrackChangeRegistered) return

    try {
      TrackPlayer.onChangeTrack((track, reason) => {
        this.trackChangeSubscribers.forEach((subscriber) => {
          try {
            subscriber(track, reason)
          } catch (error) {
            console.error(
              '[CallbackManager] Error in track change subscriber:',
              error
            )
          }
        })
      })
      this.isTrackChangeRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register track change callback:',
        error
      )
    }
  }

  /**
   * Subscribe to playback progress changes
   * @returns Unsubscribe function
   */
  subscribeToPlaybackProgressChange(
    callback: PlaybackProgressCallback
  ): () => void {
    this.playbackProgressSubscribers.add(callback)
    this.ensurePlaybackProgressRegistered()

    return () => {
      this.playbackProgressSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to seek events
   * @returns Unsubscribe function
   */
  subscribeToSeek(callback: SeekCallback): () => void {
    this.seekSubscribers.add(callback)
    this.ensureSeekRegistered()

    return () => {
      this.seekSubscribers.delete(callback)
    }
  }

  private ensurePlaybackProgressRegistered(): void {
    if (this.isPlaybackProgressRegistered) return

    try {
      TrackPlayer.onPlaybackProgressChange(
        (position, totalDuration, isManuallySeeked) => {
          this.playbackProgressSubscribers.forEach((subscriber) => {
            try {
              subscriber(position, totalDuration, isManuallySeeked)
            } catch (error) {
              console.error(
                '[CallbackManager] Error in playback progress subscriber:',
                error
              )
            }
          })
        }
      )
      this.isPlaybackProgressRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register playback progress callback:',
        error
      )
    }
  }

  /**
   * Subscribe to playNext / upNext changes
   * @returns Unsubscribe function
   */
  subscribeToTemporaryQueueChange(
    callback: TemporaryQueueCallback
  ): () => void {
    this.temporaryQueueSubscribers.add(callback)
    this.ensureTemporaryQueueRegistered()

    return () => {
      this.temporaryQueueSubscribers.delete(callback)
    }
  }

  /**
   * Subscribe to playlist mutations (tracks added/removed/reordered).
   * @returns Unsubscribe function
   */
  subscribeToPlaylistsChanged(callback: () => void): () => void {
    this.playlistsChangedSubscribers.add(callback)
    this.ensurePlaylistsChangedRegistered()

    return () => {
      this.playlistsChangedSubscribers.delete(callback)
    }
  }

  // Task-level, not a microtask: native callbacks arrive as separate JS tasks.
  private schedulePlaylistsChangedFanOut(): void {
    if (this.playlistsChangedFanOutScheduled) return
    this.playlistsChangedFanOutScheduled = true
    setTimeout(() => {
      this.playlistsChangedFanOutScheduled = false
      this.playlistsChangedSubscribers.forEach((subscriber) => {
        try {
          subscriber()
        } catch (error) {
          console.error(
            '[CallbackManager] Error in playlists changed subscriber:',
            error
          )
        }
      })
    }, 0)
  }

  private ensurePlaylistsChangedRegistered(): void {
    if (this.isPlaylistsChangedRegistered) return

    try {
      PlayerQueue.onPlaylistsChanged(() => {
        this.schedulePlaylistsChangedFanOut()
      })
      // Track-level mutations only fire the per-playlist event.
      PlayerQueue.onPlaylistChanged(() => {
        this.schedulePlaylistsChangedFanOut()
      })
      this.isPlaylistsChangedRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register playlists changed callback:',
        error
      )
    }
  }

  private ensureTemporaryQueueRegistered(): void {
    if (this.isTemporaryQueueRegistered) return

    try {
      TrackPlayer.onTemporaryQueueChange((playNextQueue, upNextQueue) => {
        this.temporaryQueueSubscribers.forEach((subscriber) => {
          try {
            subscriber(playNextQueue, upNextQueue)
          } catch (error) {
            console.error(
              '[CallbackManager] Error in temporary queue subscriber:',
              error
            )
          }
        })
      })
      this.isTemporaryQueueRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register temporary queue callback:',
        error
      )
    }
  }

  private ensureSeekRegistered(): void {
    if (this.isSeekRegistered) return

    try {
      TrackPlayer.onSeek((position, totalDuration) => {
        this.seekSubscribers.forEach((subscriber) => {
          try {
            subscriber(position, totalDuration)
          } catch (error) {
            console.error('[CallbackManager] Error in seek subscriber:', error)
          }
        })
      })
      this.isSeekRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register seek callback:',
        error
      )
    }
  }

  /**
   * Subscribe to Android Auto connection changes
   * @returns Unsubscribe function
   */
  subscribeToAndroidAutoConnection(
    callback: AndroidAutoConnectionCallback
  ): () => void {
    this.androidAutoConnectionSubscribers.add(callback)
    this.ensureAndroidAutoConnectionRegistered()

    return () => {
      this.androidAutoConnectionSubscribers.delete(callback)
    }
  }

  private ensureAndroidAutoConnectionRegistered(): void {
    if (this.isAndroidAutoConnectionRegistered) return

    try {
      TrackPlayer.onAndroidAutoConnectionChange((connected) => {
        this.androidAutoConnectionSubscribers.forEach((subscriber) => {
          try {
            subscriber(connected)
          } catch (error) {
            console.error(
              '[CallbackManager] Error in Android Auto connection subscriber:',
              error
            )
          }
        })
      })
      this.isAndroidAutoConnectionRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register Android Auto connection callback:',
        error
      )
    }
  }

  /**
   * Subscribe to in-stream (timed) metadata events
   * @returns Unsubscribe function
   */
  subscribeToTimedMetadata(callback: TimedMetadataCallback): () => void {
    this.timedMetadataSubscribers.add(callback)
    this.ensureTimedMetadataRegistered()

    return () => {
      this.timedMetadataSubscribers.delete(callback)
    }
  }

  private ensureTimedMetadataRegistered(): void {
    if (this.isTimedMetadataRegistered) return

    try {
      TrackPlayer.onTimedMetadata((metadata) => {
        this.timedMetadataSubscribers.forEach((subscriber) => {
          try {
            subscriber(metadata)
          } catch (error) {
            console.error(
              '[CallbackManager] Error in timed metadata subscriber:',
              error
            )
          }
        })
      })
      this.isTimedMetadataRegistered = true
    } catch (error) {
      console.error(
        '[CallbackManager] Failed to register timed metadata callback:',
        error
      )
    }
  }
}

// Export singleton instance
export const callbackManager = new CallbackSubscriptionManager()
