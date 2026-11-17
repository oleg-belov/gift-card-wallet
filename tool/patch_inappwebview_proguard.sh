#!/usr/bin/env bash
# Patches flutter_inappwebview_android's build.gradle in the pub cache.
#
# Newer Android Gradle Plugins reject getDefaultProguardFile('proguard-android.txt')
# (it includes -dontoptimize), which breaks the build with:
#   "A problem occurred evaluating project ':flutter_inappwebview_android'"
#
# `flutter pub get` restores the original file whenever the pub cache is
# repaired or the package re-downloaded, so re-run this script after that.
set -euo pipefail

FILE="$HOME/.pub-cache/hosted/pub.dev/flutter_inappwebview_android-1.1.3/android/build.gradle"

if [[ ! -f "$FILE" ]]; then
  echo "Not found: $FILE"
  echo "Run 'flutter pub get' first, or adjust the version in this script."
  exit 1
fi

if grep -q "proguard-android-optimize.txt" "$FILE"; then
  echo "Already patched: $FILE"
  exit 0
fi

sed -i '' "s/getDefaultProguardFile('proguard-android.txt')/getDefaultProguardFile('proguard-android-optimize.txt')/g" "$FILE"
echo "Patched: $FILE"
