import {
  androidPlatform,
  androidEmulator,
} from '@react-native-harness/platform-android';
import {
  applePlatform,
  appleSimulator,
} from '@react-native-harness/platform-apple';

const config = {
  defaultRunner: 'ios',
  // Playback tests wait on real audio; the 60s default trips mid-suite.
  bridgeTimeout: 600000,
  entryPoint: './index.js',
  appRegistryComponentName: 'example',
  forwardClientLogs: true,
  runners: [
    androidPlatform({
      name: 'android',
      device: androidEmulator(process.env.HARNESS_ANDROID_AVD ?? 'Pixel_6_Pro'),
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