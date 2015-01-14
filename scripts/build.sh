#!/bin/bash

set -e
set -u

pushd add-to-itunes
echo "Updating CocoaPods..."
pod install --silent
xcodebuild -workspace add-to-itunes.xcworkspace -scheme add-to-itunes clean build | xcpretty -c
popd
