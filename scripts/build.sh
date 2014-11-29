#!/bin/bash

pushd add-to-itunes
xcodebuild -workspace add-to-itunes.xcworkspace -scheme add-to-itunes clean build
