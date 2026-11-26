/**
 * Options for the react-native-nitro-player Expo config plugin.
 *
 * ```js
 * plugins: [['react-native-nitro-player', { android: { castEnabled: false } }]]
 * ```
 *
 * @typedef {object} NitroPlayerPluginOptions
 * @property {AndroidOptions} [android] Android project changes.
 * @property {IosOptions} [ios] iOS project changes.
 */

/**
 * @typedef {object} AndroidOptions
 * @property {boolean} [castEnabled] Writes `nitroPlayerCastEnabled` to
 *   `gradle.properties`. `false` builds without the Google Cast SDK. Left out,
 *   the property isn't written and Cast stays on.
 * @property {boolean} [androidAutoEnabled] Lists the app in Android Auto: adds
 *   the media browser service, the car application meta-data and
 *   `res/xml/automotive_app_desc.xml`. Defaults to `false`.
 * @property {boolean} [playbackResumptionEnabled] Adds only the media browser
 *   service, so the phone's media controls can resume playback, without listing
 *   the app in Android Auto. Defaults to `false`.
 * @property {boolean} [voiceSearchEnabled] Adds the `MEDIA_PLAY_FROM_SEARCH`
 *   intent filter to the launcher activity, so Assistant can play from the app
 *   by name. Defaults to `false`.
 */

/**
 * @typedef {object} IosOptions
 * @property {boolean} [castEnabled] Adds the Google Cast keys to `Info.plist`
 *   (`NSLocalNetworkUsageDescription` and `NSBonjourServices`). Defaults to
 *   `true`.
 * @property {string} [castReceiverApplicationId] Receiver app ID added to
 *   `NSBonjourServices`. Defaults to the Default Media Receiver, `CC1AD845`.
 * @property {string} [localNetworkUsageDescription] Text of the local network
 *   permission prompt. Defaults to an existing value, then to a generic text.
 * @property {boolean} [carPlayEnabled] Adds the CarPlay audio entitlement and
 *   the CarPlay scene to `Info.plist`. Needs a scene-based app (Expo SDK 58 or
 *   later). Defaults to `false`.
 */

const PACKAGE = 'react-native-nitro-player'
const DEFAULT_CAST_RECEIVER_APPLICATION_ID = 'CC1AD845'

const TOP_LEVEL_KEYS = { android: 'object', ios: 'object' }
const ANDROID_KEYS = {
  castEnabled: 'boolean',
  androidAutoEnabled: 'boolean',
  playbackResumptionEnabled: 'boolean',
  voiceSearchEnabled: 'boolean',
}
const IOS_KEYS = {
  castEnabled: 'boolean',
  castReceiverApplicationId: 'string',
  localNetworkUsageDescription: 'string',
  carPlayEnabled: 'boolean',
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function checkKeys(object, allowed, path) {
  for (const [key, value] of Object.entries(object)) {
    const type = allowed[key]
    if (type === undefined) {
      throw new Error(
        `${PACKAGE}: unknown plugin option "${path}${key}". Valid options: ${Object.keys(
          allowed
        )
          .map((name) => path + name)
          .join(', ')}.`
      )
    }
    if (value === undefined) continue
    const valid =
      type === 'object' ? isPlainObject(value) : typeof value === type
    if (!valid) {
      const expected = type === 'object' ? 'an object' : `a ${type}`
      throw new Error(
        `${PACKAGE}: plugin option "${path}${key}" must be ${expected}, got ${JSON.stringify(value)}.`
      )
    }
  }
}

/**
 * Validates the plugin options and fills in the defaults.
 *
 * @param {NitroPlayerPluginOptions | undefined} options
 */
function resolveOptions(options) {
  if (options === undefined || options === null) options = {}
  if (!isPlainObject(options)) {
    throw new Error(
      `${PACKAGE}: plugin options must be an object, got ${JSON.stringify(options)}.`
    )
  }
  checkKeys(options, TOP_LEVEL_KEYS, '')
  const android = options.android ?? {}
  const ios = options.ios ?? {}
  checkKeys(android, ANDROID_KEYS, 'android.')
  checkKeys(ios, IOS_KEYS, 'ios.')

  const iosCastEnabled = ios.castEnabled !== false
  if (!iosCastEnabled) {
    for (const key of [
      'castReceiverApplicationId',
      'localNetworkUsageDescription',
    ]) {
      if (ios[key] !== undefined) {
        throw new Error(
          `${PACKAGE}: plugin option "ios.${key}" has no effect while "ios.castEnabled" is false.`
        )
      }
    }
  }
  const receiverApplicationId =
    ios.castReceiverApplicationId ?? DEFAULT_CAST_RECEIVER_APPLICATION_ID
  if (!/^[A-Za-z0-9]+$/.test(receiverApplicationId)) {
    throw new Error(
      `${PACKAGE}: plugin option "ios.castReceiverApplicationId" must be a Cast receiver app ID such as "${DEFAULT_CAST_RECEIVER_APPLICATION_ID}", got ${JSON.stringify(receiverApplicationId)}.`
    )
  }
  if (ios.localNetworkUsageDescription === '') {
    throw new Error(
      `${PACKAGE}: plugin option "ios.localNetworkUsageDescription" can't be empty: iOS shows it in the local network permission prompt.`
    )
  }

  return {
    android: {
      castEnabled: android.castEnabled,
      androidAutoEnabled: android.androidAutoEnabled === true,
      playbackResumptionEnabled: android.playbackResumptionEnabled === true,
      voiceSearchEnabled: android.voiceSearchEnabled === true,
    },
    ios: {
      castEnabled: iosCastEnabled,
      castReceiverApplicationId: receiverApplicationId,
      localNetworkUsageDescription: ios.localNetworkUsageDescription,
      carPlayEnabled: ios.carPlayEnabled === true,
    },
  }
}

module.exports = { resolveOptions, DEFAULT_CAST_RECEIVER_APPLICATION_ID }
