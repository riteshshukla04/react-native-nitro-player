package com.margelo.nitro.nitroplayer.media

import com.margelo.nitro.nitroplayer.Variant_NullType_String

/**
 * Layout type for Android Auto media browser
 */
enum class LayoutType {
    GRID,
    LIST,
}

/**
 * Media type for different kinds of content
 */
enum class MediaType {
    FOLDER,
    AUDIO,
    PLAYLIST,
}

/**
 * Media item that can be displayed in Android Auto
 */
data class MediaItem(
    /** Unique identifier for the media item */
    val id: String,
    /** Display title */
    val title: String,
    /** Optional subtitle/description */
    val subtitle: String? = null,
    /** Optional icon/artwork URL */
    val iconUrl: String? = null,
    /** Whether this item can be played directly */
    val isPlayable: Boolean = false,
    /** Media type */
    val mediaType: MediaType = MediaType.FOLDER,
    /** Reference to playlist ID (for playlist items) */
    val playlistId: String? = null,
    /** Child items for browsable folders */
    val children: List<MediaItem>? = null,
    /** Layout type for folder items (overrides library default) */
    val layoutType: LayoutType? = null,
)

/**
 * Media library structure for Android Auto
 */
data class MediaLibrary(
    /** Layout type for the media browser (applies to all folders by default) */
    val layoutType: LayoutType = LayoutType.LIST,
    /** Root level media items */
    val rootItems: List<MediaItem> = emptyList(),
    /** Optional app name to display */
    val appName: String? = null,
    /** Optional app icon URL */
    val appIconUrl: String? = null,
)
