const {
  createRunOncePlugin,
  withAndroidManifest,
  withDangerousMod,
  withEntitlementsPlist,
  withGradleProperties,
  withInfoPlist,
} = require('expo/config-plugins')
const pkg = require('../package.json')
const { resolveOptions } = require('./options')
const android = require('./android')
const ios = require('./ios')

function withNitroPlayerAndroid(config, options) {
  if (options.castEnabled !== undefined) {
    config = withGradleProperties(config, (modConfig) => {
      android.setCastEnabled(modConfig.modResults, options.castEnabled)
      return modConfig
    })
  }

  const needsBrowserService =
    options.androidAutoEnabled || options.playbackResumptionEnabled
  if (needsBrowserService || options.voiceSearchEnabled) {
    config = withAndroidManifest(config, (modConfig) => {
      if (needsBrowserService) {
        android.addMediaBrowserService(modConfig.modResults)
      }
      if (options.androidAutoEnabled) {
        android.addAndroidAutoMetaData(modConfig.modResults)
      }
      if (options.voiceSearchEnabled) {
        android.addVoiceSearch(modConfig.modResults)
      }
      return modConfig
    })
  }

  if (options.androidAutoEnabled) {
    config = withDangerousMod(config, [
      'android',
      async (modConfig) => {
        android.writeAutomotiveAppDescriptor(
          modConfig.modRequest.platformProjectRoot
        )
        return modConfig
      },
    ])
  }
  return config
}

function withNitroPlayerIos(config, options) {
  config = withInfoPlist(config, (modConfig) => {
    ios.addBackgroundAudio(modConfig.modResults)
    if (options.castEnabled) {
      ios.addCast(modConfig.modResults, options)
    }
    if (options.carPlayEnabled) {
      ios.addCarPlayScene(modConfig.modResults)
    }
    return modConfig
  })

  if (options.carPlayEnabled) {
    config = withEntitlementsPlist(config, (modConfig) => {
      ios.addCarPlayEntitlement(modConfig.modResults)
      return modConfig
    })
  }
  return config
}

/**
 * Expo config plugin for react-native-nitro-player.
 *
 * @param {import('expo/config').ExpoConfig} config
 * @param {import('./options').NitroPlayerPluginOptions} [props]
 */
function withNitroPlayer(config, props) {
  const options = resolveOptions(props)
  config = withNitroPlayerAndroid(config, options.android)
  config = withNitroPlayerIos(config, options.ios)
  return config
}

module.exports = createRunOncePlugin(withNitroPlayer, pkg.name, pkg.version)
