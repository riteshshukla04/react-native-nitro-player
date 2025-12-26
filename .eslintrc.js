module.exports = {
  root: true,
  extends: ['@react-native', 'prettier'],
  plugins: ['prettier'],
  rules: {
    'prettier/prettier': [
      'warn',
      {
        quoteProps: 'consistent',
        singleQuote: true,
        tabWidth: 2,
        trailingComma: 'es5',
        useTabs: false,
        semi: false,
      },
    ],
  },
  ignorePatterns: [
    'node_modules/',
    'lib/',
    'nitrogen/generated/',
    '*.generated.*',
    'android/',
    'ios/',
  ],
}
