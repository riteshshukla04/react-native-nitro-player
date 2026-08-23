@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import android.app.Activity
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.margelo.nitro.NitroModules
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TimedMetadata
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.TrackPlayerState
import com.margelo.nitro.nitroplayer.connection.AndroidAutoConnectionDetector
import com.margelo.nitro.nitroplayer.download.DownloadManagerCore
import com.margelo.nitro.nitroplayer.media.ExoPlayerBuilder
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

    internal var remoteSkipForwardIntervalMs: Long = ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS
    internal var remoteSkipBackwardIntervalMs: Long = ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS
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
    internal val onTimedMetadataListeners =
        ListenerRegistry<(TimedMetadata) -> Unit>()
    internal val onCastStateChangeListeners =
        ListenerRegistry<(com.margelo.nitro.nitroplayer.CastState, String?) -> Unit>()
    internal val onNotificationLaunchListeners =
        ListenerRegistry<(TrackItem) -> Unit>()

    // ── Google Cast ──────────────────────────────────────────────────────────

    /** Set once the playback service has a usable CastContext; null when Cast is unavailable. */
    internal var castSessionController: com.margelo.nitro.nitroplayer.media.CastSessionController? = null

    /** True while the active backend is the CastPlayer (audio routed to a remote device). */
    @Volatile internal var isCastingField: Boolean = false

    /** Last track announced from a cast "waiting for URL" state — dedups onChangeTrack across updateTracks re-entries. */
    internal var lastCastWaitTrackId: String? = null

    // ── Progress & playlist-update runnables ───────────────────────────────

    /**
     * Emits progress once per second while actually playing (matching iOS), instead of
     * four times a second regardless of state. A paused player has nothing to report,
     * and every tick is a JS callback that re-renders every `useNowPlaying` consumer.
     * A seek still reports immediately via `onPositionDiscontinuity`.
     */
    internal val progressUpdateRunnable =
        object : Runnable {
            override fun run() {
                // Stop ticking while paused/idle — onIsPlayingChanged restarts it,
                // so the main looper isn't woken every second for the process lifetime
                if (!::exo.isInitialized || !exo.isPlaying) return
                val pos = exo.currentPosition / 1000.0
                val dur = if (exo.duration > 0) exo.duration / 1000.0 else 0.0
                notifyPlaybackProgress(pos, dur, if (isManuallySeeked) true else null)
                isManuallySeeked = false
                playerHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
            }
        }

    internal fun startProgressTicks() {
        playerHandler.removeCallbacks(progressUpdateRunnable)
        playerHandler.postDelayed(progressUpdateRunnable, PROGRESS_INTERVAL_MS)
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
    private var rebindAttempts = 0

    private val serviceConnection =
        object : ServiceConnection {
            override fun onServiceConnected(
                name: ComponentName?,
                service: IBinder?,
            ) {
                // Android can redeliver the MediaSessionService binder instead of
                // our LocalBinder (e.g. after the service is restarted). Guard the
                // cast and rebind explicitly with ACTION_LOCAL_BIND instead of crashing.
                val binder = service as? NitroPlayerPlaybackService.LocalBinder
                if (binder == null) {
                    NitroPlayerLogger.log("TrackPlayerCore") {
                        "onServiceConnected received unexpected binder: $service"
                    }
                    try {
                        context.unbindService(this)
                    } catch (_: Exception) {
                    }
                    serviceBound = false
                    if (rebindAttempts < 3) {
                        rebindAttempts++
                        handler.post {
                            val bindIntent =
                                Intent(context, NitroPlayerPlaybackService::class.java).apply {
                                    action = NitroPlayerPlaybackService.ACTION_LOCAL_BIND
                                }
                            context.bindService(
                                bindIntent,
                                this,
                                Context.BIND_AUTO_CREATE,
                            )
                        }
                    }
                    return
                }
                rebindAttempts = 0
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
        internal const val PROGRESS_INTERVAL_MS = 1000L

        @Volatile
        @Suppress("ktlint:standard:property-naming")
        private var INSTANCE: TrackPlayerCore? = null

        // applicationContext: the process-lifetime singleton must not pin the
        // ReactApplicationContext (and its whole JS runtime) across reloads
        fun getInstance(context: Context): TrackPlayerCore =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: TrackPlayerCore(context.applicationContext).also { INSTANCE = it }
            }
    }

    init {
        // Defer service start/bind to the main thread so it doesn't run
        // synchronously on the JNI thread during HybridObject creation.
        handler.post {
            // startService throws BackgroundServiceStartNotAllowedException on Android 12+
            // when the process is in the background — which is exactly what happens when JS
            // loads the module from a headless/backgrounded start. It is only here to keep
            // the service alive across unbind; BIND_AUTO_CREATE below already creates it,
            // and the service promotes itself to foreground once playback starts.
            try {
                context.startService(Intent(context, NitroPlayerPlaybackService::class.java))
            } catch (e: Exception) {
                NitroPlayerLogger.log("TrackPlayerCore") {
                    "startService skipped (app in background): ${e.message}"
                }
            }

            val bindIntent =
                Intent(context, NitroPlayerPlaybackService::class.java).apply {
                    action = NitroPlayerPlaybackService.ACTION_LOCAL_BIND
                }
            context.bindService(bindIntent, serviceConnection, Context.BIND_AUTO_CREATE)
        }
    }

    // ── Coroutine bridge to player looper (main thread) ────────────────────

    // ── Ordered command dispatch ───────────────────────────────────────────
    //
    // `Promise.async { … }` launches an unordered coroutine, so the hop onto the
    // player looper used to happen at an arbitrary later point: two calls made in
    // order from JS could reach the player in reverse order (play-then-pause landing
    // as pause-then-play). `enqueue` appends to a queue synchronously, on the JS
    // thread at call time, so execution order equals JS call order — including for
    // commands issued before the playback service has bound.

    private val pendingCommands = ArrayDeque<() -> Unit>()
    private var commandsDraining = false

    /**
     * Runs [block] on the player looper, preserving the order in which callers
     * enqueued. Safe to call before the service binds — commands buffer until then.
     */
    internal fun enqueue(block: () -> Unit) {
        synchronized(pendingCommands) {
            pendingCommands.addLast(block)
            if (commandsDraining) return
            if (!::playerHandler.isInitialized) return
            commandsDraining = true
        }
        playerHandler.post { drainCommands() }
    }

    private fun drainCommands() {
        while (true) {
            val next =
                synchronized(pendingCommands) {
                    val head = pendingCommands.removeFirstOrNull()
                    if (head == null) commandsDraining = false
                    head
                } ?: return
            next()
        }
    }

    /** Called once the player looper exists — flushes anything queued before binding. */
    internal fun startCommandDraining() {
        val shouldPost =
            synchronized(pendingCommands) {
                if (commandsDraining || pendingCommands.isEmpty()) {
                    false
                } else {
                    commandsDraining = true
                    true
                }
            }
        if (shouldPost) playerHandler.post { drainCommands() }
    }

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
        com.margelo.nitro.nitroplayer.media.AuthAwareHttpDataSourceFactory
            .clear()
        // Do NOT stop the service — it owns the player.
        // Unbind so Android can clean up if needed.
        if (serviceBound) {
            try {
                context.unbindService(serviceConnection)
            } catch (_: Exception) {
            }
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

    fun addOnTimedMetadataListener(cb: (TimedMetadata) -> Unit): Long = onTimedMetadataListeners.add(cb)

    fun removeOnTimedMetadataListener(id: Long): Boolean = onTimedMetadataListeners.remove(id)

    fun addOnAndroidAutoConnectionListener(cb: (Boolean) -> Unit): Long = onAndroidAutoConnectionListeners.add(cb)

    fun removeOnAndroidAutoConnectionListener(id: Long): Boolean = onAndroidAutoConnectionListeners.remove(id)

    fun addOnCastStateChangeListener(cb: (com.margelo.nitro.nitroplayer.CastState, String?) -> Unit): Long = onCastStateChangeListeners.add(cb)

    fun removeOnCastStateChangeListener(id: Long): Boolean = onCastStateChangeListeners.remove(id)

    // ── Notification-launch detection ─────────────────────────────────────

    private var notificationLaunchDetectionRegistered = false

    fun addOnNotificationLaunchListener(cb: (TrackItem) -> Unit): Long {
        val id = onNotificationLaunchListeners.add(cb)
        handler.post {
            registerNotificationLaunchDetection()
            checkNotificationLaunch(NitroModules.applicationContext?.currentActivity)
        }
        return id
    }

    fun removeOnNotificationLaunchListener(id: Long): Boolean = onNotificationLaunchListeners.remove(id)

    private fun registerNotificationLaunchDetection() {
        if (notificationLaunchDetectionRegistered) return
        notificationLaunchDetectionRegistered = true
        val app = context.applicationContext as? Application ?: return
        app.registerActivityLifecycleCallbacks(
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityResumed(activity: Activity) = checkNotificationLaunch(activity)

                override fun onActivityCreated(
                    activity: Activity,
                    savedInstanceState: Bundle?,
                ) {}

                override fun onActivityStarted(activity: Activity) {}

                override fun onActivityPaused(activity: Activity) {}

                override fun onActivityStopped(activity: Activity) {}

                override fun onActivitySaveInstanceState(
                    activity: Activity,
                    outState: Bundle,
                ) {}

                override fun onActivityDestroyed(activity: Activity) {}
            },
        )
    }

    // Must run on the main looper — reads the player and mutates the activity intent
    internal fun checkNotificationLaunch(activity: Activity?) {
        val intent = activity?.intent ?: return
        if (!intent.getBooleanExtra(NitroPlayerPlaybackService.EXTRA_STARTED_FROM_NOTIFICATION, false)) return
        val track = getCurrentTrack() ?: return
        intent.removeExtra(NitroPlayerPlaybackService.EXTRA_STARTED_FROM_NOTIFICATION)
        onNotificationLaunchListeners.forEach { it(track) }
    }
}
