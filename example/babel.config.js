module.exports = {
  presets: ['module:@react-native/babel-preset'],
  // Nitro specs use `@iOS(...)`/`@Android(...)` on `declare class`, and Metro compiles the player from source
  parserOpts: { plugins: ['decorators'] },
};
