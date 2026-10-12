#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release -Xcc -Wall -Xcc -Wextra -Xcc -Werror -Xswiftc -warnings-as-errors
bin_dir=$(swift build -c release --show-bin-path)
app_dir="$PWD/.build/HeatWatch.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/HeatWatch" "$app_dir/Contents/MacOS/HeatWatch"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --strict "$app_dir"
printf '\nBuilt: %s\n' "$app_dir"
