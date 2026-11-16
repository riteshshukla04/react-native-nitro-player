import type { RepeatMode } from '../specs/TrackPlayer.nitro'

/**
 * Icons built into Android's media controls, for {@link AndroidNotificationButton.icon}.
 * Names without `_filled` are the outlined versions.
 */
export type AndroidButtonIcon =
  | 'album'
  | 'artist'
  | 'block'
  | 'bookmark'
  | 'bookmark_filled'
  | 'check_circle'
  | 'check_circle_filled'
  | 'closed_captions'
  | 'closed_captions_off'
  | 'fast_forward'
  | 'feed'
  | 'flag'
  | 'flag_filled'
  | 'heart'
  | 'heart_filled'
  | 'minus'
  | 'minus_circle'
  | 'minus_circle_filled'
  | 'next'
  | 'pause'
  | 'play'
  | 'playback_speed'
  | 'playback_speed_0_5'
  | 'playback_speed_0_8'
  | 'playback_speed_1_0'
  | 'playback_speed_1_2'
  | 'playback_speed_1_5'
  | 'playback_speed_1_8'
  | 'playback_speed_2_0'
  | 'playlist_add'
  | 'playlist_remove'
  | 'plus'
  | 'plus_circle'
  | 'plus_circle_filled'
  | 'previous'
  | 'quality'
  | 'queue_add'
  | 'queue_next'
  | 'queue_remove'
  | 'radio'
  | 'repeat_all'
  | 'repeat_off'
  | 'repeat_one'
  | 'rewind'
  | 'settings'
  | 'share'
  | 'shuffle_off'
  | 'shuffle_on'
  | 'shuffle_star'
  | 'signal'
  | 'skip_back'
  | 'skip_back_5'
  | 'skip_back_10'
  | 'skip_back_15'
  | 'skip_back_30'
  | 'skip_forward'
  | 'skip_forward_5'
  | 'skip_forward_10'
  | 'skip_forward_15'
  | 'skip_forward_30'
  | 'star'
  | 'star_filled'
  | 'stop'
  | 'subtitles'
  | 'subtitles_off'
  | 'sync'
  | 'thumb_down'
  | 'thumb_down_filled'
  | 'thumb_up'
  | 'thumb_up_filled'
  | 'volume_down'
  | 'volume_off'
  | 'volume_up'

/**
 * A button in the Android media notification, lock screen and Android Auto.
 * Android 13+ shows the first two buttons of the list next to previous / play / next;
 * Android Auto shows more, with the rest in an overflow menu.
 */
export interface AndroidNotificationButton {
  /** Passed to `TrackPlayer.onNotificationButtonPress` */
  id: string
  /** Accessibility label; Android Auto may show it in its overflow menu */
  title: string
  /**
   * An {@link AndroidButtonIcon}, or the name of a drawable in your app's `res/drawable`.
   * Use a single-colour vector: the system tints it.
   */
  icon: string
  /** Shown while the button is active for the current track; makes the button a toggle */
  activeIcon?: string
}

/**
 * A control iOS draws itself on the Lock Screen, Control Center and CarPlay.
 * - `like` / `dislike` / `bookmark`: toggles, reported as {@link NotificationButtonEvent.isActive}
 * - `rating`: 0–5 stars, reported as {@link NotificationButtonEvent.rating}. Older API: newer iOS versions may not show it
 * - `repeat`: the player switches repeat mode itself, reported as {@link NotificationButtonEvent.repeatMode}
 * - `shuffle`: a toggle, reported as {@link NotificationButtonEvent.isActive}
 *
 * iOS 27 only draws `like`, as a star on the Lock Screen and in Control Center; the others are
 * handled but not shown there.
 */
export type LockScreenCommand =
  | 'like'
  | 'dislike'
  | 'bookmark'
  | 'rating'
  | 'repeat'
  | 'shuffle'

/** Turns on one of the controls iOS draws on the Lock Screen and Control Center */
export interface LockScreenButton {
  /** Passed to `TrackPlayer.onNotificationButtonPress` */
  id: string
  /** Text iOS may show for the control, e.g. to VoiceOver */
  title?: string
  command: LockScreenCommand
}

/**
 * Kind of button on CarPlay's Now Playing screen:
 * - `image`: draws `icon` (default)
 * - `shuffle` / `addToLibrary`: system toggles, reported as {@link NotificationButtonEvent.isActive}
 * - `repeat`: cycles the player's repeat mode itself, reported as {@link NotificationButtonEvent.repeatMode}
 * - `playbackRate`: cycles the player's speed through 1, 1.25, 1.5, 1.75, 2 and 0.5 itself
 * - `more`: the system "more" button
 */
export type CarPlayButtonType =
  | 'image'
  | 'shuffle'
  | 'repeat'
  | 'playbackRate'
  | 'addToLibrary'
  | 'more'

/** A button on CarPlay's Now Playing screen */
export interface CarPlayButton {
  /** Passed to `TrackPlayer.onNotificationButtonPress` */
  id: string
  type?: CarPlayButtonType
  /** Required for `image`: an SF Symbol name, or the name of an image in your app's asset catalog */
  icon?: string
  /** `image` only: shown while the button is active for the current track; makes the button a toggle */
  activeIcon?: string
}

/** Buttons for the iOS system media controls */
export interface IOSNotificationButtons {
  /** Each command may appear at most once */
  lockScreen?: LockScreenButton[]
  /** CarPlay shows the first five */
  carPlay?: CarPlayButton[]
}

/**
 * Extra buttons in the system media controls, set with `PlayerConfig.notificationButtons`.
 * Give a button the same `id` on every surface to handle it in one place and share its state.
 */
export interface NotificationButtons {
  /** In priority order */
  android?: AndroidNotificationButton[]
  ios?: IOSNotificationButtons
}

/** Sets whether a toggle button shows as active, for `TrackPlayer.setNotificationButtonState` */
export interface NotificationButtonState {
  buttonId: string
  /**
   * Tracks the state applies to. Leave it out to apply it to every track (e.g. shuffle);
   * taps then flip it for every track too.
   */
  trackIds?: string[]
  isActive: boolean
}

/** What a press changed, passed to `TrackPlayer.onNotificationButtonPress` */
export interface NotificationButtonEvent {
  /** Toggles: the new state. The icon has already changed; call `TrackPlayer.setNotificationButtonState` to undo it */
  isActive?: boolean
  /** `rating`: the rating picked, 0–5 */
  rating?: number
  /** `repeat`: the mode picked. The player has already switched to it */
  repeatMode?: RepeatMode
}
