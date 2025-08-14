# ndi-webcam for macOS

A lightweight CLI application that streams your Mac's built-in camera over the local network using NDI (Network Device Interface) protocol. The camera automatically activates when subscribers connect and deactivates when they disconnect, preserving privacy and system resources.

## 🎯 Quick Start

```bash
# 1. Build the app (NDI SDK must be installed first)
swift build -c release

# 2. Run it
.build/release/ndi-webcam

# 3. Open NDI Studio Monitor or OBS with NDI plugin
# Your camera stream will appear as "Swift NDI Camera"
```

## ✅ Status

- **Built and Tested**: Application compiles and runs successfully
- **NDI SDK Integration**: Working with NDI SDK version 6.2.0.3
- **Camera Capture**: AVFoundation integration complete
- **Subscriber Detection**: Automatic camera on/off functionality working
- **CLI Interface**: Full command-line argument support

## 🚀 Features

- **Automatic Camera Management**: Camera turns on when NDI viewers connect, turns off when they disconnect
- **Smart Hysteresis**: 2-second delay before stopping camera to prevent flapping
- **High Performance**: Efficient YUV→BGRA pixel format conversion and frame buffering
- **CLI Interface**: Simple command-line tool with customizable options
- **Real-time Status**: Live FPS and subscriber count reporting
- **Clean Shutdown**: Proper resource cleanup on exit

## 📋 Prerequisites

### 1. Install NDI SDK (REQUIRED)

Download and install the NDI SDK for macOS from:
https://ndi.tv/sdk/

The SDK will be installed to `/Library/NDI SDK for Apple/`

⚠️ **This is mandatory** - the app cannot run without the NDI SDK installed.

### 2. Install Xcode Command Line Tools

```bash
xcode-select --install
```

## 🔨 Building

### Option 1: Using the Build Script (Recommended)

```bash
./build.sh
```

### Option 2: Manual Build

```bash
swift build -c release
```

The executable will be at `.build/release/ndi-webcam`

### Option 3: Using Xcode

1. Open `Package.swift` in Xcode
2. Select "My Mac" as the build target
3. Build with Cmd+B

## 📦 Installation & Distribution

### Local Installation

```bash
# Install system-wide
sudo cp .build/release/ndi-webcam /usr/local/bin/

# Or create symlink
sudo ln -sf $(pwd)/.build/release/ndi-webcam /usr/local/bin/ndi-webcam
```

### Distributing to Other Macs

⚠️ **Cannot create fully static binary** due to:
- NDI SDK only provides dynamic libraries
- macOS system frameworks are dynamic-only
- Swift runtime is dynamic on macOS

**Distribution options:**

1. **Simplest**: Recipient installs NDI SDK, then copy binary
2. **Bundle approach**: Copy both binary + NDI library with wrapper script
3. **App bundle**: Create .app package with embedded libraries

See "Distribution" section below for detailed instructions.

## 🖥️ Usage

### Basic Usage

```bash
.build/release/ndi-webcam
```

This starts streaming with default settings:
- Source name: "Swift NDI Camera"
- Resolution: 1080p
- Frame rate: 30 fps

### Command Line Options

```bash
ndi-webcam [options]

Options:
  --name <string>      NDI source name (default: "Swift NDI Camera")
  --resolution <res>   Resolution: 720p, 1080p (default), 4k
  --fps <number>       Frame rate (default: 30)
  --verbose, -v        Enable verbose logging
  --help, -h           Show help message
```

### Examples

```bash
# Custom name
.build/release/ndi-webcam --name "Mac Studio Camera"

# 4K at 60fps
.build/release/ndi-webcam --resolution 4k --fps 60

# Debug logging
.build/release/ndi-webcam --verbose

# Multiple options
.build/release/ndi-webcam --name "My Camera" --resolution 720p --fps 15 --verbose
```

### Expected Output

```
╔═══════════════════════════════════╗
║     NDI Camera Streamer v1.0      ║
╚═══════════════════════════════════╝

Source Name: Swift NDI Camera
Resolution: AVCaptureSessionPreset1920x1080
Frame Rate: 30.0 fps

Starting...
[10:22:49.300] [INFO] NDI library loaded from: /Library/NDI SDK for Apple/lib/macOS/libndi.dylib
[10:22:49.300] [INFO] NDI Library Version: NDI SDK APPLE 10:41:57 Jun  2 2025 6.2.0.3
[10:22:49.323] [INFO] NDI sender created: Swift NDI Camera
[10:22:49.323] [INFO] NDI stream available as: Swift NDI Camera
[10:22:49.323] [INFO] Waiting for subscribers...
[10:22:49.526] [INFO] Camera session configured successfully
```

## Camera Permissions

On first run, macOS will prompt for camera access. If you accidentally deny access:

1. Open System Preferences → Security & Privacy → Privacy → Camera
2. Add Terminal (or your terminal app) to the allowed list
3. Restart the application

## Viewing the Stream

### NDI Studio Monitor (Free)

1. Download NDI Tools from https://ndi.tv/tools/
2. Launch NDI Studio Monitor
3. Your stream will appear in the sources list
4. Click to view

### OBS Studio with NDI Plugin

1. Install OBS Studio
2. Install obs-ndi plugin from https://github.com/obs-ndi/obs-ndi
3. Add NDI Source in OBS
4. Select your camera stream

### Other NDI-Compatible Software

- Wirecast
- vMix
- TriCaster
- Any NDI-enabled application

## How It Works

1. **Subscriber Detection**: Polls NDI connection count every 500ms
2. **Camera Activation**: When first subscriber connects, camera starts
3. **Streaming**: Captures frames from AVFoundation, converts to BGRA, sends via NDI
4. **Camera Deactivation**: When all subscribers disconnect, waits 2 seconds (hysteresis), then stops camera
5. **Privacy**: Camera LED indicates when camera is active

## Troubleshooting

### NDI Library Not Found

If you see "Failed to load NDI library":
1. Ensure NDI SDK is installed from ndi.tv
2. Check the library exists at `/Library/NDI SDK for Apple/lib/macOS/libndi.dylib`
3. Try reinstalling the NDI SDK

### Camera Access Denied

If you see "Camera access denied":
1. Grant camera permission when prompted
2. Or manually enable in System Preferences → Security & Privacy → Camera

### No Stream Visible

1. Ensure you're on the same network/subnet
2. Check firewall settings (NDI uses mDNS for discovery)
3. Try specifying IP address in viewer instead of auto-discovery

### Performance Issues

- Lower resolution: `--resolution 720p`
- Reduce frame rate: `--fps 15`
- Close other camera-using applications

## Architecture

```
Camera → AVCaptureSession → CMSampleBuffer → CVPixelBuffer
           ↓
    Color Conversion (YUV→BGRA)
           ↓
    NDI Video Frame → Network
           ↓
    Subscriber Monitor → Camera Control
```

## License

This project is provided as-is for educational and personal use.

## 📦 Distribution to Other Macs

### Method 1: Simple Copy (Requires NDI SDK on target)

**On target Mac:**
```bash
# 1. Install NDI SDK from https://ndi.tv/sdk/
# 2. Copy the binary
scp source-mac:/path/to/.build/release/ndi-webcam /usr/local/bin/
# 3. Run
ndi-webcam
```

### Method 2: Bundle Distribution

Create a portable bundle:
```bash
# Create distribution package
mkdir ndi-webcam-portable
cp .build/release/ndi-webcam ndi-webcam-portable/
cp /Library/NDI\ SDK\ for\ Apple/lib/macOS/libndi.dylib ndi-webcam-portable/

# Create wrapper script
cat > ndi-webcam-portable/run.sh << 'EOF'
#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export DYLD_LIBRARY_PATH="$DIR:$DYLD_LIBRARY_PATH"
"$DIR/ndi-webcam" "$@"
EOF
chmod +x ndi-webcam-portable/run.sh

# Zip for distribution
zip -r ndi-webcam-portable.zip ndi-webcam-portable/
```

**On target Mac:**
```bash
unzip ndi-webcam-portable.zip
cd ndi-webcam-portable
./run.sh --help
```

### Why No Static Binary?

⚠️ **Cannot create fully static binary** because:
- NDI SDK only provides dynamic libraries (`.dylib`)
- macOS system frameworks (AVFoundation, CoreMedia) are dynamic-only
- Swift runtime on macOS uses dynamic linking

## 🧪 Testing

Test the built application:
```bash
# Quick test (runs briefly then stops)
./test-ndi.sh

# Manual test with verbose output
.build/release/ndi-webcam --name "Test Camera" --verbose
# Press Ctrl+C to stop
```

## 📋 When You Come Back

### Quick Reference Commands

```bash
# Build the project
swift build -c release

# Run with default settings
.build/release/ndi-webcam

# Run with custom settings
.build/release/ndi-webcam --name "My Camera" --resolution 720p --fps 30 --verbose

# Install system-wide
sudo cp .build/release/ndi-webcam /usr/local/bin/

# Test NDI SDK is working
./test-ndi.sh
```

### What Works
- ✅ Builds successfully with NDI SDK 6.2.0.3
- ✅ Camera capture and NDI streaming functional
- ✅ Automatic camera on/off based on subscribers
- ✅ CLI arguments and help system
- ✅ Proper error handling and logging

### Distribution Notes
- Binary requires NDI SDK on target machine
- Cannot be made fully static due to dynamic library dependencies
- Use bundle method (Method 2 above) for easiest distribution

## Acknowledgments

- NDI® is a registered trademark of Vizrt Group
- Built with Swift and AVFoundation for macOS
- Tested with NDI SDK version 6.2.0.3