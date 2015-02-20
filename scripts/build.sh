#!/bin/bash

set -e
set -u

function normalize() {
    echo $( cd "$1" && pwd )
}

scripts_directory=$(normalize $(dirname "${BASH_SOURCE[0]}"))
root_directory=$(normalize "$scripts_directory/..")
source_directory="$root_directory/add-to-itunes"
build_directory="$root_directory/build"

if [[ -e "$build_directory" ]]; then
    echo "Removing '$build_directory'..."
    rm -r "$build_directory"
fi

echo "Creating '$build_directory'..."
mkdir -p "$build_directory"

pushd "$source_directory" > /dev/null
echo "Updating CocoaPods..."
pod install --silent
xcodebuild -workspace add-to-itunes.xcworkspace -scheme add-to-itunes -derivedDataPath "$build_directory" clean build | xcpretty -c
popd > /dev/null
