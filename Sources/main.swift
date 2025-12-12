import Foundation
import AVFoundation
import CoreMedia

class NDIWebcam {
    private let camera: CameraCapture
    private let ndiSender: NDISender
    private let subscriberMonitor: SubscriberMonitor
    private let logger = Logger.shared
    
    private var frameCount: UInt64 = 0
    private var startTime = Date()
    private var lastFPSReport = Date()
    private var statusTimer: Timer?
    private var currentFPS: Double = 0.0
    private let encodingMode: NDIEncodingMode
    private let forceCameraMode: Bool
    
    init(sourceName: String, resolution: AVCaptureSession.Preset, frameRate: Double, verbose: Bool, encodingMode: NDIEncodingMode = .uncompressed, forceCamera: Bool = false, camera: CameraCapture? = nil) {
        self.encodingMode = encodingMode
        self.forceCameraMode = forceCamera
        
        // Use provided camera or create a new one
        self.camera = camera ?? CameraCapture()
        
        // Configure logger
        logger.logLevel = verbose ? .debug : .info
        
        // Create NDI sender first
        ndiSender = NDISender(sourceName: sourceName, encodingMode: encodingMode)
        
        // Create subscriber monitor
        subscriberMonitor = SubscriberMonitor(ndiSender: ndiSender)
        
        // Configure camera after all properties are initialized
        self.camera.resolution = resolution
        self.camera.frameRate = frameRate
        self.camera.delegate = self
        
        // Set frame rate for HX3 encoding
        ndiSender.setFrameRate(frameRate)
        
        // Set subscriber monitor delegate
        subscriberMonitor.delegate = self
    }
    
    func run() {
        logger.info("NDI Camera Streamer Starting...")
        
        // Request camera access
        camera.requestCameraAccess { [weak self] granted in
            guard let self = self else { return }
            
            if !granted {
                self.logger.error("Camera access denied. Please grant permission in System Preferences.")
                exit(1)
            }
            
            self.startStreaming()
        }
        
        // Setup signal handlers for clean shutdown
        setupSignalHandlers()
        
        // Run the main loop
        RunLoop.main.run()
    }
    
    private func startStreaming() {
        // Start NDI sender
        guard ndiSender.start() else {
            logger.error("Failed to start NDI sender")
            exit(1)
        }
        
        if forceCameraMode {
            logger.info("🔧 Force camera mode enabled - starting camera immediately")
            camera.startCapture()
            
            // Reset frame count when starting
            frameCount = 0
            lastFPSReport = Date()
        } else {
            // Start monitoring for subscribers
            subscriberMonitor.startMonitoring()
            logger.info("Waiting for subscribers...")
        }
        
        logger.info("NDI stream available as: \(ndiSender.sourceName)")
        
        // Start dynamic status line (updates every second)
        startStatusLine()
    }
    
    private func startStatusLine() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusLine()
        }
    }
    
    private func updateStatusLine() {
        // Calculate FPS
        let elapsed = Date().timeIntervalSince(lastFPSReport)
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastFPSReport = Date()
        }
        
        // Get current status
        let uptime = Date().timeIntervalSince(startTime)
        let connections = ndiSender.getConnectionCount()
        
        // Format uptime
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60
        let uptimeStr = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        // Create status line
        let cameraStatus: String
        if forceCameraMode {
            cameraStatus = "FORCED"
        } else {
            cameraStatus = connections > 0 ? "ACTIVE" : "WAITING"
        }
        
        let encodingStr: String
        switch encodingMode {
        case .uncompressed:
            encodingStr = "RAW"
        case .hx3:
            encodingStr = "HX3"
        case .hevc:
            encodingStr = "HEVC"
        }
        let fpsStr = (connections > 0 || forceCameraMode) ? String(format: "%.1f", currentFPS) : "0.0"
        
        // Clear line and print status
        print("\r\u{1B}[K", terminator: "")  // Clear current line
        print("📹 \(cameraStatus) | 🌐 \(connections) subscriber\(connections == 1 ? "" : "s") | ⚡ \(fpsStr) fps | 🎬 \(encodingStr) | ⏱️  \(uptimeStr)", terminator: "")
        fflush(stdout)
    }
    
    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            print("\n\nShutting down...")
            exit(0)
        }
        
        signal(SIGTERM) { _ in
            print("\n\nShutting down...")
            exit(0)
        }
    }
    
    deinit {
        statusTimer?.invalidate()
        camera.stopCapture()
        subscriberMonitor.stopMonitoring()
        ndiSender.stop()
    }
}

// MARK: - CameraCaptureDelegate

extension NDIWebcam: CameraCaptureDelegate {
    func cameraCapture(_ capture: CameraCapture, didOutput sampleBuffer: CMSampleBuffer) {
        // Send frame via NDI
        ndiSender.sendFrame(sampleBuffer)
        frameCount += 1
        
        // Log first few frames to verify capture is working
        if frameCount <= 5 {
            logger.debug("Camera frame \(frameCount) captured and sent to NDI")
        }
    }
    
    func cameraCapture(_ capture: CameraCapture, didEncounterError error: Error) {
        logger.error("Camera error: \(error)")
        
        // Attempt to restart camera after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logger.info("Attempting to restart camera...")
            self?.camera.startCapture()
        }
    }
}

// MARK: - SubscriberMonitorDelegate

extension NDIWebcam: SubscriberMonitorDelegate {
    func subscriberMonitor(_ monitor: SubscriberMonitor, subscribersChanged count: Int32) {
        logger.debug("Subscriber count update: \(count)")
    }
    
    func subscriberMonitorShouldStartCamera(_ monitor: SubscriberMonitor) {
        logger.info("🎥 Starting camera capture due to subscriber connection")
        camera.startCapture()
        
        // Reset frame count when starting
        frameCount = 0
        lastFPSReport = Date()
    }
    
    func subscriberMonitorShouldStopCamera(_ monitor: SubscriberMonitor) {
        logger.info("🛑 Stopping camera capture - no subscribers")
        camera.stopCapture()
        
        // Reset FPS when stopping
        currentFPS = 0.0
    }
}

// MARK: - Command Line Interface

struct CommandLineArgs {
    var sourceName = "Swift NDI Camera"
    var resolution = AVCaptureSession.Preset.hd1920x1080
    var frameRate = 30.0
    var verbose = false
    var encodingMode = NDIEncodingMode.uncompressed
    var forceCamera = false
    var listCameras = false
    var cameraIndex: Int?
    var cameraName: String?
    
    static func parse() -> CommandLineArgs {
        var args = CommandLineArgs()
        
        let arguments = CommandLine.arguments
        var i = 1
        
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case "--name":
                if i + 1 < arguments.count {
                    args.sourceName = arguments[i + 1]
                    i += 2
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--resolution":
                if i + 1 < arguments.count {
                    let res = arguments[i + 1].lowercased()
                    switch res {
                    case "720p":
                        args.resolution = .hd1280x720
                    case "1080p":
                        args.resolution = .hd1920x1080
                    case "4k":
                        args.resolution = .hd4K3840x2160
                    default:
                        print("Invalid resolution: \(res)")
                        printHelp()
                        exit(1)
                    }
                    i += 2
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--fps":
                if i + 1 < arguments.count {
                    if let fps = Double(arguments[i + 1]) {
                        args.frameRate = fps
                        i += 2
                    } else {
                        print("Invalid frame rate")
                        printHelp()
                        exit(1)
                    }
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--verbose", "-v":
                args.verbose = true
                i += 1
                
            case "--force-camera":
                args.forceCamera = true
                i += 1
                
            case "--encoding":
                if i + 1 < arguments.count {
                    let encoding = arguments[i + 1].lowercased()
                    switch encoding {
                    case "uncompressed", "raw":
                        args.encodingMode = .uncompressed
                    case "hx3", "h264":
                        args.encodingMode = .hx3
                    case "hevc", "h265":
                        args.encodingMode = .hevc
                    default:
                        print("Invalid encoding mode: \(encoding)")
                        printHelp()
                        exit(1)
                    }
                    i += 2
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--list-cameras":
                args.listCameras = true
                i += 1
                
            case "--camera-index":
                if i + 1 < arguments.count {
                    if let index = Int(arguments[i + 1]) {
                        args.cameraIndex = index
                        i += 2
                    } else {
                        print("Invalid camera index: \(arguments[i + 1])")
                        printHelp()
                        exit(1)
                    }
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--camera-name":
                if i + 1 < arguments.count {
                    args.cameraName = arguments[i + 1]
                    i += 2
                } else {
                    printHelp()
                    exit(1)
                }
                
            case "--help", "-h":
                printHelp()
                exit(0)
                
            default:
                print("Unknown argument: \(arg)")
                printHelp()
                exit(1)
            }
        }
        
        return args
    }
    
    static func printHelp() {
        print("""
        ndi-webcam
        
        Usage: ndi-webcam [options]
        
        Options:
          --name <string>      NDI source name (default: "Swift NDI Camera")
          --resolution <res>   Resolution: 720p, 1080p (default), 4k
          --fps <number>       Frame rate (default: 30)
          --encoding <mode>    Encoding: uncompressed (default), hx3, hevc
          --list-cameras       List available cameras and exit
          --camera-index <n>   Select camera by index (use --list-cameras first)
          --camera-name <name> Select camera by name (partial match)
          --verbose, -v        Enable verbose logging
          --force-camera       Start camera immediately (bypass subscriber detection)
          --help, -h           Show this help message
        
        Encoding Modes:
          uncompressed (raw)   High quality, high bandwidth (default)
          hx3 (h264)          H.264 compressed, optimized for latency and bandwidth
          hevc (h265)         H.265 compressed, better compression than H.264
        
        Examples:
          ndi-webcam --name "Mac Camera" --resolution 1080p --fps 30
          ndi-webcam --encoding hx3 --name "Low Bandwidth Camera"
          ndi-webcam --encoding hevc --name "HEVC Camera"
          ndi-webcam --encoding uncompressed --resolution 4k --fps 60
          ndi-webcam --force-camera --verbose  # Debug camera issues
        
        Note: NDI SDK must be installed from ndi.tv
        """)
    }
}

// MARK: - Main Entry Point

let args = CommandLineArgs.parse()

// Handle camera listing
if args.listCameras {
    CameraCapture.printAvailableCameras()
    exit(0)
}

// Create camera capture instance
let camera = CameraCapture()

// Handle camera selection
if let cameraIndex = args.cameraIndex {
    if let device = CameraCapture.getCameraByIndex(cameraIndex) {
        camera.setCamera(device: device)
        print("Selected camera by index: \(device.localizedName)")
    } else {
        print("Error: Camera index \(cameraIndex) not found")
        print("Use --list-cameras to see available cameras")
        exit(1)
    }
} else if let cameraName = args.cameraName {
    if let device = CameraCapture.getCameraByName(cameraName) {
        camera.setCamera(device: device)
        print("Selected camera by name: \(device.localizedName)")
    } else {
        print("Error: No camera found matching '\(cameraName)'")
        print("Use --list-cameras to see available cameras")
        exit(1)
    }
}

print("""
╔═══════════════════════════════════╗
║       ndi-webcam v1.0             ║
╚═══════════════════════════════════╝

Source Name: \(args.sourceName)
Resolution: \(args.resolution.rawValue)
Frame Rate: \(args.frameRate) fps
Encoding: \(args.encodingMode == .hx3 ? "NDI|HX3 (H.264)" : args.encodingMode == .hevc ? "H.265/HEVC" : "Uncompressed")

Starting...
""")

let streamer = NDIWebcam(
    sourceName: args.sourceName,
    resolution: args.resolution,
    frameRate: args.frameRate,
    verbose: args.verbose,
    encodingMode: args.encodingMode,
    forceCamera: args.forceCamera,
    camera: camera
)

streamer.run()