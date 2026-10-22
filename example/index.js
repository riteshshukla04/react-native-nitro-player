/**
 * @format
 */

import { AppRegistry, Platform } from 'react-native';
import { enableScreens } from 'react-native-screens';
import App from './App';
import { name as appName } from './app.json';

// react-native-screens is not linked on iOS (no SwiftPM support), so tabs render plain Views there
if (Platform.OS === 'ios') {
  enableScreens(false);
}

AppRegistry.registerComponent(appName, () => App);
