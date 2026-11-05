/** An http(s) or file URL, an SF Symbol name, or the name of an image in the app's asset catalog */
export type CarPlayImage = string

/** Apple's own tab icons and titles, used through {@linkcode CarPlayTab.systemItem} */
export type CarPlayTabSystemItem =
  | 'bookmarks'
  | 'contacts'
  | 'downloads'
  | 'favorites'
  | 'featured'
  | 'history'
  | 'more'
  | 'mostRecent'
  | 'mostViewed'
  | 'recents'
  | 'search'
  | 'topRated'

/** How a template shows in the tab bar; `systemItem` wins over `title` and `image` */
export interface CarPlayTab {
  title?: string
  image?: CarPlayImage
  systemItem?: CarPlayTabSystemItem
  /** Shows a dot on the tab */
  badge?: boolean
}

/**
 * What selecting a row, grid button or image does, checked in this order:
 * - `playlistId` + `trackId`: plays the track from that playlist in the shared player and opens Now Playing
 * - `playlistId` + `playPlaylist`: plays the playlist from its first track
 * - `playlistId`: opens the playlist's tracks, kept in sync with `PlayerQueue`
 * - `template`: opens it
 * - `loadTemplate`: opens what `CarPlayHelper.setTemplateLoader` returns for the `id`
 * - none of them: `CarPlayHelper.onSelect` gets the `id`
 */
export interface CarPlayAction {
  playlistId?: string
  trackId?: string
  playPlaylist?: boolean
  template?: CarPlayTemplate
  loadTemplate?: boolean
}

/** The indicator at the trailing edge of a {@linkcode CarPlayListItem} */
export type CarPlayAccessory = 'none' | 'disclosure' | 'cloud'

/** A row in a list; shows a playing indicator while its `trackId` plays */
export interface CarPlayListItem extends CarPlayAction {
  type?: 'item'
  id: string
  title: string
  subtitle?: string
  image?: CarPlayImage
  /** Default: `disclosure` for rows that open something */
  accessory?: CarPlayAccessory
  /** Shown at the trailing edge instead of {@linkcode CarPlayListItem.accessory} */
  accessoryImage?: CarPlayImage
  explicit?: boolean
  /** Default: true */
  enabled?: boolean
  /** How much has been played, from 0 to 1, shown as a bar, such as for podcast episodes */
  progress?: number
  /** Which side the playing indicator shows on. Default: `trailing` */
  playingIndicator?: 'leading' | 'trailing'
}

/**
 * The fields every tile in an image row has. Selecting a tile runs its {@linkcode CarPlayAction}.
 * @see {@linkcode CarPlayImageRow}
 */
interface CarPlayImageRowTile extends CarPlayAction {
  id: string
  image: CarPlayImage
}

/** Artwork with a title and subtitle under it, in a {@linkcode CarPlayImageRow} */
export interface CarPlayImageRowElement extends CarPlayImageRowTile {
  title?: string
  /** Shown under the title, such as the artist (iOS 26+) */
  subtitle?: string
}

/** A large card with its title and subtitle at the bottom, in a {@linkcode CarPlayCardRow} */
export interface CarPlayCardElement extends CarPlayImageRowTile {
  title: string
  subtitle?: string
  /** Fills the whole card with the image instead of showing it as a rounded square. Default: false */
  fillImage?: boolean
  /**
   * The card's color as `#RRGGBB` or `#RRGGBBAA`: behind the text when `fillImage` is set,
   * otherwise in the card's gradient. Default: the system's secondary background
   */
  tintColor?: string
}

/** How {@linkcode CarPlayCondensedElement} and {@linkcode CarPlayImageGridElement} cut their image */
export type CarPlayImageShape = 'circle' | 'rounded-rectangle'

/** A small image beside its title and subtitle, in a {@linkcode CarPlayCondensedRow} */
export interface CarPlayCondensedElement extends CarPlayImageRowTile {
  title: string
  subtitle?: string
  /** Default: `rounded-rectangle` */
  imageShape?: CarPlayImageShape
  /** An SF Symbol shown at the trailing edge, such as `play.fill` */
  accessorySymbol?: string
}

/** An image with a title under it, such as an artist, in a {@linkcode CarPlayImageGridRow} */
export interface CarPlayImageGridElement extends CarPlayImageRowTile {
  title: string
  /** Default: `rounded-rectangle` */
  imageShape?: CarPlayImageShape
  /** An SF Symbol shown beside the title */
  accessorySymbol?: string
}

/** An image without text, in a {@linkcode CarPlayGridRow} */
export interface CarPlayGridElement extends CarPlayImageRowTile {}

/**
 * The fields every image row has. A row shows up to eight tiles; styles other than
 * `row` need iOS 26, and earlier versions show a single line of images.
 * @see {@linkcode CarPlayListRow}
 */
interface CarPlayImageRowBase {
  type: 'imageRow'
  /** Selecting the row's title reaches `CarPlayHelper.onSelect` with this id, such as to open the whole list */
  id: string
  /** Shown above the tiles; leave it out to show only the tiles */
  title?: string
  /** Wraps the tiles onto more lines, like a grid, instead of one line (iOS 26+). Default: false */
  multipleLines?: boolean
}

/** Artwork with titles and subtitles, such as albums or songs; the default style */
export interface CarPlayImageRow extends CarPlayImageRowBase {
  style?: 'row'
  elements: CarPlayImageRowElement[]
}

/** Large cards, such as for featured playlists or stations */
export interface CarPlayCardRow extends CarPlayImageRowBase {
  style: 'card'
  elements: CarPlayCardElement[]
}

/** Compact tiles with a small image beside the text, such as for a list of songs */
export interface CarPlayCondensedRow extends CarPlayImageRowBase {
  style: 'condensed'
  elements: CarPlayCondensedElement[]
}

/** Images with a title under each, such as round artist photos */
export interface CarPlayImageGridRow extends CarPlayImageRowBase {
  style: 'image-grid'
  elements: CarPlayImageGridElement[]
}

/** Images without text */
export interface CarPlayGridRow extends CarPlayImageRowBase {
  style: 'grid'
  elements: CarPlayGridElement[]
}

/** A row in a {@linkcode CarPlayListSection}: a list item or one of the image row styles */
export type CarPlayListRow =
  | CarPlayListItem
  | CarPlayImageRow
  | CarPlayCardRow
  | CarPlayCondensedRow
  | CarPlayImageGridRow
  | CarPlayGridRow

/** A button beside a {@linkcode CarPlayListSection.header}; presses reach `CarPlayHelper.onSelect` with its `id` */
export interface CarPlayHeaderButton {
  id: string
  image: CarPlayImage
}

/** A group of rows in a {@linkcode CarPlayListTemplate} */
export interface CarPlayListSection {
  header?: string
  /** Shown under the header; needs `header` */
  headerSubtitle?: string
  /** Shown beside the header; needs `header` */
  headerImage?: CarPlayImage
  /** Needs `header` */
  headerButton?: CarPlayHeaderButton
  /** One character in the list's side index for jumping through long lists, such as `A` */
  indexTitle?: string
  items: CarPlayListRow[]
}

/** A button in the navigation bar; presses reach `CarPlayHelper.onSelect` */
export interface CarPlayBarButton {
  id: string
  title?: string
  image?: CarPlayImage
  /** Default: `plain` */
  style?: 'plain' | 'rounded'
}

/**
 * Lists filled from the player and kept up to date:
 * - `queue`: what plays now and next; selecting a row skips to it
 * - `playlists`: every `PlayerQueue` playlist; selecting one opens its tracks
 * - `playlist`: the tracks of `playlistId`; selecting one plays it
 */
export type CarPlayListSource = 'queue' | 'playlists' | 'playlist'

/**
 * `lazy` templates show right away and get their content from
 * `CarPlayHelper.setTemplateLoader`, called with the template's `id`. The loader
 * returns a template of the same `type` whose sections, buttons, source and
 * bar buttons replace the placeholder's; `title` and `tab` stay. A cold start
 * started from the car waits for JS, so loaders work with the app closed.
 * `CarPlayHelper.reload` asks again while the last content stays on screen.
 */
interface CarPlayLazy {
  lazy?: boolean
}

/** A screen of sections and rows */
export interface CarPlayListTemplate extends CarPlayLazy {
  type: 'list'
  id: string
  title: string
  sections?: CarPlayListSection[]
  /** Shown after `sections` */
  source?: CarPlayListSource
  playlistId?: string
  emptyTitle?: string
  emptySubtitle?: string
  barButtons?: CarPlayBarButton[]
  tab?: CarPlayTab
  /** Shown while a lazy template loads. Default: {@linkcode CarPlayTexts.loading} */
  loadingTitle?: string
  /** Shown with a retry row when a lazy template's loader fails or returns nothing. Default: {@linkcode CarPlayTexts.loadFailed} */
  errorTitle?: string
  /** The retry row's subtitle. Default: {@linkcode CarPlayTexts.retry} */
  errorSubtitle?: string
}

/** A button in a {@linkcode CarPlayGridTemplate} */
export interface CarPlayGridButton extends CarPlayAction {
  id: string
  title: string
  image: CarPlayImage
  /** Default: true */
  enabled?: boolean
}

/** A screen of up to eight icon buttons, such as a menu of genres */
export interface CarPlayGridTemplate extends CarPlayLazy {
  type: 'grid'
  id: string
  title: string
  /** CarPlay shows up to eight; may be left out when `lazy` */
  buttons?: CarPlayGridButton[]
  barButtons?: CarPlayBarButton[]
  tab?: CarPlayTab
  /** The retry button's title when a lazy grid fails to load. Default: {@linkcode CarPlayTexts.retry} */
  errorTitle?: string
}

/** A screen in CarPlay */
export type CarPlayTemplate = CarPlayListTemplate | CarPlayGridTemplate

/** Options for CarPlay's Now Playing screen, set through {@linkcode CarPlayRoot.nowPlaying} */
export interface CarPlayNowPlaying {
  /** Shows the Up Next button, which opens the playing queue (default: true) */
  upNext?: boolean
  /** Default: "Up Next" */
  upNextTitle?: string
  /** Makes the album and artist tappable; presses reach `CarPlayHelper.onAlbumArtistPress` (default: false) */
  albumArtist?: boolean
}

/** Singular and plural forms of a count; `{count}` is replaced with the number, as in `{count} songs` */
export interface CarPlayCountText {
  one: string
  other: string
}

/**
 * Texts the library shows by itself, such as on screens it opens for you, set through
 * {@linkcode CarPlayRoot.texts}. Each defaults to English.
 */
export interface CarPlayTexts {
  /** Shown while a lazy template loads. Default: "Loading…" */
  loading?: string
  /** Shown when a lazy template fails to load. Default: "Couldn't load" */
  loadFailed?: string
  /** The retry row's subtitle and the retry button's title. Default: "Tap to try again" in lists, "Try again" in grids */
  retry?: string
  /** An empty `queue` list, including Up Next. Default: "Nothing queued" */
  emptyQueue?: string
  /** An empty `playlists` list. Default: "No playlists" */
  noPlaylists?: string
  /** An empty `playlist` list, including playlists opened through `playlistId`. Default: "No tracks" */
  emptyPlaylist?: string
  /** The subtitle of playlists without a description in a `playlists` list. Default: `{count} track` / `{count} tracks` */
  trackCount?: CarPlayCountText
}

/**
 * Images shown when an item has none, or while its artwork loads, set through
 * {@linkcode CarPlayRoot.placeholders}. Each is an SF Symbol or asset catalog name.
 */
export interface CarPlayPlaceholders {
  /** For tracks and image row tiles. Default: `music.note` */
  artwork?: CarPlayImage
  /** For playlists in a `playlists` list. Default: `music.note.list` */
  playlist?: CarPlayImage
}

/** Everything CarPlay shows, set with `CarPlayHelper.set` */
export interface CarPlayRoot {
  /** Each becomes a tab, up to the car's limit (usually four); a single template shows without a tab bar */
  templates: CarPlayTemplate[]
  nowPlaying?: CarPlayNowPlaying
  texts?: CarPlayTexts
  placeholders?: CarPlayPlaceholders
}
