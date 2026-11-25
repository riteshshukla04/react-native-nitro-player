package com.margelo.nitro.nitroplayer.download

import android.content.Context
import android.os.Environment
import android.os.StatFs
import com.margelo.nitro.nitroplayer.DownloadStorageInfo
import com.margelo.nitro.nitroplayer.StorageLocation
import java.io.File
import java.io.IOException

/**
 * Manages file operations for downloaded tracks
 */
class DownloadFileManager private constructor(
    private val context: Context,
) {
    companion object {
        private const val PRIVATE_DOWNLOADS_FOLDER = "NitroPlayerDownloads"
        private const val PUBLIC_DOWNLOADS_FOLDER = "NitroPlayerMusic"

        // Unfinished downloads, one file per download id, apart from the finished tracks
        private const val PARTIAL_FOLDER = ".partial"
        private const val PARTIAL_EXTENSION = "part"

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

    private fun destinationDir(storageLocation: StorageLocation): File =
        when (storageLocation) {
            StorageLocation.PRIVATE -> privateDownloadsDir
            StorageLocation.PUBLIC -> publicDownloadsDir
        }

    fun createDownloadFile(
        trackId: String,
        storageLocation: StorageLocation,
        extension: String = "mp3",
    ): File {
        // Create unique filename based on trackId
        val fileName = "$trackId.$extension"
        return File(destinationDir(storageLocation), fileName)
    }

    /**
     * The file one download writes and resumes from until it finishes. It is named by download
     * id, so downloads of the same track never share bytes, and it sits in its storage
     * location's folder, so moving it into place is a rename on the same filesystem.
     */
    fun getPartialFile(
        downloadId: String,
        storageLocation: StorageLocation,
    ): File {
        val partialDir = File(destinationDir(storageLocation), PARTIAL_FOLDER).apply { mkdirs() }
        return File(partialDir, "$downloadId.$PARTIAL_EXTENSION")
    }

    /** Moves a finished download into place as the track's file, replacing any older copy. */
    fun commitPartialFile(
        partialFile: File,
        destination: File,
    ) {
        if (!partialFile.renameTo(destination)) {
            throw IOException("Could not move ${partialFile.name} to ${destination.name}")
        }
    }

    /** Deletes the download's partial file, in either storage location. */
    fun deletePartialFiles(downloadId: String) {
        downloadDirs().forEach { File(File(it, PARTIAL_FOLDER), "$downloadId.$PARTIAL_EXTENSION").delete() }
    }

    private fun downloadDirs(): List<File> = listOf(privateDownloadsDir, publicDownloadsDir)

    private fun partialFiles(): List<File> =
        downloadDirs().flatMap { dir ->
            File(dir, PARTIAL_FOLDER).listFiles()?.filter { it.isFile } ?: emptyList()
        }

    // Finished tracks only: the partial folder is skipped
    private fun trackFiles(): List<File> =
        downloadDirs().flatMap { dir ->
            dir.listFiles()?.filter { it.isFile } ?: emptyList()
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

        trackFiles().forEach { file ->
            totalDownloadedSize += file.length()
            trackCount++
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

    fun cleanupOrphanedFiles(validTrackIds: Set<String>): Long {
        var bytesFreed = 0L
        trackFiles().forEach { file ->
            if (file.nameWithoutExtension !in validTrackIds) {
                bytesFreed += file.length()
                file.delete()
            }
        }
        return bytesFreed
    }

    /**
     * Deletes the partial files of downloads that are over. [liveDownloadIds] names the
     * downloads that may still write or resume theirs; it is asked only after the files are
     * listed, so a download that starts meanwhile can't lose a file it just created.
     */
    fun cleanupStalePartialFiles(liveDownloadIds: () -> Set<String>?): Long {
        val partials = partialFiles()
        if (partials.isEmpty()) return 0L
        val live = liveDownloadIds() ?: return 0L
        var bytesFreed = 0L
        partials.filter { it.nameWithoutExtension !in live }.forEach { file ->
            bytesFreed += file.length()
            file.delete()
        }
        return bytesFreed
    }
}
