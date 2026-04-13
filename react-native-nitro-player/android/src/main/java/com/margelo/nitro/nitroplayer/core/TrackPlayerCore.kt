@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.download.DownloadManagerCore
import com.margelo.nitro.nitroplayer.media.MediaLibraryManager
import com.margelo.nitro.nitroplayer.media.MediaSessionManager
import com.margelo.nitro.nitroplayer.media.NitroPlayerPlaybackService
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class TrackPlayerCore private constructor(
    internal val context: Context,
) {
    // ── Thread infrastructure ──────────────────────────────────────────────
    /** Main-looper handler — used for player operations and Android Auto callbacks. */
    internal val handler = Handler(Looper.getMainLooper())

    /** Populated from the service binder. Player runs on main looper. */
    internal lateinit var playerHandler: Handler

    internal val scope = CoroutineScope(SupervisorJob())

    /** Gates all player operations until the service is bound and init is complete. */
    private val serviceReady = CompletableDeferred<Unit>()

    // ── ExoPlayer wrapper (created on player thread inside initFromService) ──
    internal lateinit var exo: ExoPlayerCore

    /** Safe initialized check — backing field can only be read from the declaring class. */
    internal val isExoInitialized: Boolean get() = ::exo.isInitialized

    // ── Managers ───────────────────────────────────────────────────────────
    internal val playlistManager = PlaylistManager.getInstance(context)
    internal val downloadManager = DownloadManagerCore.getInstance(context)
    internal val mediaLibraryManager = MediaLibraryManager.getInstance(context)
    internal var mediaSessionManager: MediaSessionManager? = null

    // ── Playback state ─────────────────────────────────────────────────────
    @Volatile internal var currentPlaylistId: String? = null
    internal var isManuallySeeked = false

    @Volatile internal var isAndroidAutoConnectedField: Boolean = false
    internal var androidAutoConnectionDetector: AndroidAutoConnectionDetector? = null
    internal var previousMediaItem: androidx.media3.common.MediaItem? = null

    @Volatile internal var currentRepeatMode: RepeatMode = RepeatMode.OFF
    internal var lookaheadCount: Int = 5
    internal var playerListener: androidx.media3.common.Player.Listener? = null

    // ── Temporary queue ────────────────────────────────────────────────────
    internal var playNextStack: MutableList<TrackItem> = mutableListOf()
    internal var upNextQueue: MutableList<TrackItem> = mutableListOf()
    internal var currentTemporaryType: TemporaryType = TemporaryType.NONE
    internal var currentTracks: List<TrackItem> = emptyList()
    internal var currentTrackIndex: Int = -1

    internal enum class TemporaryType { NONE, PLAY_NEXT, UP_NEXT }

    // ── Listener registries ────────────────────────────────────────────────
    internal val onChangeTrackListeners =
        ListenerRegistry<(TrackItem, Reason?) -> Unit>()
    internal val onPlaybackStateChangeListeners =
        ListenerRegistry<(TrackPlayerState, Reason?) -> Unit>()
    internal val onSeekListeners =
        ListenerRegistry<(Double, Double) -> Unit>()
    internal val onProgressListeners =
        ListenerRegistry<(Double, Double, Boolean?) -> Unit>()
    internal val onTracksNeedUpdateListeners =
        ListenerRegistry<(List<TrackItem>, Int) -> Unit>()
    internal val onTemporaryQueueChangeListeners =
        ListenerRegistry<(List<TrackItem>, List<TrackItem>) -> Unit>()
    internal val onAndroidAutoConnectionListeners =
        ListenerRegistry<(Boolean) -> Unit>()

    // ── Progress & playlist-update runnables ───────────────────────────────
    internal val progressUpdateRunnable =
        object : Runnable {
            override fun run() {
                if (::exo.isInitialized &&
                    exo.playbackState != androidx.media3.common.Player.STATE_IDLE
                ) {
                    val pos = exo.currentPosition / 1000.0
                    val dur = if (exo.duration > 0) exo.duration / 1000.0 else 0.0
                    notifyPlaybackProgress(pos, dur, if (isManuallySeeked) true else null)
                    isManuallySeeked = false
                }
                playerHandler.postDelayed(this, 250)
            }
        }

    internal val updateCurrentPlaylistRunnable =
        Runnable {
            val id = currentPlaylistId ?: return@Runnable
            val playlist = playlistManager.getPlaylist(id) ?: return@Runnable
            currentTracks = playlist.tracks
            if (::exo.isInitialized &&
                exo.currentMediaItem != null &&
                exo.currentMediaItemIndex >= 0
            ) {
                rebuildQueueFromCurrentPosition()
            } else {
                updatePlayerQueue(playlist.tracks)
            }
            checkUpcomingTracksForUrls(lookaheadCount)
        }

    // ── Service binding ────────────────────────────────────────────────────
    private var serviceBound = false

    private val serviceConnection =
        object : ServiceConnection {
            override fun onServiceConnected(
                name: ComponentName?,
                service: IBinder?,
            ) {
                val binder = service as NitroPlayerPlaybackService.LocalBinder
                playerHandler = binder.handler
                binder.service.trackPlayerCore = this@TrackPlayerCore
                serviceBound = true

                // Initialize on main thread (player now runs on main looper)
                playerHandler.post {
                    initFromService(binder)
                    setupAndroidAutoDetector()
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                serviceBound = false
            }
        }

    // ── Singleton ──────────────────────────────────────────────────────────
    companion object {
        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: TrackPlayerCore? = null

        fun getInstance(context: Context): TrackPlayerCore =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: TrackPlayerCore(context).also { INSTANCE = it }
            }
    }

    init {
        // Defer service start/bind to the main thread so it doesn't run
        // synchronously on the JNI thread during HybridObject creation.
        handler.post {
            val intent = Intent(context, NitroPlayerPlaybackService::class.java)
            context.startService(intent)

            val bindIntent =
                Intent(context, NitroPlayerPlaybackService::class.java).apply {
                    action = NitroPlayerPlaybackService.ACTION_LOCAL_BIND
                }
            context.bindService(bindIntent, serviceConnection, Context.BIND_AUTO_CREATE)
        }
    }

    // ── Coroutine bridge to player looper (main thread) ────────────────────

    internal suspend fun <T> withPlayerContext(block: () -> T): T {
        // Wait until the service is bound and player is initialized
        serviceReady.await()
        if (Looper.myLooper() == playerHandler.looper) return block()
        return suspendCancellableCoroutine { cont ->
            val r =
                Runnable {
                    try {
                        cont.resume(block())
                    } catch (e: Exception) {
                        cont.resumeWithException(e)
                    }
                }
            playerHandler.post(r)
            cont.invokeOnCancellation { playerHandler.removeCallbacks(r) }
        }
    }

    /** Called from initFromService once everything is wired up. */
    internal fun completeServiceReady() {
        serviceReady.complete(Unit)
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    fun destroy() {
        if (::playerHandler.isInitialized) {
            playerHandler.post {
                androidAutoConnectionDetector?.unregisterCarConnectionReceiver()
                playerHandler.removeCallbacks(progressUpdateRunnable)
                if (::exo.isInitialized) {
                    playerListener?.let { exo.removeListener(it) }
                }
                playerListener = null
            }
        }
        scope.cancel()
        // Do NOT stop the service — it owns the player.
        // Unbind so Android can clean up if needed.
        if (serviceBound) {
            try {
                context.unbindService(serviceConnection)
            } catch (_: Exception) {}
            serviceBound = false
        }
    }

    // ── Simple read-only accessors ─────────────────────────────────────────

    fun isAndroidAutoConnected(): Boolean = isAndroidAutoConnectedField

    fun getCurrentPlaylistId(): String? = currentPlaylistId

    fun getPlaylistManager(): PlaylistManager = playlistManager

    fun getAllPlaylists(): List<com.margelo.nitro.nitroplayer.playlist.Playlist> = playlistManager.getAllPlaylists()

    // ── Listener add/remove (returns stable ID for cleanup) ───────────────

    fun addOnChangeTrackListener(cb: (TrackItem, Reason?) -> Unit): Long = onChangeTrackListeners.add(cb)

    fun removeOnChangeTrackListener(id: Long): Boolean = onChangeTrackListeners.remove(id)

    fun addOnPlaybackStateChangeListener(cb: (TrackPlayerState, Reason?) -> Unit): Long = onPlaybackStateChangeListeners.add(cb)

    fun removeOnPlaybackStateChangeListener(id: Long): Boolean = onPlaybackStateChangeListeners.remove(id)

    fun addOnSeekListener(cb: (Double, Double) -> Unit): Long = onSeekListeners.add(cb)

    fun removeOnSeekListener(id: Long): Boolean = onSeekListeners.remove(id)

    fun addOnPlaybackProgressChangeListener(cb: (Double, Double, Boolean?) -> Unit): Long = onProgressListeners.add(cb)

    fun removeOnPlaybackProgressChangeListener(id: Long): Boolean = onProgressListeners.remove(id)

    fun addOnTracksNeedUpdateListener(cb: (List<TrackItem>, Int) -> Unit): Long = onTracksNeedUpdateListeners.add(cb)

    fun removeOnTracksNeedUpdateListener(id: Long): Boolean = onTracksNeedUpdateListeners.remove(id)

    fun addOnTemporaryQueueChangeListener(cb: (List<TrackItem>, List<TrackItem>) -> Unit): Long = onTemporaryQueueChangeListeners.add(cb)

    fun removeOnTemporaryQueueChangeListener(id: Long): Boolean = onTemporaryQueueChangeListeners.remove(id)

    fun addOnAndroidAutoConnectionListener(cb: (Boolean) -> Unit): Long = onAndroidAutoConnectionListeners.add(cb)

    fun removeOnAndroidAutoConnectionListener(id: Long): Boolean = onAndroidAutoConnectionListeners.remove(id)
}
