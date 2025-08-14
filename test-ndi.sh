#!/bin/bash

echo "Testing ndi-webcam..."
echo "===================="
echo ""

# Check if NDI SDK is installed
if [ -f "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib" ]; then
    echo "✅ NDI SDK found at: /Library/NDI SDK for Apple/lib/macOS/libndi.dylib"
else
    echo "❌ NDI SDK not found. Please install from https://ndi.tv/sdk/"
    exit 1
fi

echo ""
echo "Starting ndi-webcam..."
echo "Press Ctrl+C to stop"
echo ""

# Run with brief timeout for testing (timeout doesn't exist on macOS, use different approach)
(.build/release/ndi-webcam --name "Test Camera" --verbose &) && sleep 3 && pkill -f ndi-webcam 2>/dev/null || true

echo ""
echo "Test completed. If you saw 'NDI Library Version' above, the app is working!"
echo "For actual use, run: .build/release/ndi-webcam"