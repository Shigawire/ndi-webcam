import Foundation
import AVFoundation
import CoreMedia

class NDIWebcam {
    private let camera = CameraCapture()
    private let ndiSender: NDISender
    private let subscriberMonitor: SubscriberMonitor
    private let logger = Logger.shared
    
    private var frameCount: UInt64 = 0
    private var startTime = Date()
    private var lastFPSReport = Date()
    
    init(sourceName: String, resolution: AVCaptureSession.Preset, frameRate: Double, verbose: Bool, encodingMode: NDIEncodingMode = .uncompressed) {
        // Configure logger
        logger.logLevel = verbose ? .debug : .info
        
        // Create NDI sender first
        ndiSender = NDISender(sourceName: sourceName, encodingMode: encodingMode)
        
        // Create subscriber monitor
        subscriberMonitor = SubscriberMonitor(ndiSender: ndiSender)
        
        // Configure camera after all properties are initialized
        camera.resolution = resolution
        camera.frameRate = frameRate
        camera.delegate = self
        
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
        
        // Start monitoring for subscribers
        subscriberMonitor.startMonitoring()
        
        logger.info("NDI stream available as: \(ndiSender.sourceName)")
        logger.info("Waiting for subscribers...")
        
        // Print status periodically
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.printStatus()
        }
    }
    
    private func printStatus() {
        let uptime = Date().timeIntervalSince(startTime)
        let connections = ndiSender.getConnectionCount()
        
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60
        
        let uptimeStr = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        
        if frameCount > 0 {
            let elapsed = Date().timeIntervalSince(lastFPSReport)
            let fps = Double(frameCount) / elapsed
            logger.info("Status - Uptime: \(uptimeStr), Subscribers: \(connections), FPS: \(String(format: "%.1f", fps))")
            frameCount = 0
            lastFPSReport = Date()
        } else {
            logger.info("Status - Uptime: \(uptimeStr), Subscribers: \(connections), Camera: inactive")
        }
    }
    
    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            print("\nShutting down...")
            exit(0)
        }
        
        signal(SIGTERM) { _ in
            print("\nShutting down...")
            exit(0)
        }
    }
    
    deinit {
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
        // Status is logged by the monitor
    }
    
    func subscriberMonitorShouldStartCamera(_ monitor: SubscriberMonitor) {
        logger.info("Starting camera capture")
        camera.startCapture()
    }
    
    func subscriberMonitorShouldStopCamera(_ monitor: SubscriberMonitor) {
        logger.info("Stopping camera capture")
        camera.stopCapture()
    }
}

// MARK: - Command Line Interface

struct CommandLineArgs {
    var sourceName = "Swift NDI Camera"
    var resolution = AVCaptureSession.Preset.hd1920x1080
    var frameRate = 30.0
    var verbose = false
    var encodingMode = NDIEncodingMode.uncompressed
    
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
                
            case "--encoding":
                if i + 1 < arguments.count {
                    let encoding = arguments[i + 1].lowercased()
                    switch encoding {
                    case "uncompressed", "raw":
                        args.encodingMode = .uncompressed
                    case "hx3", "h264":
                        args.encodingMode = .hx3
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
          --encoding <mode>    Encoding: uncompressed (default), hx3
          --verbose, -v        Enable verbose logging
          --help, -h           Show this help message
        
        Encoding Modes:
          uncompressed (raw)   High quality, high bandwidth (default)
          hx3 (h264)          H.264 compressed, optimized for latency and bandwidth
        
        Examples:
          ndi-webcam --name "Mac Camera" --resolution 1080p --fps 30
          ndi-webcam --encoding hx3 --name "Low Bandwidth Camera"
          ndi-webcam --encoding uncompressed --resolution 4k --fps 60
        
        Note: NDI SDK must be installed from ndi.tv
        """)
    }
}

// MARK: - Main Entry Point

let args = CommandLineArgs.parse()

print("""
╔═══════════════════════════════════╗
║       ndi-webcam v1.0             ║
╚═══════════════════════════════════╝

Source Name: \(args.sourceName)
Resolution: \(args.resolution.rawValue)
Frame Rate: \(args.frameRate) fps
Encoding: \(args.encodingMode == .hx3 ? "NDI|HX3 (H.264)" : "Uncompressed")

Starting...
""")

let streamer = NDIWebcam(
    sourceName: args.sourceName,
    resolution: args.resolution,
    frameRate: args.frameRate,
    verbose: args.verbose,
    encodingMode: args.encodingMode
)

streamer.run()