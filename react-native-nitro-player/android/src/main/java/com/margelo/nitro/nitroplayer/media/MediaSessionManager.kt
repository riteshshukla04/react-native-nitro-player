package com.margelo.nitro.nitroplayer.media

import android.content.Context
import android.os.Bundle
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionCommands
import com.margelo.nitro.nitroplayer.NotificationButtonEvent
import com.margelo.nitro.nitroplayer.R
import com.margelo.nitro.nitroplayer.TrackItem
import com.margelo.nitro.nitroplayer.core.TrackPlayerCore
import com.margelo.nitro.nitroplayer.core.canSkipToNextOnQueue
import com.margelo.nitro.nitroplayer.core.canSkipToPreviousOnQueue
import com.margelo.nitro.nitroplayer.core.findTrackById
import com.margelo.nitro.nitroplayer.core.notifyNotificationButtonPress
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
    companion object {
        private const val DEFAULT_REMOTE_SKIP_INTERVAL_MS = 15_000L
        private const val NOTIFICATION_BUTTON_ACTION_PREFIX = "com.margelo.nitro.nitroplayer.button:"

        /** Extra on a notification button's command naming the track it was drawn for. */
        const val EXTRA_BUTTON_TRACK_ID = "com.margelo.nitro.nitroplayer.TRACK_ID"

        private fun notificationButtonAction(buttonId: String) = NOTIFICATION_BUTTON_ACTION_PREFIX + buttonId
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
    private var showRemoteSkipButtons: Boolean = true

    /** Which of previous / next / ±N skip can do something for the current item. */
    private data class StandardButtons(
        val previous: Boolean,
        val next: Boolean,
        val skip: Boolean,
    )

    private var standardButtons: StandardButtons? = null

    /** App-defined button; [icon] is a CommandButton.ICON_* constant. */
    data class SessionButton(
        val action: String,
        val title: String,
        val icon: Int,
    )

    private var sessionButtons: List<SessionButton> = emptyList()

    @Volatile var onSessionButtonPress: ((action: String) -> Unit)? = null

    private var notificationButtons: List<NotificationButton> = emptyList()
    private val notificationButtonStates = NotificationButtonStates()

    fun sessionCommands(): SessionCommands =
        MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS
            .buildUpon()
            .apply {
                notificationButtons.forEach { add(SessionCommand(notificationButtonAction(it.id), Bundle.EMPTY)) }
                sessionButtons.forEach { add(SessionCommand(it.action, Bundle.EMPTY)) }
            }.build()

    fun handlesSessionButton(action: String): Boolean = sessionButtons.any { it.action == action }

    fun setSessionButtons(buttons: List<SessionButton>) {
        sessionButtons = buttons
        refreshAvailableCommands()
        updateMediaButtonPreferences()
    }

    fun setNotificationButtons(buttons: List<NotificationButton>) {
        notificationButtons = buttons
        refreshAvailableCommands()
        updateMediaButtonPreferences()
    }

    fun setNotificationButtonState(
        buttonId: String,
        trackIds: List<String>?,
        isActive: Boolean,
    ) {
        notificationButtonStates.set(buttonId, trackIds, isActive)
        if (notificationButtons.any { it.id == buttonId && it.activeIcon != null }) updateMediaButtonPreferences()
    }

    /** Handles a press on a [NotificationButton]; false when [action] is not one. */
    fun onNotificationButtonCommand(
        action: String,
        pressedTrackId: String?,
    ): Boolean {
        if (!action.startsWith(NOTIFICATION_BUTTON_ACTION_PREFIX)) return false
        val buttonId = action.removePrefix(NOTIFICATION_BUTTON_ACTION_PREFIX)
        val button = notificationButtons.firstOrNull { it.id == buttonId } ?: return true
        val core = trackPlayerCore ?: return true
        // The track the button was drawn for, so a press just after a skip is not misattributed
        val track =
            currentTrack?.takeIf { pressedTrackId == null || it.id == pressedTrackId }
                ?: pressedTrackId?.let { core.findTrackById(it) }
                ?: currentTrack
                ?: return true
        val isActive = button.activeIcon?.let { notificationButtonStates.toggle(buttonId, track.id) }
        if (isActive != null) updateMediaButtonPreferences()
        core.notifyNotificationButtonPress(buttonId, track, NotificationButtonEvent(isActive, null, null))
        return true
    }

    // A controller only shows or presses a button whose command it was granted; the notification one feeds Android Auto
    private fun refreshAvailableCommands() {
        val session = mediaSession ?: return
        val commands = sessionCommands()
        (session.connectedControllers + listOfNotNull(session.mediaNotificationControllerInfo)).distinct().forEach {
            session.setAvailableCommands(it, commands, MediaSession.ConnectionResult.DEFAULT_PLAYER_COMMANDS)
        }
    }

    init {
        updateMediaButtonPreferences()
    }

    fun configure(
        androidAutoEnabled: Boolean?,
        carPlayEnabled: Boolean?,
        showInNotification: Boolean?,
        remoteSkipForwardIntervalMs: Long,
        remoteSkipBackwardIntervalMs: Long,
        showRemoteSkipButtons: Boolean?,
    ) {
        androidAutoEnabled?.let { this.androidAutoEnabled = it }
        carPlayEnabled?.let { this.carPlayEnabled = it }
        showInNotification?.let { this.showInNotification = it }
        showRemoteSkipButtons?.let { this.showRemoteSkipButtons = it }
        this.remoteSkipForwardIntervalMs = remoteSkipForwardIntervalMs
        this.remoteSkipBackwardIntervalMs = remoteSkipBackwardIntervalMs
        updateMediaButtonPreferences()
    }

    fun onTrackChanged(track: TrackItem?) {
        currentTrack = track
        // Redraw for the new track's toggle state and so presses name the track now showing
        if (notificationButtons.isNotEmpty()) updateMediaButtonPreferences()
    }

    fun onPlaybackStateChanged(playing: Boolean) {
        isPlaying = playing
    }

    /** Redraws the buttons when the current item or queue changes what previous / next / ±N skip can do. */
    fun refreshStandardButtons() {
        if (currentStandardButtons() != standardButtons) updateMediaButtonPreferences()
    }

    // Media3 checks preference buttons only against the commands granted to a controller, not
    // against what the current item supports, so System UI, Android Auto and WearOS would show
    // ±N skip on a live stream and previous/next with nothing to move to unless they're left out.
    private fun currentStandardButtons(): StandardButtons {
        val player = mediaSession?.player ?: return StandardButtons(previous = false, next = false, skip = false)
        val core = trackPlayerCore
        val seekable =
            player.isCommandAvailable(Player.COMMAND_SEEK_BACK) &&
                !player.isCurrentMediaItemLive &&
                player.duration != C.TIME_UNSET
        return StandardButtons(
            previous = core?.canSkipToPreviousOnQueue() ?: player.isCommandAvailable(Player.COMMAND_SEEK_TO_PREVIOUS),
            next = core?.canSkipToNextOnQueue() ?: player.isCommandAvailable(Player.COMMAND_SEEK_TO_NEXT),
            skip = showRemoteSkipButtons && seekable,
        )
    }

    fun release() {
        // Service owns the session — just null out our reference
        mediaSession = null
    }

    private fun updateMediaButtonPreferences() {
        val session = mediaSession ?: return
        val standard = currentStandardButtons()
        standardButtons = standard
        // Preferences replace Media3's default layout — prev/next must be declared or they vanish,
        // and are left out only when they'd do nothing (see currentStandardButtons).
        // Compact only shows BACK / play-pause / FORWARD, so the ±N skips go to OVERFLOW; left in
        // the forward slot they push Next out of the compact notification entirely.
        val preserved = session.mediaButtonPreferences.filterNot { it.isManagedButton() || it.sessionCommand != null }
        val trackId = currentTrack?.id
        val trackExtras = Bundle().apply { trackId?.let { putString(EXTRA_BUTTON_TRACK_ID, it) } }
        val configured =
            notificationButtons.map {
                val icon = it.activeIcon?.takeIf { _ -> notificationButtonStates.isActive(it.id, trackId) } ?: it.icon
                CommandButton
                    .Builder(icon.icon)
                    .apply { if (icon.customIconResId != 0) setCustomIconResId(icon.customIconResId) }
                    .setDisplayName(it.title)
                    .setSessionCommand(SessionCommand(notificationButtonAction(it.id), trackExtras))
                    .setSlots(CommandButton.SLOT_OVERFLOW)
                    .build()
            }
        val custom =
            sessionButtons.map {
                CommandButton
                    .Builder(it.icon)
                    .setDisplayName(it.title)
                    .setSessionCommand(SessionCommand(it.action, Bundle.EMPTY))
                    .setSlots(CommandButton.SLOT_OVERFLOW)
                    .build()
            }
        val navigation = listOfNotNull(previousTrackButton().takeIf { standard.previous }, nextTrackButton().takeIf { standard.next })
        val skips = if (standard.skip) listOf(skipBackButton(), skipForwardButton()) else emptyList()
        session.setMediaButtonPreferences(navigation + configured + custom + skips + preserved)
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
