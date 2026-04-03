@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.util.LruCache
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaNotification
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.margelo.nitro.nitroplayer.core.NitroPlayerLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

/**
 * Custom notification provider that manually builds a [MediaStyle][androidx.media.app.NotificationCompat.MediaStyle]
 * notification with artwork, title, artist, and transport controls — matching
 * the proven approach from the main branch.
 */
@UnstableApi
class NitroPlayerNotificationProvider(
    private val context: Context,
) : MediaNotification.Provider {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val artworkCache =
        object : LruCache<String, Bitmap>(20) {
            override fun sizeOf(key: String, value: Bitmap): Int = 1
        }

    companion object {
        const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "nitro_player_channel"
        private const val CHANNEL_NAME = "Music Player"
    }

    init {
        createNotificationChannel()
    }

    override fun createNotification(
        mediaSession: MediaSession,
        customLayout: ImmutableList<CommandButton>,
        actionFactory: MediaNotification.ActionFactory,
        onNotificationChangedCallback: MediaNotification.Provider.Callback,
    ): MediaNotification {
        val player = mediaSession.player
        val metadata = player.mediaMetadata
        val isPlaying = player.isPlaying

        val contentIntent =
            PendingIntent.getActivity(
                context,
                0,
                context.packageManager.getLaunchIntentForPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val builder =
            NotificationCompat
                .Builder(context, CHANNEL_ID)
                .setContentTitle(metadata.title ?: "Unknown Title")
                .setContentText(metadata.artist ?: "Unknown Artist")
                .setSubText(metadata.albumTitle ?: "")
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(contentIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(isPlaying)
                .setShowWhen(false)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_TRANSPORT)

        // MediaStyle with session token
        try {
            val compatToken =
                android.support.v4.media.session.MediaSessionCompat.Token
                    .fromToken(mediaSession.platformToken)
            builder.setStyle(
                androidx.media.app.NotificationCompat
                    .MediaStyle()
                    .setMediaSession(compatToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )
        } catch (e: Exception) {
            NitroPlayerLogger.log("NotificationProvider") { "Failed to set media session token: ${e.message}" }
        }

        // Transport actions using media button PendingIntents
        builder.addAction(
            android.R.drawable.ic_media_previous,
            "Previous",
            buildMediaButtonIntent(KeyEvent.KEYCODE_MEDIA_PREVIOUS, 0),
        )

        if (isPlaying) {
            builder.addAction(
                android.R.drawable.ic_media_pause,
                "Pause",
                buildMediaButtonIntent(KeyEvent.KEYCODE_MEDIA_PAUSE, 1),
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_media_play,
                "Play",
                buildMediaButtonIntent(KeyEvent.KEYCODE_MEDIA_PLAY, 1),
            )
        }

        builder.addAction(
            android.R.drawable.ic_media_next,
            "Next",
            buildMediaButtonIntent(KeyEvent.KEYCODE_MEDIA_NEXT, 2),
        )

        // Load artwork async and update notification
        metadata.artworkUri?.toString()?.let { artworkUrl ->
            val cached = artworkCache.get(artworkUrl)
            if (cached != null) {
                builder.setLargeIcon(cached)
            } else {
                scope.launch {
                    val bitmap = loadArtworkBitmap(artworkUrl)
                    if (bitmap != null) {
                        builder.setLargeIcon(bitmap)
                        onNotificationChangedCallback.onNotificationChanged(
                            MediaNotification(NOTIFICATION_ID, builder.build()),
                        )
                    }
                }
            }
        }

        return MediaNotification(NOTIFICATION_ID, builder.build())
    }

    override fun handleCustomCommand(
        session: MediaSession,
        action: String,
        extras: Bundle,
    ): Boolean = false

    private fun buildMediaButtonIntent(keyCode: Int, requestCode: Int): PendingIntent {
        val intent =
            Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                setPackage(context.packageName)
            }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Media playback controls"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private suspend fun loadArtworkBitmap(artworkUrl: String): Bitmap? {
        artworkCache.get(artworkUrl)?.let { return it }
        return try {
            withContext(Dispatchers.IO) {
                val url = URL(artworkUrl)
                BitmapFactory.decodeStream(url.openConnection().getInputStream())
            }?.also { artworkCache.put(artworkUrl, it) }
        } catch (_: Exception) {
            null
        }
    }
}
