import type { CarPlayMediaLibrary } from '../types/CarPlayMediaLibrary'
import { CarPlayMediaLibraryModule } from '../index'

/**
 * Helper utilities for CarPlay Media Library
 * iOS-only functionality
 */
export const CarPlayMediaLibraryHelper = {
  /**
   * Set the CarPlay media library structure
   * This defines what folders and playlists appear in CarPlay
   *
   * @param library - The media library structure
   *
   * @example
   * ```ts
   * CarPlayMediaLibraryHelper.set({
   *   layoutType: 'list',
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
   *           playlistId: 'favorites-playlist-id',
   *           isPlayable: false,
   *         },
   *       ],
   *     },
   *   ],
   * })
   * ```
   */
  set: (library: CarPlayMediaLibrary): void => {
    if (!CarPlayMediaLibraryModule) {
      console.warn('CarPlayMediaLibrary is only available on iOS')
      return
    }
    const json = JSON.stringify(library)
    CarPlayMediaLibraryModule.setMediaLibrary(json)
  },

  /**
   * Clear the CarPlay media library
   * Falls back to showing all playlists
   */
  clear: (): void => {
    if (!CarPlayMediaLibraryModule) {
      console.warn('CarPlayMediaLibrary is only available on iOS')
      return
    }
    CarPlayMediaLibraryModule.clearMediaLibrary()
  },

  /**
   * Check if CarPlay Media Library is available (iOS only)
   */
  isAvailable: (): boolean => {
    return CarPlayMediaLibraryModule !== null
  },
}
