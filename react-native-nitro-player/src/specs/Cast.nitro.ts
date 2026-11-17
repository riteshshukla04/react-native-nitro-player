import type { HybridObject } from 'react-native-nitro-modules'
import type { TrackItem } from '../types/PlayerQueue'

/**
 * The current Google Cast connection state.
 *
 * - `no_devices_available`: No Cast devices are discoverable on the network.
 *   The Cast button is typically hidden in this state.
 * - `not_connected`: Cast devices are available but none is connected.
 * - `connecting`: A session is being established with a device.
 * - `connected`: A session is active and playback is routed to the device.
 */
export type CastState =
  | 'no_devices_available'
  | 'not_connected'
  | 'connecting'
  | 'connected'

/**
 * Google Cast control surface.
 *
 * Casting is implemented as an internal playback backend swap inside the native
 * player core: when a session is `connected`, every playback operation (play,
 * pause, seek, skip, queue) is routed to the remote Cast device and local audio
 * is suppressed automatically. The existing {@link TrackPlayer} API keeps
 * working unchanged — this object only exposes the Cast-specific surface.
 */
export interface Cast extends HybridObject<{
  android: 'kotlin'
  ios: 'swift'
}> {
  /**
   * Initialize the Cast framework. Must be called once early in app startup
   * (before the first Cast interaction). Safe to call multiple times.
   *
   * @param receiverApplicationId Optional Web Receiver application ID registered
   *   in the Google Cast Developer Console. When omitted, the platform Default
   *   Media Receiver (`CC1AD845`) is used, which supports audio playback,
   *   metadata and queues out of the box.
   */
  configure(receiverApplicationId?: string): Promise<void>

  /**
   * Whether playback is currently routed to a Cast device.
   * Equivalent to `getCastState() === 'connected'`.
   */
  isCasting(): boolean

  /** The current Cast connection state. */
  getCastState(): CastState

  /** The friendly name of the connected device, or `null` when not connected. */
  getCastDeviceName(): string | null

  /**
   * Present the native Cast dialog. Shows the device chooser when not connected,
   * or the cast controls / disconnect dialog when already connected. Mirrors the
   * behaviour of the standard platform Cast button.
   */
  showCastPicker(): void

  /** End the current Cast session and resume local playback. No-op when not connected. */
  endCastSession(): Promise<void>

  /**
   * Register a callback fired whenever the Cast connection state changes.
   * The callback receives the new {@link CastState} and the connected device
   * name (or `null`).
   *
   * Each call adds a listener and there is no way to remove one, so register
   * once (e.g. at app start), not in a component effect; inside components use
   * `useCastState` or `useIsCasting`. Calling it never affects those hooks or
   * `CastButton`.
   */
  onCastStateChange(
    callback: (state: CastState, deviceName: string | null) => void
  ): void

  /**
   * Register a callback fired while casting when the current or upcoming
   * tracks have no Cast URL yet. Answer it with {@link setCastUrls}.
   *
   * Use this when the receiver needs a different URL from the one the phone
   * plays, such as a format the receiver can decode or a stream for a
   * downloaded track. Once a callback is registered, the receiver only loads
   * tracks that have a Cast URL, and waits on the first one that doesn't.
   * Without one, the receiver loads each track's `url`.
   *
   * Each track id is asked for at most once every few seconds while unanswered.
   *
   * @param callback Called with the tracks that need a Cast URL, one per id
   */
  onTracksNeedCastUrls(callback: (tracks: TrackItem[]) => void): void

  /**
   * Supply the URLs the Cast receiver loads, keyed by track id. Merged into
   * the URLs already supplied; empty strings are ignored.
   *
   * Cast URLs are cleared whenever a Cast session starts or ends, so each
   * session asks for fresh ones through {@link onTracksNeedCastUrls}.
   *
   * @param urls Cast URL per track id
   */
  setCastUrls(urls: Record<string, string>): Promise<void>
}
