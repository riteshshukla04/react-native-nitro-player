/**
 * Layout type for the CarPlay media browser
 */
export type CarPlayLayoutType = 'grid' | 'list'

/**
 * Media type for different kinds of content in CarPlay
 */
export type CarPlayMediaType = 'folder' | 'audio' | 'playlist'

/**
 * Media item that can be displayed in CarPlay
 */
export interface CarPlayMediaItem {
  /** Unique identifier for the media item */
  id: string

  /** Display title */
  title: string

  /** Optional subtitle/description */
  subtitle?: string

  /** Optional icon/artwork URL */
  iconUrl?: string

  /** Whether this item can be played directly */
  isPlayable: boolean

  /** Media type */
  mediaType: CarPlayMediaType

  /** Reference to playlist ID (for playlist items) - will load tracks from this playlist */
  playlistId?: string

  /** Child items for browsable folders */
  children?: CarPlayMediaItem[]

  /** Layout type for folder items (overrides library default) */
  layoutType?: CarPlayLayoutType
}

/**
 * Media library structure for CarPlay
 */
export interface CarPlayMediaLibrary {
  /** Layout type for the media browser (applies to all folders by default) */
  layoutType: CarPlayLayoutType

  /** Root level media items */
  rootItems: CarPlayMediaItem[]

  /** Optional app name to display */
  appName?: string

  /** Optional app icon URL */
  appIconUrl?: string
}
