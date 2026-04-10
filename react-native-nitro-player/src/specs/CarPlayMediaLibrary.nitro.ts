import type { HybridObject } from 'react-native-nitro-modules'

/**
 * CarPlay Media Library Manager
 * iOS-only HybridObject for managing CarPlay media browser structure
 */
export interface CarPlayMediaLibrary extends HybridObject<{
  ios: 'swift'
}> {
  /**
   * Set the CarPlay media library structure
   * This defines what folders and playlists appear in CarPlay
   *
   * @param libraryJson - JSON string of the CarPlayMediaLibrary structure
   */
  setMediaLibrary(libraryJson: string): Promise<void>

  /**
   * Clear the CarPlay media library
   * Falls back to showing all playlists
   */
  clearMediaLibrary(): Promise<void>
}
