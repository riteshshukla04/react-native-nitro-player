#!/bin/bash

set -e

SWIFT_DIRS=(
  "react-native-nitro-player/ios"
  "example/ios"
)

if which swift >/dev/null; then
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
    if ! swift format --mode lint "$file" >/dev/null 2>&1; then
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
else
  echo "error: swift not installed, install the toolchain with Xcode."
  exit 1
fi

