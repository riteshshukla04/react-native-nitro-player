@file:OptIn(UnstableApi::class)

package com.margelo.nitro.nitroplayer.media

import android.content.Context
import androidx.annotation.DrawableRes
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import com.margelo.nitro.nitroplayer.AndroidNotificationButton

/** A button from `PlayerConfig.notificationButtons` with its icons resolved; [activeIcon] makes it a toggle. */
data class NotificationButton(
    val id: String,
    val title: String,
    val icon: ButtonIcon,
    val activeIcon: ButtonIcon?,
)

/** A CommandButton.ICON_* constant, or ICON_UNDEFINED plus a drawable from the app. */
data class ButtonIcon(
    val icon: Int,
    @DrawableRes val customIconResId: Int = 0,
)

/** Rejects unknown icons and repeated ids, so a bad config fails `configure` instead of showing nothing. */
internal fun resolveNotificationButtons(
    context: Context,
    buttons: List<AndroidNotificationButton>,
): List<NotificationButton> {
    buttons.groupBy { it.id }.filterValues { it.size > 1 }.keys.firstOrNull()?.let {
        throw IllegalArgumentException("notificationButtons.android: id '$it' is used more than once")
    }
    return buttons.map {
        NotificationButton(
            it.id,
            it.title,
            resolveButtonIcon(context, it.id, it.icon),
            it.activeIcon?.let { name -> resolveButtonIcon(context, it.id, name) },
        )
    }
}

private fun resolveButtonIcon(
    context: Context,
    buttonId: String,
    name: String,
): ButtonIcon {
    BUILT_IN_ICONS[name]?.let { return ButtonIcon(it) }
    val resId = context.resources.getIdentifier(name, "drawable", context.packageName)
    if (resId == 0) {
        throw IllegalArgumentException(
            "notificationButtons.android: icon '$name' of '$buttonId' is neither a built-in icon nor a drawable in res/drawable",
        )
    }
    return ButtonIcon(CommandButton.ICON_UNDEFINED, resId)
}

/** On/off state of toggle buttons: per track, or for every track when set without track ids. */
internal class NotificationButtonStates {
    private class Entry {
        var allTracks: Boolean? = null
        val perTrack = HashMap<String, Boolean>()
    }

    private val entries = HashMap<String, Entry>()

    fun isActive(
        buttonId: String,
        trackId: String?,
    ): Boolean {
        val entry = entries[buttonId] ?: return false
        return trackId?.let { entry.perTrack[it] } ?: entry.allTracks ?: false
    }

    fun set(
        buttonId: String,
        trackIds: List<String>?,
        isActive: Boolean,
    ) {
        val entry = entries.getOrPut(buttonId) { Entry() }
        if (trackIds == null) {
            entry.allTracks = isActive
            entry.perTrack.clear()
        } else {
            trackIds.forEach { entry.perTrack[it] = isActive }
        }
    }

    /** Flips the state shown for [trackId]; for every track when it was last set without track ids. */
    fun toggle(
        buttonId: String,
        trackId: String,
    ): Boolean {
        val next = !isActive(buttonId, trackId)
        val entry = entries[buttonId]
        val forAllTracks = entry?.allTracks != null && entry.perTrack.isEmpty()
        set(buttonId, if (forAllTracks) null else listOf(trackId), next)
        return next
    }
}

private val BUILT_IN_ICONS =
    mapOf(
        "album" to CommandButton.ICON_ALBUM,
        "artist" to CommandButton.ICON_ARTIST,
        "block" to CommandButton.ICON_BLOCK,
        "bookmark_filled" to CommandButton.ICON_BOOKMARK_FILLED,
        "bookmark" to CommandButton.ICON_BOOKMARK_UNFILLED,
        "check_circle_filled" to CommandButton.ICON_CHECK_CIRCLE_FILLED,
        "check_circle" to CommandButton.ICON_CHECK_CIRCLE_UNFILLED,
        "closed_captions" to CommandButton.ICON_CLOSED_CAPTIONS,
        "closed_captions_off" to CommandButton.ICON_CLOSED_CAPTIONS_OFF,
        "fast_forward" to CommandButton.ICON_FAST_FORWARD,
        "feed" to CommandButton.ICON_FEED,
        "flag_filled" to CommandButton.ICON_FLAG_FILLED,
        "flag" to CommandButton.ICON_FLAG_UNFILLED,
        "heart_filled" to CommandButton.ICON_HEART_FILLED,
        "heart" to CommandButton.ICON_HEART_UNFILLED,
        "minus" to CommandButton.ICON_MINUS,
        "minus_circle_filled" to CommandButton.ICON_MINUS_CIRCLE_FILLED,
        "minus_circle" to CommandButton.ICON_MINUS_CIRCLE_UNFILLED,
        "next" to CommandButton.ICON_NEXT,
        "pause" to CommandButton.ICON_PAUSE,
        "play" to CommandButton.ICON_PLAY,
        "playback_speed" to CommandButton.ICON_PLAYBACK_SPEED,
        "playback_speed_0_5" to CommandButton.ICON_PLAYBACK_SPEED_0_5,
        "playback_speed_0_8" to CommandButton.ICON_PLAYBACK_SPEED_0_8,
        "playback_speed_1_0" to CommandButton.ICON_PLAYBACK_SPEED_1_0,
        "playback_speed_1_2" to CommandButton.ICON_PLAYBACK_SPEED_1_2,
        "playback_speed_1_5" to CommandButton.ICON_PLAYBACK_SPEED_1_5,
        "playback_speed_1_8" to CommandButton.ICON_PLAYBACK_SPEED_1_8,
        "playback_speed_2_0" to CommandButton.ICON_PLAYBACK_SPEED_2_0,
        "playlist_add" to CommandButton.ICON_PLAYLIST_ADD,
        "playlist_remove" to CommandButton.ICON_PLAYLIST_REMOVE,
        "plus" to CommandButton.ICON_PLUS,
        "plus_circle_filled" to CommandButton.ICON_PLUS_CIRCLE_FILLED,
        "plus_circle" to CommandButton.ICON_PLUS_CIRCLE_UNFILLED,
        "previous" to CommandButton.ICON_PREVIOUS,
        "quality" to CommandButton.ICON_QUALITY,
        "queue_add" to CommandButton.ICON_QUEUE_ADD,
        "queue_next" to CommandButton.ICON_QUEUE_NEXT,
        "queue_remove" to CommandButton.ICON_QUEUE_REMOVE,
        "radio" to CommandButton.ICON_RADIO,
        "repeat_all" to CommandButton.ICON_REPEAT_ALL,
        "repeat_off" to CommandButton.ICON_REPEAT_OFF,
        "repeat_one" to CommandButton.ICON_REPEAT_ONE,
        "rewind" to CommandButton.ICON_REWIND,
        "settings" to CommandButton.ICON_SETTINGS,
        "share" to CommandButton.ICON_SHARE,
        "shuffle_off" to CommandButton.ICON_SHUFFLE_OFF,
        "shuffle_on" to CommandButton.ICON_SHUFFLE_ON,
        "shuffle_star" to CommandButton.ICON_SHUFFLE_STAR,
        "signal" to CommandButton.ICON_SIGNAL,
        "skip_back" to CommandButton.ICON_SKIP_BACK,
        "skip_back_10" to CommandButton.ICON_SKIP_BACK_10,
        "skip_back_15" to CommandButton.ICON_SKIP_BACK_15,
        "skip_back_30" to CommandButton.ICON_SKIP_BACK_30,
        "skip_back_5" to CommandButton.ICON_SKIP_BACK_5,
        "skip_forward" to CommandButton.ICON_SKIP_FORWARD,
        "skip_forward_10" to CommandButton.ICON_SKIP_FORWARD_10,
        "skip_forward_15" to CommandButton.ICON_SKIP_FORWARD_15,
        "skip_forward_30" to CommandButton.ICON_SKIP_FORWARD_30,
        "skip_forward_5" to CommandButton.ICON_SKIP_FORWARD_5,
        "star_filled" to CommandButton.ICON_STAR_FILLED,
        "star" to CommandButton.ICON_STAR_UNFILLED,
        "stop" to CommandButton.ICON_STOP,
        "subtitles" to CommandButton.ICON_SUBTITLES,
        "subtitles_off" to CommandButton.ICON_SUBTITLES_OFF,
        "sync" to CommandButton.ICON_SYNC,
        "thumb_down_filled" to CommandButton.ICON_THUMB_DOWN_FILLED,
        "thumb_down" to CommandButton.ICON_THUMB_DOWN_UNFILLED,
        "thumb_up_filled" to CommandButton.ICON_THUMB_UP_FILLED,
        "thumb_up" to CommandButton.ICON_THUMB_UP_UNFILLED,
        "volume_down" to CommandButton.ICON_VOLUME_DOWN,
        "volume_off" to CommandButton.ICON_VOLUME_OFF,
        "volume_up" to CommandButton.ICON_VOLUME_UP,
    )
