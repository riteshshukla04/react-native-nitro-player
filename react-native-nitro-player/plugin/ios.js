const PACKAGE = 'react-native-nitro-player'
const CAST_BONJOUR_SERVICE = '_googlecast._tcp'
const DEFAULT_LOCAL_NETWORK_USAGE_DESCRIPTION =
  '$(PRODUCT_NAME) uses the local network to discover Cast devices.'
const PHONE_SCENE_ROLE = 'UIWindowSceneSessionRoleApplication'
const CARPLAY_SCENE_ROLE = 'CPTemplateApplicationSceneSessionRoleApplication'
const CARPLAY_SCENE_DELEGATE = 'NitroPlayerCarPlaySceneDelegate'
const CARPLAY_AUDIO_ENTITLEMENT = 'com.apple.developer.carplay-audio'

function withValues(list, values) {
  const result = Array.isArray(list) ? [...list] : []
  for (const value of values) {
    if (!result.includes(value)) result.push(value)
  }
  return result
}

/**
 * Adds `audio` to `UIBackgroundModes`, so playback continues in the background.
 */
function addBackgroundAudio(infoPlist) {
  infoPlist.UIBackgroundModes = withValues(infoPlist.UIBackgroundModes, [
    'audio',
  ])
  return infoPlist
}

/**
 * Adds the keys Google Cast device discovery needs.
 *
 * @param {object} infoPlist
 * @param {{ castReceiverApplicationId: string, localNetworkUsageDescription?: string }} options
 */
function addCast(infoPlist, options) {
  infoPlist.NSBonjourServices = withValues(infoPlist.NSBonjourServices, [
    CAST_BONJOUR_SERVICE,
    `_${options.castReceiverApplicationId}.${CAST_BONJOUR_SERVICE}`,
  ])
  if (options.localNetworkUsageDescription !== undefined) {
    infoPlist.NSLocalNetworkUsageDescription =
      options.localNetworkUsageDescription
  } else if (!infoPlist.NSLocalNetworkUsageDescription) {
    infoPlist.NSLocalNetworkUsageDescription =
      DEFAULT_LOCAL_NETWORK_USAGE_DESCRIPTION
  }
  return infoPlist
}

/**
 * Declares the CarPlay scene next to the app's phone scene. Throws when the
 * app has no phone scene: declaring only a CarPlay scene would make iOS run a
 * window-based app through scenes and leave its phone screen blank.
 */
function addCarPlayScene(infoPlist) {
  const sceneManifest = infoPlist.UIApplicationSceneManifest
  const configurations = sceneManifest?.UISceneConfigurations
  const phoneScenes = configurations?.[PHONE_SCENE_ROLE]
  if (!Array.isArray(phoneScenes) || phoneScenes.length === 0) {
    throw new Error(
      `${PACKAGE}: "ios.carPlayEnabled" needs a scene-based iOS app, but Info.plist declares no ${PHONE_SCENE_ROLE} scene. Expo SDK 58 and later generate one.`
    )
  }
  sceneManifest.UIApplicationSupportsMultipleScenes = true
  const carPlayScenes = Array.isArray(configurations[CARPLAY_SCENE_ROLE])
    ? configurations[CARPLAY_SCENE_ROLE]
    : []
  if (
    !carPlayScenes.some(
      (scene) => scene.UISceneDelegateClassName === CARPLAY_SCENE_DELEGATE
    )
  ) {
    // iOS uses the role's first configuration unless the app delegate picks one
    carPlayScenes.unshift({
      UISceneClassName: 'CPTemplateApplicationScene',
      UISceneConfigurationName: 'CarPlay',
      UISceneDelegateClassName: CARPLAY_SCENE_DELEGATE,
    })
  }
  configurations[CARPLAY_SCENE_ROLE] = carPlayScenes
  return infoPlist
}

/**
 * Adds the CarPlay audio entitlement. Apple has to grant it to the app's
 * bundle ID before a signed build can use it.
 */
function addCarPlayEntitlement(entitlements) {
  entitlements[CARPLAY_AUDIO_ENTITLEMENT] = true
  return entitlements
}

module.exports = {
  addBackgroundAudio,
  addCast,
  addCarPlayScene,
  addCarPlayEntitlement,
}
