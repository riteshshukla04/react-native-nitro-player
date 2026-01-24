package com.margelo.nitro.nitroplayer.download

import android.content.Context
import android.os.Environment
import android.os.StatFs
import com.margelo.nitro.nitroplayer.DownloadStorageInfo
import com.margelo.nitro.nitroplayer.StorageLocation
import java.io.File

/**
 * Manages file operations for downloaded tracks
 */
class DownloadFileManager private constructor(
    private val context: Context,
) {
    companion object {
        private const val PRIVATE_DOWNLOADS_FOLDER = "NitroPlayerDownloads"
        private const val PUBLIC_DOWNLOADS_FOLDER = "NitroPlayerMusic"

        @Volatile
        private var instance: DownloadFileManager? = null

        fun getInstance(context: Context): DownloadFileManager =
            instance ?: synchronized(this) {
                instance ?: DownloadFileManager(context.applicationContext).also { instance = it }
            }
    }

    private val privateDownloadsDir: File by lazy {
        File(context.filesDir, PRIVATE_DOWNLOADS_FOLDER).apply {
            if (!exists()) mkdirs()
        }
    }

    private val publicDownloadsDir: File by lazy {
        val publicDir =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                // On Android 10+, use app-specific external storage
                File(context.getExternalFilesDir(Environment.DIRECTORY_MUSIC), PUBLIC_DOWNLOADS_FOLDER)
            } else {
                // On older versions, use public Downloads directory
                @Suppress("DEPRECATION")
                File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), PUBLIC_DOWNLOADS_FOLDER)
            }
        publicDir.apply {
            if (!exists()) mkdirs()
        }
    }

    fun createDownloadFile(
        trackId: String,
        storageLocation: StorageLocation,
    ): File {
        val destinationDir =
            when (storageLocation) {
                StorageLocation.PRIVATE -> privateDownloadsDir
                StorageLocation.PUBLIC -> publicDownloadsDir
            }

        // Create unique filename based on trackId
        val fileName = "$trackId.mp3"
        return File(destinationDir, fileName)
    }

    fun deleteFile(path: String) {
        try {
            val file = File(path)
            if (file.exists()) {
                file.delete()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun getFileSize(path: String): Long =
        try {
            File(path).length()
        } catch (e: Exception) {
            0L
        }

    fun getStorageInfo(): DownloadStorageInfo {
        var totalDownloadedSize = 0L
        var trackCount = 0

        // Count files in private directory
        privateDownloadsDir.listFiles()?.forEach { file ->
            if (file.isFile) {
                totalDownloadedSize += file.length()
                trackCount++
            }
        }

        // Count files in public directory
        publicDownloadsDir.listFiles()?.forEach { file ->
            if (file.isFile) {
                totalDownloadedSize += file.length()
                trackCount++
            }
        }

        // Get device storage info
        val stat = StatFs(context.filesDir.path)
        val availableSpace = stat.availableBytes
        val totalSpace = stat.totalBytes

        // Get playlist count from database
        val playlistCount = DownloadDatabase.getInstance(context).getAllDownloadedPlaylists().size

        return DownloadStorageInfo(
            totalDownloadedSize = totalDownloadedSize.toDouble(),
            trackCount = trackCount.toDouble(),
            playlistCount = playlistCount.toDouble(),
            availableSpace = availableSpace.toDouble(),
            totalSpace = totalSpace.toDouble(),
        )
    }

    fun getLocalPath(trackId: String): String? {
        // Check private directory first
        val privateFile = File(privateDownloadsDir, "$trackId.mp3")
        if (privateFile.exists()) {
            return privateFile.absolutePath
        }

        // Check public directory
        val publicFile = File(publicDownloadsDir, "$trackId.mp3")
        if (publicFile.exists()) {
            return publicFile.absolutePath
        }

        return null
    }

    fun cleanupOrphanedFiles(validTrackIds: Set<String>): Long {
        var bytesFreed = 0L

        // Clean private directory
        privateDownloadsDir.listFiles()?.forEach { file ->
            val trackId = file.nameWithoutExtension
            if (trackId !in validTrackIds) {
                bytesFreed += file.length()
                file.delete()
            }
        }

        // Clean public directory
        publicDownloadsDir.listFiles()?.forEach { file ->
            val trackId = file.nameWithoutExtension
            if (trackId !in validTrackIds) {
                bytesFreed += file.length()
                file.delete()
            }
        }

        return bytesFreed
    }
}
