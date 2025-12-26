package com.margelo.nitro.nitroplayer.queue

import com.margelo.nitro.nitroplayer.QueueOperation
import com.margelo.nitro.nitroplayer.TrackItem
import java.util.concurrent.CopyOnWriteArrayList

/**
 * QueueManager is a singleton that manages the queue state across the app session.
 * It provides thread-safe access to the queue and notifies listeners of queue changes.
 */
class QueueManager private constructor() {
    private val queue = Queue()
    private val listeners = CopyOnWriteArrayList<(List<TrackItem>, QueueOperation?) -> Unit>()

    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: QueueManager? = null

        /**
         * Get the singleton instance of QueueManager
         */
        @JvmStatic
        fun getInstance(): QueueManager =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: QueueManager().also { INSTANCE = it }
            }
    }

    /**
     * Get the current queue
     */
    fun getQueue(): Queue = queue

    /**
     * Get all tracks in the queue
     */
    fun getTracks(): List<TrackItem> = queue.getTracks()

    /**
     * Get tracks as an array
     */
    fun getTracksArray(): Array<TrackItem> = queue.getTracksArray()

    /**
     * Load multiple tracks into the queue (replaces existing queue)
     */
    fun loadQueue(tracks: Array<TrackItem>) {
        queue.loadTracks(tracks.toList())
        notifyListeners(QueueOperation.ADD)
    }

    /**
     * Load a single track at a specific index
     */
    fun loadSingleTrack(
        track: TrackItem,
        index: Double?,
    ) {
        val insertIndex = index?.toInt()
        if (insertIndex != null && insertIndex >= 0) {
            queue.addTrackAtIndex(track, insertIndex)
        } else {
            queue.addTrack(track)
        }
        notifyListeners(QueueOperation.ADD)
    }

    /**
     * Delete a track by ID
     */
    fun deleteTrack(id: String) {
        val removed = queue.removeTrack(id)
        if (removed) {
            notifyListeners(QueueOperation.REMOVE)
        }
    }

    /**
     * Clear all tracks from the queue
     */
    fun clearQueue() {
        queue.clear()
        notifyListeners(QueueOperation.CLEAR)
    }

    /**
     * Add a listener for queue changes
     * @param listener Callback that receives (queue, operation)
     * @return A function to remove the listener
     */
    fun addQueueChangeListener(listener: (List<TrackItem>, QueueOperation?) -> Unit): () -> Unit {
        listeners.add(listener)
        return { listeners.remove(listener) }
    }

    /**
     * Remove a queue change listener
     */
    fun removeQueueChangeListener(listener: (List<TrackItem>, QueueOperation?) -> Unit) {
        listeners.remove(listener)
    }

    /**
     * Notify all listeners of queue changes
     */
    private fun notifyListeners(operation: QueueOperation?) {
        val currentTracks = queue.getTracks()
        listeners.forEach { listener ->
            try {
                listener(currentTracks, operation)
            } catch (e: Exception) {
                // Log error but don't break other listeners
                e.printStackTrace()
            }
        }
    }

    /**
     * Get queue size
     */
    fun getQueueSize(): Int = queue.size()

    /**
     * Check if queue is empty
     */
    fun isQueueEmpty(): Boolean = queue.isEmpty()

    /**
     * Get a track by index
     */
    fun getTrack(index: Int): TrackItem? = queue.getTrack(index)

    /**
     * Get a track by ID
     */
    fun getTrackById(id: String): TrackItem? = queue.getTrackById(id)

    /**
     * Get the index of a track by ID
     */
    fun getTrackIndex(id: String): Int = queue.getTrackIndex(id)
}
