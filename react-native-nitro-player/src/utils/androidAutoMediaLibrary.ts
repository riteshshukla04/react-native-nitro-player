import type {
  MediaItem,
  MediaLibrary,
  SessionButton,
} from '../types/AndroidAutoMediaLibrary'
import { AndroidAutoMediaLibrary as AndroidAutoMediaLibraryModule } from '../index'

type ItemsProvider = (
  argument: string
) => Promise<MediaItem[] | null | undefined>

const answer = (requestId: string, provide: () => ReturnType<ItemsProvider>) =>
  provide()
    .catch(() => null)
    .then((items) =>
      AndroidAutoMediaLibraryModule?.resolveRequest(
        requestId,
        JSON.stringify(items ?? [])
      )
    )

/**
 * Helper utilities for Android Auto Media Library
 * Android-only functionality
 */
export const AndroidAutoMediaLibraryHelper = {
  /**
   * Set the Android Auto media library structure
   * This defines what folders and playlists appear in Android Auto
   *
   * @param library - The media library structure
   *
   * @example
   * ```ts
   * AndroidAutoMediaLibraryHelper.set({
   *   layoutType: 'grid',
   *   rootItems: [
   *     {
   *       id: 'my_music',
   *       title: 'My Music',
   *       mediaType: 'folder',
   *       isPlayable: false,
   *       children: [
   *         {
   *           id: 'favorites',
   *           title: 'Favorites',
   *           mediaType: 'playlist',
   *           playlistId: 'favorites-playlist-id', // References a playlist created with PlayerQueue
   *           isPlayable: false,
   *         },
   *       ],
   *     },
   *   ],
   * })
   * ```
   */
  set: (library: MediaLibrary): void => {
    if (!AndroidAutoMediaLibraryModule) {
      console.warn('AndroidAutoMediaLibrary is only available on Android')
      return
    }
    const json = JSON.stringify(library)
    AndroidAutoMediaLibraryModule.setMediaLibrary(json)
  },

  /**
   * Clear the Android Auto media library
   * Falls back to showing all playlists
   */
  clear: (): void => {
    if (!AndroidAutoMediaLibraryModule) {
      console.warn('AndroidAutoMediaLibrary is only available on Android')
      return
    }
    AndroidAutoMediaLibraryModule.clearMediaLibrary()
  },

  /** Children of folders published with `children: []`; playable ids are `${playlistId}:${trackId}`, empty after 10s. Register at module scope: the car can start the app without UI. */
  setChildrenLoader: (loader: ItemsProvider): void => {
    AndroidAutoMediaLibraryModule?.onLoadChildren((requestId, parentId) =>
      answer(requestId, () => loader(parentId))
    )
  },

  /** Answers car searches and unmatched voice requests (first playable result plays); search shows from the next connection. */
  setSearchHandler: (handler: ItemsProvider): void => {
    AndroidAutoMediaLibraryModule?.onSearch((requestId, query) =>
      answer(requestId, () => handler(query))
    )
  },

  /** Buttons beside the transport controls in Android Auto and the notification; call again to change their state. */
  setSessionButtons: (buttons: SessionButton[]): void => {
    AndroidAutoMediaLibraryModule?.setSessionButtons(JSON.stringify(buttons))
  },

  /** Called with the pressed button's `action`. */
  onSessionButtonPress: (callback: (action: string) => void): void => {
    AndroidAutoMediaLibraryModule?.onSessionButtonPress(callback)
  },

  /** Car auto-play or play-on-connect found nothing loaded: restore your last queue (playback starts once it is loaded). */
  onPlaybackResumption: (callback: () => void): void => {
    AndroidAutoMediaLibraryModule?.onPlaybackResumption(callback)
  },

  /**
   * Check if Android Auto Media Library is available (Android only)
   */
  isAvailable: (): boolean => {
    return AndroidAutoMediaLibraryModule !== null
  },
}
