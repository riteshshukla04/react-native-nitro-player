#!/bin/bash

set -e

SWIFT_DIRS=(
  "react-native-nitro-player/ios"
  "example/ios"
)

# Try to find swift-format or swift format
SWIFT_FORMAT_CMD=""
if command -v swift-format >/dev/null 2>&1; then
  SWIFT_FORMAT_CMD="swift-format format --in-place"
elif command -v swift >/dev/null 2>&1 && swift format --version >/dev/null 2>&1; then
  SWIFT_FORMAT_CMD="swift format --in-place"
else
  echo "error: swift-format not found. Install with one of:"
  echo "  - swift package install swift-format (via Swift Package Manager)"
  echo "  - brew install swift-format (via Homebrew)"
  echo "  - Or ensure swift toolchain is installed with Xcode"
  exit 1
fi

DIRS=$(printf "%s " "${SWIFT_DIRS[@]}")
find $DIRS -type f \( -name "*.swift" \) ! -path "*/Pods/*" ! -path "*/generated/*" ! -path "*/nitrogen/generated/*" -print0 | while read -d $'\0' file; do
  $SWIFT_FORMAT_CMD "$file"
done
echo "Swift Format done!"

