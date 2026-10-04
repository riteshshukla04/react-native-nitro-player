/**
 * Layout type for the Android Auto media browser
 */
export type LayoutType = 'grid' | 'list'

/**
 * Media type for different kinds of content
 */
export type MediaType = 'folder' | 'audio' | 'playlist'

/**
 * Media item that can be displayed in Android Auto
 */
export interface MediaItem {
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
  mediaType: MediaType

  /** Reference to playlist ID (for playlist items) - will load tracks from this playlist */
  playlistId?: string

  /** Child items for browsable folders */
  children?: MediaItem[]

  /** Layout type for folder items (overrides library default) */
  layoutType?: LayoutType

  /** Group header; contiguous items sharing one are listed under it */
  groupTitle?: string
}

/**
 * Media library structure for Android Auto
 */
export interface MediaLibrary {
  /** Layout type for the media browser (applies to all folders by default) */
  layoutType: LayoutType

  /** Root level media items */
  rootItems: MediaItem[]

  /** Optional app name to display */
  appName?: string

  /** Optional app icon URL */
  appIconUrl?: string
}

export type SessionButtonIcon =
  | 'heart'
  | 'heart_filled'
  | 'star'
  | 'star_filled'
  | 'thumb_up'
  | 'thumb_up_filled'
  | 'plus'
  | 'check'

/** App-defined button beside the transport controls in Android Auto and the notification */
export interface SessionButton {
  /** Passed to the press callback */
  action: string

  /** Accessibility label */
  title: string

  icon: SessionButtonIcon
}
