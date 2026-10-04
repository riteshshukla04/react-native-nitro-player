import type { HybridObject } from 'react-native-nitro-modules'

/**
 * Android Auto Media Library Manager
 * Android-only HybridObject for managing Android Auto media browser structure
 */
export interface AndroidAutoMediaLibrary extends HybridObject<{
  android: 'kotlin'
}> {
  /**
   * Set the Android Auto media library structure
   * This defines what folders and playlists appear in Android Auto
   *
   * @param libraryJson - JSON string of the MediaLibrary structure
   */
  setMediaLibrary(libraryJson: string): Promise<void>

  /**
   * Clear the Android Auto media library
   * Falls back to showing all playlists
   */
  clearMediaLibrary(): Promise<void>

  /** Android Auto opened a folder published with `children: []`; answer with {@link resolveRequest}. */
  onLoadChildren(callback: (requestId: string, parentId: string) => void): void

  /** A car search, or a voice request the loaded playlists cannot match; answer with {@link resolveRequest}. */
  onSearch(callback: (requestId: string, query: string) => void): void

  /** Answers {@link onLoadChildren} / {@link onSearch} with a JSON array of MediaItem. */
  resolveRequest(requestId: string, itemsJson: string): void

  /** Replaces the session buttons with a JSON array of SessionButton. */
  setSessionButtons(buttonsJson: string): void

  /** Called with the button's `action` when a session button is pressed. */
  onSessionButtonPress(callback: (action: string) => void): void

  /** A controller asked to play with nothing loaded (car auto-play, play on connect); load the last queue now. */
  onPlaybackResumption(callback: () => void): void
}
