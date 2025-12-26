#!/bin/bash

set -e

SWIFT_DIRS=(
  "react-native-nitro-player/ios"
  "example/ios"
)

if which swift >/dev/null; then
  DIRS=$(printf "%s " "${SWIFT_DIRS[@]}")
  find $DIRS -type f \( -name "*.swift" \) ! -path "*/Pods/*" ! -path "*/generated/*" ! -path "*/nitrogen/generated/*" -print0 | while read -d $'\0' file; do
    swift format --in-place "$file"
  done
  echo "Swift Format done!"
else
  echo "error: swift not installed, install the toolchain with Xcode."
  exit 1
fi

