package com.margelo.nitro.nitroplayer.media

import android.content.Context

/**
 * Manages the Android Auto media library structure
 */
class MediaLibraryManager private constructor(
    context: Context,
) {
    @Volatile
    private var mediaLibrary: MediaLibrary? = null

    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: MediaLibraryManager? = null

        fun getInstance(context: Context): MediaLibraryManager =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: MediaLibraryManager(context).also { INSTANCE = it }
            }
    }

    /**
     * Set the media library structure
     */
    fun setMediaLibrary(library: MediaLibrary) {
        mediaLibrary = library
        println("📚 MediaLibraryManager: Media library set with ${library.rootItems.size} root items")
    }

    /**
     * Get the current media library
     */
    fun getMediaLibrary(): MediaLibrary? = mediaLibrary

    /**
     * Get media item by ID (searches recursively)
     */
    fun getMediaItemById(itemId: String): MediaItem? {
        val library = mediaLibrary ?: return null
        return findMediaItemRecursive(library.rootItems, itemId)
    }

    private fun findMediaItemRecursive(
        items: List<MediaItem>,
        targetId: String,
    ): MediaItem? {
        for (item in items) {
            if (item.id == targetId) {
                return item
            }
            item.children?.let { children ->
                val found = findMediaItemRecursive(children, targetId)
                if (found != null) return found
            }
        }
        return null
    }

    /**
     * Get children of a media item by ID
     */
    fun getChildrenById(parentId: String): List<MediaItem>? {
        val item = getMediaItemById(parentId)
        return item?.children
    }

    /**
     * Clear the media library
     */
    fun clear() {
        mediaLibrary = null
        println("📚 MediaLibraryManager: Media library cleared")
    }
}
