#!/bin/bash
# Compila HackCheck come app universale (x86_64 + arm64). Richiede Xcode o Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
NAME="HackCheck"; OUT="build"; APP="$OUT/$NAME.app"
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in x86_64 arm64; do
  echo "→ Compilo $ARCH"
  swiftc -O -parse-as-library -swift-version 5 -target "$ARCH-apple-macos13.0" Sources/*.swift -o "$OUT/$NAME-$ARCH"
done
lipo -create "$OUT/$NAME-x86_64" "$OUT/$NAME-arm64" -output "$APP/Contents/MacOS/$NAME"
rm "$OUT/$NAME-x86_64" "$OUT/$NAME-arm64"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "✅ Fatto: $APP   (apri con: open $APP)"
