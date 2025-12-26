#!/bin/bash

set -e

KOTLIN_DIRS=(
  "react-native-nitro-player/android/src/main/java"
  "example/android/app/src/main/java"
)

if which ktlint >/dev/null; then
  # Find all .kt files excluding generated and build directories
  KOTLIN_FILES=$(find "${KOTLIN_DIRS[@]}" -type f -name '*.kt' ! -path '*/generated/*' ! -path '*/build/*' 2>/dev/null || true)
  
  if [ -z "$KOTLIN_FILES" ]; then
    echo "No Kotlin files found to check."
    exit 0
  fi
  
  echo "$KOTLIN_FILES" | xargs ktlint
  echo "Kotlin Format check passed!"
else
  echo "error: ktlint not installed, install with 'npm install -g ktlint' or 'brew install ktlint' (see https://github.com/pinterest/ktlint)"
  exit 1
fi

