@file:Suppress("ktlint:standard:max-line-length")

package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Metadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.icy.IcyInfo
import com.margelo.nitro.nitroplayer.Reason
import com.margelo.nitro.nitroplayer.RepeatMode
import com.margelo.nitro.nitroplayer.TimedMetadata
import com.margelo.nitro.nitroplayer.equalizer.EqualizerCore
import com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService

/**
 * ExoPlayer event listener — translates low-level ExoPlayer callbacks into
 * TrackPlayerCore state mutations and JS-facing listener notifications.
 * All callbacks fire on the main looper (ExoPlayer uses the default application looper).
 */
internal class TrackPlayerEventListener(
    private val core: TrackPlayerCore,
) : Player.Listener {
    override fun onMediaItemTransition(
        mediaItem: MediaItem?,
        reason: Int,
    ) {
        with(core) {
            // TRACK repeat: REPEAT_MODE_ONE fires this every loop — not a real track change
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_REPEAT) return

            // Remove the track that just finished/was skipped from temp lists
            if ((
                    reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO ||
                        reason == Player.MEDIA_ITEM_TRANSITION_REASON_SEEK
                ) &&
                previousMediaItem != null
            ) {
                previousMediaItem?.mediaId?.let { mediaId ->
                    val trackId = extractTrackId(mediaId)
                    val pnIdx = playNextStack.indexOfFirst { it.id == trackId }
                    if (pnIdx >= 0) {
                        playNextStack.removeAt(pnIdx)
                    } else {
                        val unIdx = upNextQueue.indexOfFirst { it.id == trackId }
                        if (unIdx >= 0) upNextQueue.removeAt(unIdx)
                    }
                }
            }

            // Track new current item as "previous" for the next transition
            previousMediaItem = mediaItem

            // Re-determine temporary type for the new current item
            currentTemporaryType = determineCurrentTemporaryType()

            // Update currentTrackIndex when landing on an original playlist track
            if (currentTemporaryType == TrackPlayerCore.TemporaryType.NONE && mediaItem != null) {
                val trackId = extractTrackId(mediaItem.mediaId)
                val newIdx = currentTracks.indexOfFirst { it.id == trackId }
                if (newIdx >= 0 && newIdx != currentTrackIndex) currentTrackIndex = newIdx
            }

            // Top up the windowed timeline — the item we just left freed a slot.
            // Only when it is actually short: rebuildQueueFromCurrentPosition can fall
            // into the substitute-jump path (setMediaItems), which re-enters this very
            // callback. The length check makes any such re-entry a no-op and terminate.
            if (mediaItem != null &&
                exo.mediaItemCount - exo.currentMediaItemIndex - 1 < QUEUE_WINDOW_SIZE
            ) {
                rebuildQueueFromCurrentPosition()
            }

            val track = getCurrentTrack() ?: return
            val r =
                when (reason) {
                    Player.MEDIA_ITEM_TRANSITION_REASON_AUTO -> Reason.END
                    Player.MEDIA_ITEM_TRANSITION_REASON_SEEK -> Reason.USER_ACTION
                    Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED -> Reason.USER_ACTION
                    else -> null
                }
            notifyTrackChange(track, r)
            mediaSessionManager?.onTrackChanged(track)
            checkUpcomingTracksForUrls(lookaheadCount)
            notifyTemporaryQueueChange()
        }
    }

    /** In-stream metadata (ICY StreamTitle, ID3 frames) arriving mid-playback. */
    @UnstableApi
    override fun onMetadata(metadata: Metadata) {
        val builder = MediaMetadata.Builder()
        var url: String? = null
        for (i in 0 until metadata.length()) {
            val entry = metadata.get(i)
            entry.populateMediaMetadata(builder)
            // populateMediaMetadata drops IcyInfo.url — radio providers put the
            // current track's artwork URL there, so read it off the entry directly.
            if (entry is IcyInfo && !entry.url.isNullOrEmpty()) url = entry.url
        }
        val merged = builder.build()
        var artist = merged.artist?.toString()
        var title = merged.title?.toString()
        // ICY streams pack both fields into one "Artist - Title" string
        val separator = if (artist == null) title?.indexOf(" - ") ?: -1 else -1
        if (separator > 0 && title != null && separator + 3 < title.length) {
            artist = title.substring(0, separator)
            title = title.substring(separator + 3)
        }
        val album = merged.albumTitle?.toString()
        val artworkUrl = merged.artworkUri?.toString()
        if (title == null && artist == null && album == null && url == null && artworkUrl == null) return
        core.notifyTimedMetadata(TimedMetadata(title, artist, album, url, artworkUrl))
    }

    override fun onTimelineChanged(
        timeline: androidx.media3.common.Timeline,
        reason: Int,
    ) {
        if (reason == Player.TIMELINE_CHANGE_REASON_PLAYLIST_CHANGED) {
            NitroPlayerMediaBrowserService.getInstance()?.onPlaylistsUpdated()
        }
    }

    override fun onPlayWhenReadyChanged(
        playWhenReady: Boolean,
        reason: Int,
    ) {
        val r = if (reason == Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST) Reason.USER_ACTION else null
        core.emitStateChange(r)
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        with(core) {
            if (playbackState == Player.STATE_ENDED && currentRepeatMode == RepeatMode.PLAYLIST) {
                playNextStack.clear()
                upNextQueue.clear()
                currentTemporaryType = TrackPlayerCore.TemporaryType.NONE
                rebuildQueueAndPlayFromIndex(0)
                val firstTrack = currentTracks.getOrNull(0)
                if (firstTrack != null) notifyTrackChange(firstTrack, Reason.REPEAT)
                return
            }
            emitStateChange()
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        core.emitStateChange()
    }

    override fun onPositionDiscontinuity(
        oldPosition: Player.PositionInfo,
        newPosition: Player.PositionInfo,
        reason: Int,
    ) {
        if (reason == Player.DISCONTINUITY_REASON_SEEK) {
            core.isManuallySeeked = true
            val pos = core.exo.currentPosition / 1000.0
            val dur = if (core.exo.duration > 0) core.exo.duration / 1000.0 else 0.0
            core.notifySeek(pos, dur)
        }
    }

    override fun onAudioSessionIdChanged(audioSessionId: Int) {
        if (audioSessionId != 0) {
            try {
                EqualizerCore.getInstance(core.context).initialize(audioSessionId)
            } catch (_: Exception) {
                // Non-critical — device may not support equalizer
            }
        }
    }
}
