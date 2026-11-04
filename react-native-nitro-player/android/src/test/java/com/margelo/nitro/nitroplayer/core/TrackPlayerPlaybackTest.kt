package com.margelo.nitro.nitroplayer.core

import androidx.media3.common.Player
import com.margelo.nitro.nitroplayer.media.AudioFocusController
import org.junit.Test
import org.mockito.Mockito.*

class TrackPlayerPlaybackTest {
    private val core = mock(TrackPlayerCore::class.java)
    private val exo = mock(ExoPlayerCore::class.java)
    private val focus = mock(AudioFocusController::class.java)

    private fun givenPlayer(state: Int, count: Int, hasFocusController: Boolean = true) {
        `when`(core.exo).thenReturn(exo)
        `when`(core.audioFocusController).thenReturn(if (hasFocusController) focus else null)
        `when`(exo.playbackState).thenReturn(state)
        `when`(exo.mediaItemCount).thenReturn(count)
    }

    @Test
    fun `notification dismissal prepares the retained queue before playing`() {
        givenPlayer(Player.STATE_IDLE, 2)

        core.playOnQueue()

        inOrder(focus, exo).apply {
            verify(focus).acquire()
            verify(exo).prepare()
            verify(exo).play()
        }
    }

    @Test
    fun `an empty idle player is not prepared`() {
        givenPlayer(Player.STATE_IDLE, 0)

        core.playOnQueue()

        verify(exo, never()).prepare()
        verify(exo).play()
    }

    @Test
    fun `ready playback is not reset`() {
        givenPlayer(Player.STATE_READY, 2)

        core.playOnQueue()

        verify(exo, never()).prepare()
        verify(exo).play()
    }

    @Test
    fun `buffering playback is not prepared again`() {
        givenPlayer(Player.STATE_BUFFERING, 2)

        core.playOnQueue()

        verify(exo, never()).prepare()
        verify(exo).play()
    }

    @Test
    fun `idle playback recovers without an audio focus controller`() {
        givenPlayer(Player.STATE_IDLE, 1, hasFocusController = false)

        core.playOnQueue()

        inOrder(exo).apply {
            verify(exo).prepare()
            verify(exo).play()
        }
        verifyNoInteractions(focus)
    }
}
