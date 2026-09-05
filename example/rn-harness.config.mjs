import {
  androidPlatform,
  androidEmulator,
  physicalAndroidDevice,
} from '@react-native-harness/platform-android';
import {
  applePlatform,
  appleSimulator,
} from '@react-native-harness/platform-apple';

const config = {
  defaultRunner: 'ios',
  // Playback tests wait on real audio; a whole suite must fit in one RPC.
  bridgeTimeout: 1800000,
  entryPoint: './index.js',
  appRegistryComponentName: 'example',
  forwardClientLogs: true,
  runners: [
    androidPlatform({
      name: 'android',
      // Set HARNESS_ANDROID_MANUFACTURER/MODEL to run on a plugged-in phone instead of an emulator.
      device: process.env.HARNESS_ANDROID_MODEL
        ? physicalAndroidDevice(
            process.env.HARNESS_ANDROID_MANUFACTURER ?? 'samsung',
            process.env.HARNESS_ANDROID_MODEL
          )
        : androidEmulator(process.env.HARNESS_ANDROID_AVD ?? 'Pixel_8_API_35'),
      bundleId: 'com.example', // Your Android bundle ID
    }),
    applePlatform({
      name: 'ios',
      // Overridable so CI can point at whichever runtime the image actually ships.
      device: appleSimulator(
        process.env.HARNESS_IOS_DEVICE ?? 'iPhone 17',
        process.env.HARNESS_IOS_VERSION ?? '26.5'
      ),
      bundleId: 'org.reactjs.native.example.example', // Your iOS bundle ID
    }),
  ],
};

export default config;