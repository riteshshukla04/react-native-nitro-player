/* eslint-env es2020, node */
import assert from 'node:assert/strict'
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  mkdirSync,
} from 'node:fs'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

// The pure transforms run without Expo installed; app.plugin.js only wires them to Expo's mods
const require = createRequire(import.meta.url)
const plugin = '../../react-native-nitro-player/plugin'
const { resolveOptions } = require(`${plugin}/options.js`)
const android = require(`${plugin}/android.js`)
const ios = require(`${plugin}/ios.js`)

const BROWSER_SERVICE =
  'com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService'

function expoManifest() {
  return {
    manifest: {
      $: { 'xmlns:android': 'http://schemas.android.com/apk/res/android' },
      application: [
        {
          $: { 'android:name': '.MainApplication' },
          activity: [
            {
              '$': { 'android:name': '.MainActivity' },
              'intent-filter': [
                {
                  action: [
                    { $: { 'android:name': 'android.intent.action.MAIN' } },
                  ],
                  category: [
                    {
                      $: { 'android:name': 'android.intent.category.LAUNCHER' },
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  }
}

function sceneInfoPlist() {
  return {
    UIApplicationSceneManifest: {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          {
            UISceneConfigurationName: 'Default Configuration',
            UISceneDelegateClassName: '$(PRODUCT_MODULE_NAME).SceneDelegate',
          },
        ],
      },
    },
  }
}

test('options default to Cast on iOS and leave Cast unset on Android', () => {
  for (const options of [undefined, null, {}]) {
    assert.deepEqual(resolveOptions(options), {
      android: {
        castEnabled: undefined,
        androidAutoEnabled: false,
        playbackResumptionEnabled: false,
        voiceSearchEnabled: false,
      },
      ios: {
        castEnabled: true,
        castReceiverApplicationId: 'CC1AD845',
        localNetworkUsageDescription: undefined,
        carPlayEnabled: false,
      },
    })
  }
})

test('options reject typos, wrong types and settings that would be ignored', () => {
  assert.throws(
    () => resolveOptions({ castEnabled: false }),
    /unknown plugin option "castEnabled"/
  )
  assert.throws(
    () => resolveOptions({ android: { castEnable: false } }),
    /"android.castEnable"/
  )
  assert.throws(
    () => resolveOptions({ android: { castEnabled: 'false' } }),
    /must be a boolean/
  )
  assert.throws(() => resolveOptions({ ios: [] }), /"ios" must be an object/)
  assert.throws(
    () =>
      resolveOptions({
        ios: { castEnabled: false, castReceiverApplicationId: 'ABCD1234' },
      }),
    /no effect while "ios.castEnabled" is false/
  )
  assert.throws(
    () => resolveOptions({ ios: { castReceiverApplicationId: '_x._tcp' } }),
    /receiver app ID/
  )
  assert.throws(
    () => resolveOptions({ ios: { localNetworkUsageDescription: '' } }),
    /can't be empty/
  )
})

test('the Cast gradle property is written once and updated in place', () => {
  const properties = [{ type: 'property', key: 'hermesEnabled', value: 'true' }]
  android.setCastEnabled(properties, false)
  android.setCastEnabled(properties, true)
  const entries = properties.filter(
    item => item.key === 'nitroPlayerCastEnabled'
  )
  assert.deepEqual(entries, [
    { type: 'property', key: 'nitroPlayerCastEnabled', value: 'true' },
  ])
})

test('Android Auto and voice search entries are added once', () => {
  const manifest = expoManifest()
  for (let run = 0; run < 2; run++) {
    android.addMediaBrowserService(manifest)
    android.addAndroidAutoMetaData(manifest)
    android.addVoiceSearch(manifest)
  }
  const application = manifest.manifest.application[0]
  assert.equal(
    manifest.manifest.$['xmlns:tools'],
    'http://schemas.android.com/tools'
  )
  assert.deepEqual(
    application.service.map(service => service.$['android:name']),
    [BROWSER_SERVICE]
  )
  assert.equal(
    application.service[0]['intent-filter'][0].action[0].$['android:name'],
    'android.media.browse.MediaBrowserService'
  )
  assert.deepEqual(application['meta-data'], [
    {
      $: {
        'android:name': 'com.google.android.gms.car.application',
        'android:resource': '@xml/automotive_app_desc',
      },
    },
  ])
  const filters = application.activity[0]['intent-filter']
  assert.equal(filters.length, 2)
  assert.equal(
    filters[1].action[0].$['android:name'],
    'android.media.action.MEDIA_PLAY_FROM_SEARCH'
  )
})

test('an existing browser service declaration is kept as it is', () => {
  const manifest = expoManifest()
  const own = {
    $: { 'android:name': BROWSER_SERVICE, 'android:exported': 'true' },
  }
  manifest.manifest.application[0].service = [own]
  android.addMediaBrowserService(manifest)
  assert.deepEqual(manifest.manifest.application[0].service, [own])
})

test('voice search needs a launcher activity', () => {
  const manifest = expoManifest()
  manifest.manifest.application[0].activity = []
  assert.throws(() => android.addVoiceSearch(manifest), /no launcher activity/)
})

test('the automotive app descriptor is written unless the project has one', () => {
  const root = mkdtempSync(join(tmpdir(), 'nitro-plugin-test-'))
  try {
    const file = join(root, 'app/src/main/res/xml/automotive_app_desc.xml')
    android.writeAutomotiveAppDescriptor(root)
    assert.match(readFileSync(file, 'utf8'), /<uses name="media" \/>/)

    writeFileSync(file, '<automotiveApp />')
    android.writeAutomotiveAppDescriptor(root)
    assert.equal(readFileSync(file, 'utf8'), '<automotiveApp />')
  } finally {
    rmSync(root, { recursive: true, force: true })
  }
  const empty = mkdtempSync(join(tmpdir(), 'nitro-plugin-test-'))
  try {
    mkdirSync(join(empty, 'app'))
    android.writeAutomotiveAppDescriptor(empty)
    assert.ok(
      existsSync(join(empty, 'app/src/main/res/xml/automotive_app_desc.xml'))
    )
  } finally {
    rmSync(empty, { recursive: true, force: true })
  }
})

test('background audio and Cast keys are added without duplicates', () => {
  const infoPlist = {
    UIBackgroundModes: ['fetch', 'audio'],
    NSBonjourServices: ['_googlecast._tcp', '_other._tcp'],
  }
  ios.addBackgroundAudio(infoPlist)
  ios.addCast(infoPlist, { castReceiverApplicationId: 'ABCD1234' })
  assert.deepEqual(infoPlist.UIBackgroundModes, ['fetch', 'audio'])
  assert.deepEqual(infoPlist.NSBonjourServices, [
    '_googlecast._tcp',
    '_other._tcp',
    '_ABCD1234._googlecast._tcp',
  ])
  assert.match(infoPlist.NSLocalNetworkUsageDescription, /Cast devices/)
})

test('the local network description prefers the option, then an existing value', () => {
  const existing = { NSLocalNetworkUsageDescription: 'Finds speakers' }
  ios.addCast(existing, { castReceiverApplicationId: 'CC1AD845' })
  assert.equal(existing.NSLocalNetworkUsageDescription, 'Finds speakers')

  ios.addCast(existing, {
    castReceiverApplicationId: 'CC1AD845',
    localNetworkUsageDescription: 'Finds TVs',
  })
  assert.equal(existing.NSLocalNetworkUsageDescription, 'Finds TVs')
})

test('the CarPlay scene goes first in its role and is added once', () => {
  const infoPlist = sceneInfoPlist()
  const other = {
    UISceneConfigurationName: 'Other',
    UISceneDelegateClassName: 'OtherDelegate',
  }
  infoPlist.UIApplicationSceneManifest.UISceneConfigurations.CPTemplateApplicationSceneSessionRoleApplication =
    [other]
  ios.addCarPlayScene(infoPlist)
  ios.addCarPlayScene(infoPlist)
  const manifest = infoPlist.UIApplicationSceneManifest
  assert.equal(manifest.UIApplicationSupportsMultipleScenes, true)
  assert.deepEqual(
    manifest.UISceneConfigurations
      .CPTemplateApplicationSceneSessionRoleApplication,
    [
      {
        UISceneClassName: 'CPTemplateApplicationScene',
        UISceneConfigurationName: 'CarPlay',
        UISceneDelegateClassName: 'NitroPlayerCarPlaySceneDelegate',
      },
      other,
    ]
  )
  assert.equal(
    manifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication.length,
    1
  )
})

test('CarPlay refuses an app without a phone scene', () => {
  assert.throws(() => ios.addCarPlayScene({}), /needs a scene-based iOS app/)
  const infoPlist = sceneInfoPlist()
  infoPlist.UIApplicationSceneManifest.UISceneConfigurations.UIWindowSceneSessionRoleApplication =
    []
  assert.throws(() => ios.addCarPlayScene(infoPlist), /Expo SDK 58/)
})

test('the CarPlay audio entitlement is set', () => {
  assert.deepEqual(ios.addCarPlayEntitlement({}), {
    'com.apple.developer.carplay-audio': true,
  })
})
