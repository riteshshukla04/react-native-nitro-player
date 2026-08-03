import { PlayerQueue, TrackPlayer } from '../index'
import type { TrackItem, TrackPlayerState, Reason } from '../types/PlayerQueue'

type PlaybackStateCallback = (state: TrackPlayerState, reason?: Reason) => void
type TrackChangeCallback = (track: TrackItem, reason?: Reason) => void
type PlaybackProgressCallback = (
  position: number,
  totalDuration: number,
  isManuallySeeked?: boolean
) => void
type SeekCallback = (position: number, totalDuration: number) => void
type TemporaryQueueCallback = (
  playNextQueue: TrackItem[],
  upNextQueue: TrackItem[]
) => void

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
  private temporaryQueueSubscribers = new Set<TemporaryQueueCallback>()
  private playlistsChangedSubscribers = new Set<() => void>()
  private isPlaylistsChangedRegistered = false
  private isPlaybackStateRegistered = false
  private isTrackChangeRegistered = false
  private isPlaybackProgressRegistered = false
  private isSeekRegistered = false
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
  subscribeToTemporaryQueueChange(callback: TemporaryQueueCallback): () => void {
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

  private ensurePlaylistsChangedRegistered(): void {
    if (this.isPlaylistsChangedRegistered) return

    try {
      PlayerQueue.onPlaylistsChanged(() => {
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
}

// Export singleton instance
export const callbackManager = new CallbackSubscriptionManager()
