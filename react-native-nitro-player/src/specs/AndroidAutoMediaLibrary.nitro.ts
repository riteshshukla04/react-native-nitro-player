import type { HybridObject } from 'react-native-nitro-modules'

/**
 * Android Auto Media Library Manager
 * Android-only HybridObject for managing Android Auto media browser structure
 */
export interface AndroidAutoMediaLibrary
  extends HybridObject<{ android: 'kotlin' }> {
  /**
   * Set the Android Auto media library structure
   * This defines what folders and playlists appear in Android Auto
   *
   * @param libraryJson - JSON string of the MediaLibrary structure
   */
  setMediaLibrary(libraryJson: string): void

  /**
   * Clear the Android Auto media library
   * Falls back to showing all playlists
   */
  clearMediaLibrary(): void
}
