#!/bin/bash
# Builds a Release copy of Orbit.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
xcodebuild -project Orbit.xcodeproj -scheme Orbit -configuration Release \
  -derivedDataPath build/DerivedData build
rm -rf build/Orbit.app
cp -R build/DerivedData/Build/Products/Release/Orbit.app build/Orbit.app
echo "Built: $(pwd)/build/Orbit.app — drag it into Applications."
open -R build/Orbit.app
