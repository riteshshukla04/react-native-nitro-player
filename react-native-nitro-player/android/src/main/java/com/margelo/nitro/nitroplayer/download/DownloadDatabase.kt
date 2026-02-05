package com.margelo.nitro.nitroplayer.download

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.margelo.nitro.core.NullType
import com.margelo.nitro.nitroplayer.*
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Manages persistence of downloaded track metadata using SharedPreferences
 */
class DownloadDatabase private constructor(
    private val context: Context,
) {
    companion object {
        private const val TAG = "DownloadDatabase"
        private const val PREFS_NAME = "NitroPlayerDownloads"
        private const val KEY_DOWNLOADED_TRACKS = "downloaded_tracks"
        private const val KEY_PLAYLIST_TRACKS = "playlist_tracks"

        @Volatile
        private var instance: DownloadDatabase? = null

        fun getInstance(context: Context): DownloadDatabase =
            instance ?: synchronized(this) {
                instance ?: DownloadDatabase(context.applicationContext).also { instance = it }
            }
    }

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val downloadedTracks = mutableMapOf<String, DownloadedTrackRecord>()
    private val playlistTracks = mutableMapOf<String, MutableSet<String>>()
    private val fileManager = DownloadFileManager.getInstance(context)

    init {
        loadFromDisk()
    }

    // Save Operations
    fun saveDownloadedTrack(
        track: DownloadedTrack,
        playlistId: String?,
    ) {
        synchronized(this) {
            val record =
                DownloadedTrackRecord(
                    trackId = track.trackId,
                    originalTrack = trackItemToRecord(track.originalTrack),
                    localPath = track.localPath,
                    localArtworkPath = track.localArtworkPath?.asSecondOrNull(),
                    downloadedAt = track.downloadedAt,
                    fileSize = track.fileSize,
                    storageLocation = track.storageLocation.name,
                )

            downloadedTracks[track.trackId] = record

            // Associate with playlist if provided
            playlistId?.let {
                if (playlistTracks[it] == null) {
                    playlistTracks[it] = mutableSetOf()
                }
                playlistTracks[it]?.add(track.trackId)
            }

            saveToDisk()
        }
    }

    // Query Operations
    fun isTrackDownloaded(trackId: String): Boolean {
        synchronized(this) {
            val record = downloadedTracks[trackId] ?: return false
            // Verify file still exists
            return File(record.localPath).exists()
        }
    }

    fun isPlaylistDownloaded(playlistId: String): Boolean {
        synchronized(this) {
            val trackIds = playlistTracks[playlistId] ?: return false
            if (trackIds.isEmpty()) return false

            // Get original playlist to check all tracks
            val playlist = PlaylistManager.getInstance(context).getPlaylist(playlistId) ?: return false

            // Check if all tracks are downloaded
            return playlist.tracks.all { track ->
                isTrackDownloaded(track.id)
            }
        }
    }

    fun isPlaylistPartiallyDownloaded(playlistId: String): Boolean {
        synchronized(this) {
            val trackIds = playlistTracks[playlistId] ?: return false
            if (trackIds.isEmpty()) return false

            // Check if at least one track is downloaded
            return trackIds.any { trackId ->
                isTrackDownloaded(trackId)
            }
        }
    }

    fun getDownloadedTrack(trackId: String): DownloadedTrack? {
        synchronized(this) {
            val record = downloadedTracks[trackId] ?: return null

            // Verify file still exists
            if (!File(record.localPath).exists()) {
                // File was deleted externally, clean up record
                downloadedTracks.remove(trackId)
                saveToDisk()
                return null
            }

            return recordToDownloadedTrack(record)
        }
    }

    fun getAllDownloadedTracks(): List<DownloadedTrack> {
        synchronized(this) {
            val validTracks = mutableListOf<DownloadedTrack>()
            val invalidTrackIds = mutableListOf<String>()

            for ((trackId, record) in downloadedTracks) {
                if (File(record.localPath).exists()) {
                    validTracks.add(recordToDownloadedTrack(record))
                } else {
                    invalidTrackIds.add(trackId)
                }
            }

            // Clean up invalid records
            if (invalidTrackIds.isNotEmpty()) {
                invalidTrackIds.forEach { downloadedTracks.remove(it) }
                saveToDisk()
            }

            return validTracks
        }
    }

    fun getDownloadedPlaylist(playlistId: String): DownloadedPlaylist? {
        synchronized(this) {
            val trackIds = playlistTracks[playlistId] ?: return null
            if (trackIds.isEmpty()) return null

            val playlist = PlaylistManager.getInstance(context).getPlaylist(playlistId) ?: return null

            val downloadedTracksList = mutableListOf<DownloadedTrack>()
            var totalSize = 0.0

            for (trackId in trackIds) {
                getDownloadedTrack(trackId)?.let { track ->
                    downloadedTracksList.add(track)
                    totalSize += track.fileSize
                }
            }

            if (downloadedTracksList.isEmpty()) return null

            val isComplete = downloadedTracksList.size == playlist.tracks.size

            return DownloadedPlaylist(
                playlistId = playlistId,
                originalPlaylist = convertPlaylistManagerToNitro(playlist),
                downloadedTracks = downloadedTracksList.toTypedArray(),
                totalSize = totalSize,
                downloadedAt = downloadedTracksList.minOfOrNull { it.downloadedAt } ?: System.currentTimeMillis().toDouble(),
                isComplete = isComplete,
            )
        }
    }

    fun getAllDownloadedPlaylists(): List<DownloadedPlaylist> {
        synchronized(this) {
            return playlistTracks.keys.mapNotNull { playlistId ->
                getDownloadedPlaylist(playlistId)
            }
        }
    }

    // Delete Operations
    fun deleteDownloadedTrack(trackId: String) {
        synchronized(this) {
            downloadedTracks[trackId]?.let { record ->
                // Delete the file
                fileManager.deleteFile(record.localPath)

                // Delete artwork if exists
                record.localArtworkPath?.let { artworkPath ->
                    fileManager.deleteFile(artworkPath)
                }
            }

            // Remove from records
            downloadedTracks.remove(trackId)

            // Remove from all playlist associations
            playlistTracks.forEach { (playlistId, trackIds) ->
                trackIds.remove(trackId)
                if (trackIds.isEmpty()) {
                    playlistTracks.remove(playlistId)
                }
            }

            saveToDisk()
        }
    }

    fun deleteDownloadedPlaylist(playlistId: String) {
        synchronized(this) {
            val trackIds = playlistTracks[playlistId]?.toList() ?: return

            // Delete all tracks in the playlist
            for (trackId in trackIds) {
                downloadedTracks[trackId]?.let { record ->
                    fileManager.deleteFile(record.localPath)
                    record.localArtworkPath?.let { fileManager.deleteFile(it) }
                }
                downloadedTracks.remove(trackId)
            }

            // Remove playlist association
            playlistTracks.remove(playlistId)

            saveToDisk()
        }
    }

    fun deleteAllDownloads() {
        synchronized(this) {
            // Delete all files
            for (record in downloadedTracks.values) {
                fileManager.deleteFile(record.localPath)
                record.localArtworkPath?.let { fileManager.deleteFile(it) }
            }

            // Clear all records
            downloadedTracks.clear()
            playlistTracks.clear()

            saveToDisk()
        }
    }

    /** Validates all downloads and removes records for missing files */
    fun syncDownloads(): Int {
        synchronized(this) {
            Log.d(TAG, "syncDownloads called")

            val trackIdsToRemove = mutableListOf<String>()

            for ((trackId, record) in downloadedTracks) {
                if (!File(record.localPath).exists()) {
                    Log.d(TAG, "Missing file for track $trackId: ${record.localPath}")
                    trackIdsToRemove.add(trackId)
                }
            }

            // Remove invalid records
            for (trackId in trackIdsToRemove) {
                downloadedTracks.remove(trackId)

                // Also remove from playlist associations
                val playlistsToClean = mutableListOf<String>()
                for ((playlistId, trackIds) in playlistTracks) {
                    if (trackIds.remove(trackId)) {
                        if (trackIds.isEmpty()) {
                            playlistsToClean.add(playlistId)
                        }
                    }
                }
                playlistsToClean.forEach { playlistTracks.remove(it) }
            }

            if (trackIdsToRemove.isNotEmpty()) {
                saveToDisk()
                Log.d(TAG, "Cleaned up ${trackIdsToRemove.size} orphaned records")
            } else {
                Log.d(TAG, "All downloads are valid")
            }

            return trackIdsToRemove.size
        }
    }

    // Persistence
    private fun saveToDisk() {
        try {
            // Save downloaded tracks
            val tracksJson = JSONObject()
            for ((trackId, record) in downloadedTracks) {
                tracksJson.put(trackId, record.toJson())
            }
            prefs.edit().putString(KEY_DOWNLOADED_TRACKS, tracksJson.toString()).apply()

            // Save playlist associations
            val playlistJson = JSONObject()
            for ((playlistId, trackIds) in playlistTracks) {
                playlistJson.put(playlistId, JSONArray(trackIds.toList()))
            }
            prefs.edit().putString(KEY_PLAYLIST_TRACKS, playlistJson.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun loadFromDisk() {
        try {
            // Load downloaded tracks
            val tracksString = prefs.getString(KEY_DOWNLOADED_TRACKS, null)
            if (tracksString != null) {
                val tracksJson = JSONObject(tracksString)
                for (trackId in tracksJson.keys()) {
                    val record = DownloadedTrackRecord.fromJson(tracksJson.getJSONObject(trackId))
                    downloadedTracks[trackId] = record
                }
            }

            // Load playlist associations
            val playlistString = prefs.getString(KEY_PLAYLIST_TRACKS, null)
            if (playlistString != null) {
                val playlistJson = JSONObject(playlistString)
                for (playlistId in playlistJson.keys()) {
                    val trackIdsArray = playlistJson.getJSONArray(playlistId)
                    val trackIds = mutableSetOf<String>()
                    for (i in 0 until trackIdsArray.length()) {
                        trackIds.add(trackIdsArray.getString(i))
                    }
                    playlistTracks[playlistId] = trackIds
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // Conversion Helpers
    private fun trackItemToRecord(track: TrackItem): TrackItemRecord =
        TrackItemRecord(
            id = track.id,
            title = track.title,
            artist = track.artist,
            album = track.album,
            duration = track.duration,
            url = track.url,
            artwork = track.artwork?.asSecondOrNull(),
        )

    private fun recordToTrackItem(record: TrackItemRecord): TrackItem {
        val artworkVariant =
            if (record.artwork != null) {
                Variant_NullType_String.create(record.artwork)
            } else {
                null
            }

        return TrackItem(
            id = record.id,
            title = record.title,
            artist = record.artist,
            album = record.album,
            duration = record.duration,
            url = record.url,
            artwork = artworkVariant,
            extraPayload = null,
        )
    }

    private fun recordToDownloadedTrack(record: DownloadedTrackRecord): DownloadedTrack {
        val localArtworkVariant =
            if (record.localArtworkPath != null) {
                Variant_NullType_String.create(record.localArtworkPath)
            } else {
                null
            }

        return DownloadedTrack(
            trackId = record.trackId,
            originalTrack = recordToTrackItem(record.originalTrack),
            localPath = record.localPath,
            localArtworkPath = localArtworkVariant,
            downloadedAt = record.downloadedAt,
            fileSize = record.fileSize,
            storageLocation = StorageLocation.valueOf(record.storageLocation),
        )
    }

    private fun convertPlaylistManagerToNitro(playlist: com.margelo.nitro.nitroplayer.playlist.Playlist): Playlist {
        // PlaylistManager already uses TrackItem from generated code with proper Variant types
        return Playlist(
            id = playlist.id,
            name = playlist.name,
            description = null, // PlaylistManager doesn't have description in Nitro Playlist
            artwork = null, // PlaylistManager doesn't have artwork in Nitro Playlist
            tracks = playlist.tracks.toTypedArray(),
        )
    }
}

// Internal record classes
internal data class DownloadedTrackRecord(
    val trackId: String,
    val originalTrack: TrackItemRecord,
    val localPath: String,
    val localArtworkPath: String?,
    val downloadedAt: Double,
    val fileSize: Double,
    val storageLocation: String,
) {
    fun toJson(): JSONObject =
        JSONObject().apply {
            put("trackId", trackId)
            put("originalTrack", originalTrack.toJson())
            put("localPath", localPath)
            put("localArtworkPath", localArtworkPath)
            put("downloadedAt", downloadedAt)
            put("fileSize", fileSize)
            put("storageLocation", storageLocation)
        }

    companion object {
        fun fromJson(json: JSONObject): DownloadedTrackRecord =
            DownloadedTrackRecord(
                trackId = json.getString("trackId"),
                originalTrack = TrackItemRecord.fromJson(json.getJSONObject("originalTrack")),
                localPath = json.getString("localPath"),
                localArtworkPath = json.optString("localArtworkPath", null),
                downloadedAt = json.getDouble("downloadedAt"),
                fileSize = json.getDouble("fileSize"),
                storageLocation = json.getString("storageLocation"),
            )
    }
}

internal data class TrackItemRecord(
    val id: String,
    val title: String,
    val artist: String,
    val album: String,
    val duration: Double,
    val url: String,
    val artwork: String?,
) {
    fun toJson(): JSONObject =
        JSONObject().apply {
            put("id", id)
            put("title", title)
            put("artist", artist)
            put("album", album)
            put("duration", duration)
            put("url", url)
            put("artwork", artwork)
        }

    companion object {
        fun fromJson(json: JSONObject): TrackItemRecord =
            TrackItemRecord(
                id = json.getString("id"),
                title = json.getString("title"),
                artist = json.getString("artist"),
                album = json.getString("album"),
                duration = json.getDouble("duration"),
                url = json.getString("url"),
                artwork = json.optString("artwork", null),
            )
    }
}
