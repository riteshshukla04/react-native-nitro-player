package com.margelo.nitro.nitroplayer.media

import android.content.Context
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import com.margelo.nitro.nitroplayer.R
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.playlist.PlaylistManager
import java.text.NumberFormat

/**
 * Thin wrapper around a [MediaSession] owned by the playback service.
 *
 * No longer creates the session, notification channel, or manages service
 * start/stop — the service handles all of that automatically per Media3 docs.
 */
@UnstableApi
class MediaSessionManager(
    private val context: Context,
    session: MediaSession,
    private val playlistManager: PlaylistManager,
) {
    private companion object {
        const val DEFAULT_REMOTE_SKIP_INTERVAL_MS = 15_000L
    }

    private var trackPlayerCore: TrackPlayerCore? = null

    fun setTrackPlayerCore(core: TrackPlayerCore) {
        trackPlayerCore = core
    }

    var mediaSession: MediaSession? = session
        private set

    @Volatile private var currentTrack: TrackItem? = null
    @Volatile private var isPlaying: Boolean = false

    private var androidAutoEnabled: Boolean = false
    private var carPlayEnabled: Boolean = false
    private var showInNotification: Boolean = true
    private var remoteSkipForwardIntervalMs: Long = DEFAULT_REMOTE_SKIP_INTERVAL_MS
    private var remoteSkipBackwardIntervalMs: Long = DEFAULT_REMOTE_SKIP_INTERVAL_MS

    init {
        updateMediaButtonPreferences()
    }

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
        remoteSkipForwardIntervalMs: Long,
        remoteSkipBackwardIntervalMs: Long,
    ) {
        androidAutoEnabled?.let { this.androidAutoEnabled = it }
        carPlayEnabled?.let { this.carPlayEnabled = it }
        showInNotification?.let { this.showInNotification = it }
        this.remoteSkipForwardIntervalMs = remoteSkipForwardIntervalMs
        this.remoteSkipBackwardIntervalMs = remoteSkipBackwardIntervalMs
        updateMediaButtonPreferences()
    }

    fun onTrackChanged(track: TrackItem?) {
        currentTrack = track
    }

    fun onPlaybackStateChanged(playing: Boolean) {
        isPlaying = playing
    }

    fun release() {
        // Service owns the session — just null out our reference
        mediaSession = null
    }

    private fun updateMediaButtonPreferences() {
        val session = mediaSession ?: return
        // Preferences replace Media3's default layout — prev/next must be declared or they vanish.
        // Compact only shows BACK / play-pause / FORWARD, so the ±N skips go to OVERFLOW; left in
        // the forward slot they push Next out of the compact notification entirely.
        val preserved = session.mediaButtonPreferences.filterNot { it.isManagedButton() }
        session.setMediaButtonPreferences(
            listOf(previousTrackButton(), nextTrackButton(), skipBackButton(), skipForwardButton()) + preserved,
        )
    }

    private fun previousTrackButton(): CommandButton =
        CommandButton
            .Builder(CommandButton.ICON_PREVIOUS)
            .setPlayerCommand(Player.COMMAND_SEEK_TO_PREVIOUS)
            .setSlots(CommandButton.SLOT_BACK)
            .setDisplayName(context.getString(R.string.nitro_player_previous_track))
            .build()

    private fun nextTrackButton(): CommandButton =
        CommandButton
            .Builder(CommandButton.ICON_NEXT)
            .setPlayerCommand(Player.COMMAND_SEEK_TO_NEXT)
            .setSlots(CommandButton.SLOT_FORWARD)
            .setDisplayName(context.getString(R.string.nitro_player_next_track))
            .build()

    private fun skipBackButton(): CommandButton =
        CommandButton
            .Builder(skipBackIcon(remoteSkipBackwardIntervalMs))
            .setPlayerCommand(Player.COMMAND_SEEK_BACK)
            .setSlots(CommandButton.SLOT_OVERFLOW)
            .setDisplayName(
                context.getString(
                    R.string.nitro_player_skip_back_seconds,
                    displaySeconds(remoteSkipBackwardIntervalMs),
                ),
            ).build()

    private fun skipForwardButton(): CommandButton =
        CommandButton
            .Builder(skipForwardIcon(remoteSkipForwardIntervalMs))
            .setPlayerCommand(Player.COMMAND_SEEK_FORWARD)
            .setSlots(CommandButton.SLOT_OVERFLOW)
            .setDisplayName(
                context.getString(
                    R.string.nitro_player_skip_forward_seconds,
                    displaySeconds(remoteSkipForwardIntervalMs),
                ),
            ).build()

    private fun CommandButton.isManagedButton(): Boolean =
        playerCommand == Player.COMMAND_SEEK_BACK ||
            playerCommand == Player.COMMAND_SEEK_FORWARD ||
            playerCommand == Player.COMMAND_SEEK_TO_PREVIOUS ||
            playerCommand == Player.COMMAND_SEEK_TO_NEXT

    private fun skipBackIcon(intervalMs: Long): Int =
        when (intervalMs) {
            5_000L -> CommandButton.ICON_SKIP_BACK_5
            10_000L -> CommandButton.ICON_SKIP_BACK_10
            15_000L -> CommandButton.ICON_SKIP_BACK_15
            30_000L -> CommandButton.ICON_SKIP_BACK_30
            else -> CommandButton.ICON_SKIP_BACK
        }

    private fun skipForwardIcon(intervalMs: Long): Int =
        when (intervalMs) {
            5_000L -> CommandButton.ICON_SKIP_FORWARD_5
            10_000L -> CommandButton.ICON_SKIP_FORWARD_10
            15_000L -> CommandButton.ICON_SKIP_FORWARD_15
            30_000L -> CommandButton.ICON_SKIP_FORWARD_30
            else -> CommandButton.ICON_SKIP_FORWARD
        }

    private fun displaySeconds(intervalMs: Long): String =
        NumberFormat
            .getNumberInstance()
            .apply {
                maximumFractionDigits = 3
                minimumFractionDigits = 0
                isGroupingUsed = false
            }.format(intervalMs / 1000.0)
}
