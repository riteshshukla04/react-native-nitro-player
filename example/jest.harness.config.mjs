import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const reactNativeJestPreset = require('react-native/jest-preset');

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// react-native-harness preset only sets `runner`; we need RN's babel-jest transform for .ts.
// Omit Jest `setupFiles` here: they target Node (e.g. jest/setup.js) and break Metro when the
// harness bundles tests on device.
export default {
  ...reactNativeJestPreset,
  rootDir: __dirname,
  runner: '@react-native-harness/jest',
  setupFiles: [],
  testTimeout: 300000,
};
