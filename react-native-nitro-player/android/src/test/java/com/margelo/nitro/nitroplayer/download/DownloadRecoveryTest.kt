package com.margelo.nitro.nitroplayer.download

import android.content.Context
import android.os.Looper
import androidx.work.Data
import androidx.work.impl.WorkManagerImpl
import com.margelo.nitro.nitroplayer.DownloadState
import com.margelo.nitro.nitroplayer.DownloadedTrack
import com.margelo.nitro.nitroplayer.TrackItem
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.util.concurrent.ConcurrentHashMap

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class DownloadRecoveryTest {
    private lateinit var manager: DownloadManagerCore
    private lateinit var database: DownloadDatabase
    private var originalDatabase: Any? = null
    private var originalFileManager: Any? = null

    @Before
    fun setUp() {
        val context = RuntimeEnvironment.getApplication() as Context
        database = mock(DownloadDatabase::class.java)
        originalDatabase = replaceSingleton(DownloadDatabase::class.java, database)
        originalFileManager = replaceSingleton(DownloadFileManager::class.java, mock(DownloadFileManager::class.java))
        WorkManagerImpl.setDelegate(mock(WorkManagerImpl::class.java))
        val constructor = DownloadManagerCore::class.java.getDeclaredConstructor(Context::class.java)
        constructor.isAccessible = true
        manager = constructor.newInstance(context)
    }

    @After
    fun tearDown() {
        WorkManagerImpl.setDelegate(null)
        replaceSingleton(DownloadDatabase::class.java, originalDatabase)
        replaceSingleton(DownloadFileManager::class.java, originalFileManager)
    }

    @Test
    fun `older jobs recover required fields when optional metadata was never saved`() {
        val track = worker(Data.EMPTY).buildLegacyTrackFromInput("track", "Episode", "https://audio.test/episode.mp3")

        assertEquals("track", track.id)
        assertEquals("Episode", track.title)
        assertEquals("https://audio.test/episode.mp3", track.url)
        assertEquals("", track.artist)
        assertEquals("", track.album)
        assertEquals(0.0, track.duration, 0.0)
        assertNull(track.artwork)
        assertNull(track.extraPayload)
    }

    @Test
    fun `legacy scalar metadata survives recovery`() {
        val data = Data.Builder()
            .putString("track_artist", "Author")
            .putString("track_album", "Podcast")
            .putDouble("track_duration", 123.5)
            .putString("track_artwork", "https://audio.test/artwork.jpg")
            .build()

        val track = worker(data).buildLegacyTrackFromInput("track", "Episode", "https://audio.test/episode.mp3")

        assertEquals("Author", track.artist)
        assertEquals("Podcast", track.album)
        assertEquals(123.5, track.duration, 0.0)
        assertEquals("https://audio.test/artwork.jpg", track.artwork?.asSecondOrNull())
    }

    @Test
    fun `empty legacy artwork stays absent`() {
        val data = Data.Builder().putString("track_artwork", "").build()

        assertNull(worker(data).buildLegacyTrackFromInput("track", "Episode", "url").artwork)
    }

    @Test
    fun `a fresh manager registers a completed download from persisted metadata`() {
        val track = track("Persisted title")
        val completed = mutableListOf<DownloadedTrack>()
        manager.addCompleteCallback { completed.add(it) }

        manager.onComplete("download", "track", "/audio/episode.mp3", track)
        shadowOf(Looper.getMainLooper()).idle()

        val saved = savedTrack()
        assertSame(track, saved.originalTrack)
        assertEquals("/audio/episode.mp3", saved.localPath)
        assertEquals(listOf(saved), completed)
    }

    @Test
    fun `in memory metadata takes precedence over the persisted fallback`() {
        val current = track("Current title")
        field<ConcurrentHashMap<String, TrackItem>>("trackMetadata")["track"] = current

        manager.onComplete("download", "track", "/audio/episode.mp3", track("Older title"))

        assertSame(current, savedTrack().originalTrack)
    }

    @Test
    fun `missing metadata completes polling and releases the concurrency slot without inventing a record`() {
        val metadata = DownloadTaskMetadata("download", "track", null, DownloadState.DOWNLOADING, 1.0)
        val tasks = field<ConcurrentHashMap<String, DownloadTaskMetadata>>("activeTasks")
        val running = field<MutableSet<String>>("runningDownloads")
        tasks["download"] = metadata
        running.add("download")
        val states = mutableListOf<DownloadState>()
        val completed = mutableListOf<DownloadedTrack>()
        manager.addStateChangeCallback { id, trackId, state, error ->
            assertEquals("download", id)
            assertEquals("track", trackId)
            assertNull(error)
            states.add(state)
        }
        manager.addCompleteCallback { completed.add(it) }

        manager.onComplete("download", "track", "/audio/episode.mp3")
        shadowOf(Looper.getMainLooper()).idle()

        assertFalse(tasks.containsKey("download"))
        assertFalse(running.contains("download"))
        assertEquals(DownloadState.COMPLETED, metadata.state)
        assertNotNull(metadata.completedAt)
        assertEquals(listOf(DownloadState.COMPLETED), states)
        assertTrue(completed.isEmpty())
        verifyNoInteractions(database)
    }

    private fun savedTrack(): DownloadedTrack {
        val calls = mockingDetails(database).invocations.filter { it.method.name == "saveDownloadedTrack" }
        assertEquals(1, calls.size)
        assertNull(calls.single().arguments[1])
        return calls.single().arguments[0] as DownloadedTrack
    }

    private fun worker(data: Data): DownloadWorker = mock(DownloadWorker::class.java, CALLS_REAL_METHODS).also {
        doReturn(data).`when`(it).inputData
    }

    private fun track(title: String) = TrackItem("track", title, "Author", "Podcast", 123.5, "url", null, null)

    @Suppress("UNCHECKED_CAST")
    private fun <T> field(name: String): T = DownloadManagerCore::class.java.getDeclaredField(name).let {
        it.isAccessible = true
        it.get(manager) as T
    }

    private fun replaceSingleton(type: Class<*>, value: Any?): Any? = type.getDeclaredField("instance").let {
        it.isAccessible = true
        val previous = it.get(null)
        it.set(null, value)
        previous
    }
}
