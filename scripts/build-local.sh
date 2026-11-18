#!/bin/sh
# Build and run `bf` with plain swiftc, for machines with only the Command Line Tools
# (old SwiftPM there refuses to build without XCTest). With Xcode, use `swift run bf`.
set -e
cd "$(dirname "$0")/.."
B=${BUILD_DIR:-.build/local}
mkdir -p "$B"
swiftc -O -parse-as-library -emit-library -static -module-name BarcodeFrames \
  -emit-module-path "$B/BarcodeFrames.swiftmodule" -o "$B/libBarcodeFrames.a" Sources/BarcodeFrames/*.swift
if [ -n "$(ls Sources/BarcodeFramesUI/*.swift 2>/dev/null)" ]; then
  swiftc -O -parse-as-library -emit-library -static -module-name BarcodeFramesUI -I "$B" \
    -emit-module-path "$B/BarcodeFramesUI.swiftmodule" -o "$B/libBarcodeFramesUI.a" Sources/BarcodeFramesUI/*.swift
fi
swiftc -O -I "$B" -L "$B" -lBarcodeFrames -o "$B/bf" Sources/bf/main.swift
exec "$B/bf" "$@"
