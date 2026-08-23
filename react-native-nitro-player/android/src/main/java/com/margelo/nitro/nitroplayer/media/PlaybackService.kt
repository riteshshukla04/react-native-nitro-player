package com.margelo.nitro.nitroplayer.media

import android.app.PendingIntent
import android.content.Intent
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.media3.cast.CastPlayer
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.android.gms.cast.framework.CastContext
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager

/**
 * Foreground service that **owns** the ExoPlayer and MediaSession.
 *
 * The player runs on the **main looper** so that Media3's
 * [MediaSessionService] can access it directly for automatic notification
 * management (foreground promotion, media-style notification, demotion).
 *
 * ExoPlayer does all heavy work (decoding, buffering, network I/O) on its
 * own internal threads — the application looper only handles lightweight
 * callbacks and control calls.
 */
@UnstableApi
class NitroPlayerPlaybackService : MediaSessionService() {

    companion object {
        const val ACTION_LOCAL_BIND = "com.margelo.nitro.nitroplayer.LOCAL_BIND"
        const val EXTRA_STARTED_FROM_NOTIFICATION = "com.margelo.nitro.nitroplayer.STARTED_FROM_NOTIFICATION"

        @Volatile
        var notificationSmallIconResName: String? = null
            set(value) {
                field = value
                instance?.let { service ->
                    service.mainHandler.post { service.applyNotificationSmallIcon() }
                }
            }

        @Volatile
        private var instance: NitroPlayerPlaybackService? = null
    }

    // ── Created in onCreate ────────────────────────────────────────────────
    private lateinit var player: ExoPlayer
    private var mediaSession: MediaSession? = null
    private var notificationProvider: DefaultMediaNotificationProvider? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Owns the CastPlayer + Cast session lifecycle; null when Cast is unavailable. */
    private var castSessionController: CastSessionController? = null

    @Volatile
    var trackPlayerCore: TrackPlayerCore? = null

    // ── Binder exposed to TrackPlayerCore ──────────────────────────────────
    inner class LocalBinder : Binder() {
        val service: NitroPlayerPlaybackService get() = this@NitroPlayerPlaybackService
        val exoPlayer: ExoPlayer get() = player
        val session: MediaSession get() = mediaSession!!
        val handler: Handler get() = mainHandler
        val castController: CastSessionController? get() = castSessionController
    }

    private val localBinder = lazy { LocalBinder() }

    // ── Lifecycle ───────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        NitroPlayerLogger.log("PlaybackService") { "onCreate" }
        instance = this

        // Build ExoPlayer on main looper (default)
        player = ExoPlayerBuilder.build(this)

        // Build MediaSession
        val playlistManager = PlaylistManager.getInstance(this)
        mediaSession = MediaSession
            .Builder(this, player)
            .setCallback(MediaSessionCallbackFactory.create(this, playlistManager))
            .apply { buildSessionActivity()?.let { setSessionActivity(it) } }
            .build()

        val provider = DefaultMediaNotificationProvider.Builder(this).build()
        notificationProvider = provider
        applyNotificationSmallIcon()
        setMediaNotificationProvider(provider)

        addSession(mediaSession!!)

        initCast()
    }

    /**
     * Initialize Google Cast. Best-effort: when Google Play services or the Cast
     * framework are unavailable (older devices, no Play services), the controller
     * stays null and all Cast features become inert no-ops.
     */
    private fun initCast() {
        try {
            val castContext = CastContext.getSharedInstance(this)
            // CastPlayer's seek increments are constructor-only, so a later
            // configure() cannot change them — the receiver always skips by the default.
            val castPlayer =
                CastPlayer(
                    castContext,
                    NitroMediaItemConverter(),
                    ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS,
                    ExoPlayerBuilder.DEFAULT_REMOTE_SKIP_INTERVAL_MS,
                )
            castSessionController =
                CastSessionController(
                    castContext = castContext,
                    castPlayer = castPlayer,
                    localPlayer = player,
                    mediaSession = mediaSession!!,
                    mainHandler = mainHandler,
                )
        } catch (e: Exception) {
            NitroPlayerLogger.log("PlaybackService") { "Cast unavailable: ${e.message}" }
            castSessionController = null
        }
    }

    // Content intent for the notification tap — newer Android has no fallback without it
    private fun buildSessionActivity(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launch.putExtra(EXTRA_STARTED_FROM_NOTIFICATION, true)
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    private fun applyNotificationSmallIcon() {
        val name = notificationSmallIconResName ?: return
        val provider = notificationProvider ?: return
        val resId = resources.getIdentifier(name, "drawable", packageName)
        if (resId == 0) {
            NitroPlayerLogger.log("PlaybackService") {
                "androidNotificationIcon '$name' not found in drawable resources — using default"
            }
            return
        }
        provider.setSmallIcon(resId)

        // Live Refresh :)
        val session = mediaSession
        if (session != null && session.player.isPlaying) {
            try {
                onUpdateNotification(session, false)
            } catch (e: Exception) {
                NitroPlayerLogger.log("PlaybackService") { "notification refresh failed: ${e.message}" }
            }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession

    override fun onBind(intent: Intent?): IBinder? {
        if (intent?.action == ACTION_LOCAL_BIND) {
            return localBinder.value
        }
        return super.onBind(intent)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val session = mediaSession
        if (session == null || !session.player.playWhenReady) {
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        NitroPlayerLogger.log("PlaybackService") { "onDestroy" }
        if (instance === this) instance = null
        notificationProvider = null
        castSessionController?.release()
        castSessionController = null
        mediaSession?.release()
        mediaSession = null
        player.release()
        super.onDestroy()
    }
}
