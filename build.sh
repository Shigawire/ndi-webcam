#!/bin/bash

echo "Building ndi-webcam..."

# Check if NDI SDK is installed
if [ ! -d "/Library/NDI SDK for Apple" ]; then
    echo "❌ Error: NDI SDK not found!"
    echo "Please download and install from: https://ndi.tv/sdk/"
    exit 1
fi

# Build in release mode
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    echo "Executable location: .build/release/ndi-webcam"
    echo ""
    echo "To install system-wide:"
    echo "  sudo cp .build/release/ndi-webcam /usr/local/bin/"
    echo ""
    echo "To run directly:"
    echo "  .build/release/ndi-webcam --help"
else
    echo "❌ Build failed!"
    exit 1
fi