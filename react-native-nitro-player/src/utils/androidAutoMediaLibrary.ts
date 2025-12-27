import type { MediaLibrary } from '../types/AndroidAutoMediaLibrary'
import { AndroidAutoMediaLibrary as AndroidAutoMediaLibraryModule } from '../index'

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

  /**
   * Check if Android Auto Media Library is available (Android only)
   */
  isAvailable: (): boolean => {
    return AndroidAutoMediaLibraryModule !== null
  },
}
