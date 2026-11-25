const fs = require('fs')
const path = require('path')

const PACKAGE = 'react-native-nitro-player'
const CAST_ENABLED_PROPERTY = 'nitroPlayerCastEnabled'
const MEDIA_BROWSER_SERVICE =
  'com.margelo.nitro.nitroplayer.media.NitroPlayerMediaBrowserService'
const CAR_APPLICATION_META_DATA = 'com.google.android.gms.car.application'
const PLAY_FROM_SEARCH_ACTION = 'android.media.action.MEDIA_PLAY_FROM_SEARCH'
const AUTOMOTIVE_APP_DESC_PATH = path.join(
  'app',
  'src',
  'main',
  'res',
  'xml',
  'automotive_app_desc.xml'
)
const AUTOMOTIVE_APP_DESC = `<?xml version="1.0" encoding="utf-8"?>
<automotiveApp>
  <uses name="media" />
</automotiveApp>
`

function hasName(element, name) {
  return element.$ !== undefined && element.$['android:name'] === name
}

/**
 * Sets `nitroPlayerCastEnabled` in the parsed `gradle.properties`.
 */
function setCastEnabled(properties, castEnabled) {
  const value = String(castEnabled)
  const existing = properties.find(
    (item) => item.type === 'property' && item.key === CAST_ENABLED_PROPERTY
  )
  if (existing !== undefined) {
    existing.value = value
    return properties
  }
  properties.push(
    {
      type: 'comment',
      value: `${PACKAGE}: false builds without the Google Cast SDK`,
    },
    { type: 'property', key: CAST_ENABLED_PROPERTY, value }
  )
  return properties
}

function getApplication(androidManifest) {
  const application = androidManifest.manifest.application?.[0]
  if (application === undefined) {
    throw new Error(
      `${PACKAGE}: AndroidManifest.xml has no <application> element.`
    )
  }
  return application
}

function isLauncherFilter(filter) {
  return (
    (filter.action ?? []).some((action) =>
      hasName(action, 'android.intent.action.MAIN')
    ) &&
    (filter.category ?? []).some((category) =>
      hasName(category, 'android.intent.category.LAUNCHER')
    )
  )
}

function getLauncherActivity(androidManifest) {
  const activities = getApplication(androidManifest).activity ?? []
  const activity = activities.find((item) =>
    (item['intent-filter'] ?? []).some(isLauncherFilter)
  )
  if (activity === undefined) {
    throw new Error(
      `${PACKAGE}: AndroidManifest.xml has no launcher activity for the voice search intent filter.`
    )
  }
  return activity
}

/**
 * Declares the media browser service that Android Auto browses and that the
 * phone's media controls resume playback through. Keeps an existing
 * declaration as it is.
 */
function addMediaBrowserService(androidManifest) {
  const manifest = androidManifest.manifest
  if (manifest.$['xmlns:tools'] === undefined) {
    manifest.$['xmlns:tools'] = 'http://schemas.android.com/tools'
  }
  const application = getApplication(androidManifest)
  const services = application.service ?? []
  if (!services.some((service) => hasName(service, MEDIA_BROWSER_SERVICE))) {
    services.push({
      '$': {
        'android:name': MEDIA_BROWSER_SERVICE,
        'android:foregroundServiceType': 'mediaPlayback',
        'android:exported': 'true',
        'tools:ignore': 'ExportedService',
      },
      'intent-filter': [
        {
          action: [
            {
              $: { 'android:name': 'android.media.browse.MediaBrowserService' },
            },
          ],
        },
      ],
    })
  }
  application.service = services
  return androidManifest
}

/**
 * Adds the meta-data that lists the app in Android Auto. Keeps an existing
 * entry as it is.
 */
function addAndroidAutoMetaData(androidManifest) {
  const application = getApplication(androidManifest)
  const metaData = application['meta-data'] ?? []
  if (!metaData.some((item) => hasName(item, CAR_APPLICATION_META_DATA))) {
    metaData.push({
      $: {
        'android:name': CAR_APPLICATION_META_DATA,
        'android:resource': '@xml/automotive_app_desc',
      },
    })
  }
  application['meta-data'] = metaData
  return androidManifest
}

/**
 * Adds the `MEDIA_PLAY_FROM_SEARCH` intent filter to the launcher activity.
 */
function addVoiceSearch(androidManifest) {
  const activity = getLauncherActivity(androidManifest)
  const filters = activity['intent-filter'] ?? []
  const hasFilter = filters.some((filter) =>
    (filter.action ?? []).some((action) =>
      hasName(action, PLAY_FROM_SEARCH_ACTION)
    )
  )
  if (!hasFilter) {
    filters.push({
      action: [{ $: { 'android:name': PLAY_FROM_SEARCH_ACTION } }],
      category: [{ $: { 'android:name': 'android.intent.category.DEFAULT' } }],
    })
  }
  activity['intent-filter'] = filters
  return androidManifest
}

/**
 * Writes `res/xml/automotive_app_desc.xml` unless the project already has one.
 *
 * @param {string} platformProjectRoot The `android` directory.
 */
function writeAutomotiveAppDescriptor(platformProjectRoot) {
  const file = path.join(platformProjectRoot, AUTOMOTIVE_APP_DESC_PATH)
  if (fs.existsSync(file)) return
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, AUTOMOTIVE_APP_DESC)
}

module.exports = {
  setCastEnabled,
  addMediaBrowserService,
  addAndroidAutoMetaData,
  addVoiceSearch,
  writeAutomotiveAppDescriptor,
}
