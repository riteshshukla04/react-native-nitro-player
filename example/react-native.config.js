// iOS builds through SwiftPM, which cannot compile these libraries' mixed Swift + Objective-C sources yet
module.exports = {
  dependencies: {
    'react-native-audio-pro': { platforms: { ios: null } },
    'react-native-screens': { platforms: { ios: null } },
  },
};
