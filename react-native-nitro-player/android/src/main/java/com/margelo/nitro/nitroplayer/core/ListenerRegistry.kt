package com.margelo.nitro.nitroplayer.core

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

/**
 * Thread-safe listener registry with stable numeric IDs for add/remove.
 * Uses CopyOnWriteArrayList for lock-free iteration and AtomicLong for ID generation.
 */
class ListenerRegistry<T> {
    private data class Entry<T>(
        val id: Long,
        val callback: T,
    )

    private val entries = CopyOnWriteArrayList<Entry<T>>()
    private val nextId = AtomicLong(0)

    /** Register a callback and return its stable ID for later removal. */
    fun add(callback: T): Long {
        val id = nextId.incrementAndGet()
        entries.add(Entry(id, callback))
        return id
    }

    /** Remove the callback with the given ID. Returns true if found. */
    fun remove(id: Long): Boolean {
        val iterator = entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.id == id) {
                entries.remove(entry)
                return true
            }
        }
        return false
    }

    /** Remove all registered callbacks. */
    fun clear() = entries.clear()

    /** Invoke action for every registered callback (snapshot iteration — safe under mutation). */
    fun forEach(action: (T) -> Unit) {
        for (entry in entries) {
            action(entry.callback)
        }
    }

    /** True when no callbacks are registered. */
    val isEmpty: Boolean get() = entries.isEmpty()
}
