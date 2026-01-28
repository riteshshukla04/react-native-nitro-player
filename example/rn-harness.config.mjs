import {
  androidPlatform,
  androidEmulator,
} from '@react-native-harness/platform-android';
import {
  applePlatform,
  appleSimulator,
} from '@react-native-harness/platform-apple';

const config = {
  entryPoint: './index.js',
  appRegistryComponentName: 'example',
  forwardClientLogs: true,
  runners: [
    androidPlatform({
      name: 'android',
      device: androidEmulator('Pixel_6_Pro'), // Your Android emulator name
      bundleId: 'com.example', // Your Android bundle ID
    }),
    applePlatform({
      name: 'ios',
      device: appleSimulator('iPhone 17', '26.2'), // Your iOS simulator name and version
      bundleId: 'org.reactjs.native.example.example', // Your iOS bundle ID
    }),
  ],
};

export default config;