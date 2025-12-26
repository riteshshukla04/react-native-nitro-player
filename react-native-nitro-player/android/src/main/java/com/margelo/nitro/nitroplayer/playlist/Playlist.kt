package com.margelo.nitro.nitroplayer.playlist

import com.margelo.nitro.nitroplayer.TrackItem

/**
 * Represents a playlist containing multiple tracks
 * Uses ExoPlayer's native playlist functionality
 */
data class Playlist(
    val id: String,
    val name: String,
    val description: String? = null,
    val artwork: String? = null,
    val tracks: MutableList<TrackItem> = mutableListOf(),
) {
    fun toTrackItemArray(): Array<TrackItem> = tracks.toTypedArray()

    fun getTrackCount(): Int = tracks.size

    fun isEmpty(): Boolean = tracks.isEmpty()
}
