package com.margelo.nitro.nitroplayer.media

import android.content.Context
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Manages the Android Auto media library structure
 */
class MediaLibraryManager private constructor(
    context: Context,
) {
    @Volatile
    private var mediaLibrary: MediaLibrary? = null

    // The app answers these through resolve(): folders loaded on demand, and searches
    @Volatile
    var childrenRequester: ((requestId: String, parentId: String) -> Unit)? = null
        set(value) {
            field = value
            if (value != null) loaderRegistered.complete(Unit)
        }

    private val loaderRegistered = CompletableDeferred<Unit>()

    private var resumptionRequester: (() -> Unit)? = null
    private var resumptionPending = false

    // A resumption asked for before the app's JS registered its handler is delivered once it does
    fun setResumptionRequester(requester: () -> Unit) {
        val deliver =
            synchronized(this) {
                resumptionRequester = requester
                resumptionPending.also { resumptionPending = false }
            }
        if (deliver) requester()
    }

    fun requestResumption() {
        val requester = synchronized(this) { resumptionRequester.also { if (it == null) resumptionPending = true } }
        requester?.invoke()
    }

    @Volatile
    var searchRequester: ((requestId: String, query: String) -> Unit)? = null

    private val pending = ConcurrentHashMap<String, CompletableDeferred<String>>()

    private val firstPublish = CompletableDeferred<Unit>()

    // A car-only start asks for the root before the app's JS has published; wait once instead of showing "No items"
    suspend fun awaitFirstPublish(timeoutMs: Long) {
        withTimeoutOrNull(timeoutMs) { firstPublish.await() }
        firstPublish.complete(Unit)
    }

    /** Children of a folder the published library leaves empty, or null when the app has none to give. */
    private val inFlightChildren = ConcurrentHashMap<String, CompletableDeferred<List<MediaItem>?>>()

    // Folders loaded on demand are refreshed with the library, so the car never keeps a stale or failed answer
    val loadedFolderIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

    // An answer that missed the timeout is kept briefly and the car told to reload that folder
    private val lateChildren = ConcurrentHashMap<String, Pair<Long, List<MediaItem>>>()

    @Volatile
    var onLateChildren: ((parentId: String) -> Unit)? = null

    suspend fun loadChildren(parentId: String): List<MediaItem>? {
        // The car reopens remembered folders on connect, before a car-only start's JS has registered its loader
        if (childrenRequester == null) withTimeoutOrNull(FIRST_PUBLISH_WAIT_MS) { loaderRegistered.await() }
        loaderRegistered.complete(Unit)
        loadedFolderIds.add(parentId)
        lateChildren.remove(parentId)?.let { (at, items) -> if (System.currentTimeMillis() - at < LATE_CHILDREN_TTL_MS) return items }
        // The car asks for the same folder several times at once; answer them all from one app call
        val result = CompletableDeferred<List<MediaItem>?>()
        inFlightChildren.putIfAbsent(parentId, result)?.let { return it.await() }
        try {
            result.complete(request(childrenRequester, parentId, LOAD_CHILDREN_TIMEOUT_MS, lateFolder = parentId))
        } catch (e: Throwable) {
            result.completeExceptionally(e)
            throw e
        } finally {
            inFlightChildren.remove(parentId, result)
        }
        return result.await()
    }

    suspend fun search(query: String): List<MediaItem>? = request(searchRequester, query, SEARCH_TIMEOUT_MS)

    fun resolve(
        requestId: String,
        itemsJson: String,
    ) {
        pending.remove(requestId)?.complete(itemsJson)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    private suspend fun request(
        requester: ((String, String) -> Unit)?,
        argument: String,
        timeoutMs: Long,
        lateFolder: String? = null,
    ): List<MediaItem>? {
        val ask = requester ?: return null
        val requestId = UUID.randomUUID().toString()
        val answer = CompletableDeferred<String>()
        pending[requestId] = answer
        try {
            ask(requestId, argument)
        } catch (e: Throwable) {
            pending.remove(requestId)
            throw e
        }
        // A driver is waiting at the screen: past this the folder reads as empty
        val askedAt = System.currentTimeMillis()
        val json = withTimeoutOrNull(timeoutMs) { answer.await() }
        NitroPlayerLogger.log("MediaLibraryManager") { "'$argument' ${if (json == null) "timed out" else "answered"} after ${System.currentTimeMillis() - askedAt}ms" }
        if (json == null && lateFolder != null) {
            if (pending.size > MAX_PENDING) pending.clear()
            answer.invokeOnCompletion { error -> if (error == null) deliverLate(lateFolder, answer.getCompleted()) }
            return null
        }
        pending.remove(requestId)
        return json?.let { parseItems(it, argument) }
    }

    private fun deliverLate(
        parentId: String,
        json: String,
    ) {
        val items = parseItems(json, parentId) ?: return
        NitroPlayerLogger.log("MediaLibraryManager") { "Late answer for '$parentId', asking the car to reload it" }
        lateChildren[parentId] = System.currentTimeMillis() to items
        onLateChildren?.invoke(parentId)
    }

    private fun parseItems(
        json: String,
        argument: String,
    ): List<MediaItem>? =
        try {
            MediaLibraryParser.itemsFromJson(json)
        } catch (e: JSONException) {
            NitroPlayerLogger.log("MediaLibraryManager") { "Bad items JSON for '$argument': ${e.message}" }
            null
        }

    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: MediaLibraryManager? = null

        private const val LOAD_CHILDREN_TIMEOUT_MS = 10_000L
        private const val LATE_CHILDREN_TTL_MS = 60_000L
        private const val MAX_PENDING = 64
        private const val SEARCH_TIMEOUT_MS = 7_000L
        internal const val FIRST_PUBLISH_WAIT_MS = 3_000L

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
        firstPublish.complete(Unit)
        NitroPlayerLogger.log("MediaLibraryManager", "📚 MediaLibraryManager: Media library set with ${library.rootItems.size} root items")
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
        firstPublish.complete(Unit)
        NitroPlayerLogger.log("MediaLibraryManager", "📚 MediaLibraryManager: Media library cleared")
    }
}
