#!/bin/bash

set -e
set -u

pushd add-to-itunes
pod install
xcodebuild -workspace add-to-itunes.xcworkspace -scheme add-to-itunes clean build | xcpretty -c
popd
