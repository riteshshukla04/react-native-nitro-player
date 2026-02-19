package com.margelo.nitro.nitroplayer.storage

import android.content.Context
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import java.io.File

object NitroPlayerStorage {
    private const val TAG = "NitroPlayerStorage"
    private const val DIR_NAME = "nitroplayer"

    /** Reads the contents of [filename] from the NitroPlayer storage directory, or null if absent. */
    fun read(context: Context, filename: String): String? {
        val file = File(storageDirectory(context), filename)
        return if (file.exists()) {
            try {
                file.readText()
            } catch (e: Exception) {
                NitroPlayerLogger.log(TAG, "read($filename) failed: $e")
                null
            }
        } else {
            null
        }
    }

    /**
     * Atomically writes [json] to [filename] in the NitroPlayer storage directory.
     * Writes to `<filename>.tmp` first, then renames — leaving the prior file
     * untouched on failure (crash-safe).
     */
    fun write(context: Context, filename: String, json: String) {
        try {
            val dir = storageDirectory(context)
            dir.mkdirs()
            val tmp = File(dir, "$filename.tmp")
            val dest = File(dir, filename)
            tmp.writeText(json)
            if (!tmp.renameTo(dest)) {
                // renameTo can fail across mount points; copy then delete as fallback
                dest.writeText(tmp.readText())
                tmp.delete()
            }
        } catch (e: Exception) {
            NitroPlayerLogger.log(TAG, "write($filename) failed: $e")
        }
    }

    /** Returns the NitroPlayer subdirectory inside filesDir. */
    private fun storageDirectory(context: Context): File = File(context.filesDir, DIR_NAME)
}
