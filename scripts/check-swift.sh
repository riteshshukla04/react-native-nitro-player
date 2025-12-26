#!/bin/bash

set -e

SWIFT_DIRS=(
  "react-native-nitro-player/ios"
  "example/ios"
)

# Try to find swift-format (required for linting)
SWIFT_FORMAT_CMD=""
if command -v swift-format >/dev/null 2>&1; then
  SWIFT_FORMAT_CMD="swift-format lint"
else
  echo "error: swift-format not found. Install with one of:"
  echo "  - swift package install swift-format (via Swift Package Manager)"
  echo "  - brew install swift-format (via Homebrew)"
  echo "  - Or install via Swiftly: curl -LsSf https://swiftly.dev/install.sh | sh"
  exit 1
fi

DIRS=$(printf "%s " "${SWIFT_DIRS[@]}")
ERROR_COUNT=0

# Collect all Swift files first
SWIFT_FILES=$(find $DIRS -type f \( -name "*.swift" \) ! -path "*/Pods/*" ! -path "*/generated/*" ! -path "*/nitrogen/generated/*" 2>/dev/null || true)

if [ -z "$SWIFT_FILES" ]; then
  echo "No Swift files found to check."
  exit 0
fi

# Check each file
for file in $SWIFT_FILES; do
  if ! $SWIFT_FORMAT_CMD "$file" >/dev/null 2>&1; then
    echo "Formatting issue in: $file"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
done

if [ $ERROR_COUNT -eq 0 ]; then
  echo "Swift Format check passed!"
  exit 0
else
  echo "Swift Format check failed! Found $ERROR_COUNT file(s) with formatting issues."
  echo "Run 'npm run format:swift' to fix."
  exit 1
fi

