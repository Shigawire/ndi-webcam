# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Swift CLI application that streams macOS camera feeds over the network using NDI (Network Device Interface) protocol. The app automatically manages camera activation based on subscriber connections for privacy and resource efficiency.

## Build and Development Commands

```bash
# Build the project
swift build -c release

# Build using the provided script (recommended - includes NDI SDK check)
./build.sh

# Quick test run
./test-ndi.sh

# Run the application
.build/release/ndi-webcam

# Run with custom options
.build/release/ndi-webcam --name "My Camera" --resolution 720p --fps 30 --verbose

# Install system-wide
sudo cp .build/release/ndi-webcam /usr/local/bin/
```

## Architecture

### Core Components

- **NDIWebcam** (main.swift): Main orchestrator that coordinates all components
- **CameraCapture**: AVFoundation-based camera capture with automatic format negotiation
- **NDISender**: NDI library wrapper for video streaming  
- **SubscriberMonitor**: Tracks NDI viewer connections for automatic camera control
- **FrameConverter**: Optimized YUV→BGRA pixel format conversion
- **Logger**: Centralized logging with configurable levels

### Data Flow

```
Camera → AVCaptureSession → CMSampleBuffer → FrameConverter (YUV→BGRA) → NDISender → Network
                                                    ↑
                                         SubscriberMonitor ← NDI Connection Count
                                                    ↓
                                           Camera Start/Stop Control
```

### Key Design Patterns

- **Delegate pattern**: Camera capture and subscriber monitoring use delegates for loose coupling
- **Async queues**: Separate queues for camera session, output processing, and NDI sending
- **Hysteresis control**: 2-second delay before stopping camera to prevent connection flapping
- **Autoreleasepool**: Memory management for high-frequency frame processing

## Dependencies

### External Requirements
- **NDI SDK**: Must be installed at `/Library/NDI SDK for Apple/` (required runtime dependency)
- **macOS 13+**: Minimum platform requirement
- **Camera permissions**: App requests AVFoundation camera access

### Framework Dependencies (linked in Package.swift)
- AVFoundation: Camera capture and media handling
- CoreMedia: Video frame processing
- CoreVideo: Pixel buffer manipulation
- Foundation: Core Swift functionality

## Key Implementation Details

### Frame Rate Handling
The camera frame rate selection uses precision matching to find the closest supported rate from available ranges, accounting for floating-point precision issues in AVFoundation.

### Memory Management
- Uses autoreleasepool in high-frequency frame processing
- Separate dispatch queues prevent main thread blocking
- Proper cleanup in deinit methods

### NDI Integration
- Dynamic library loading from standard SDK path
- C FFI through NDITypes.swift for native NDI SDK calls
- Connection count polling for subscriber detection

### Error Recovery
- Automatic camera restart on capture errors
- Graceful degradation when exact frame rates unavailable
- Proper signal handling for clean shutdown

## Development Notes

- The project has no Swift package dependencies - only system frameworks
- NDI SDK provides dynamic libraries only (no static linking possible)
- Camera format negotiation prefers YUV for efficiency but falls back to BGRA
- All major components are designed for independent testing via dependency injection