import AVFoundation
import CoreMedia

protocol CameraCaptureDelegate: AnyObject {
    func cameraCapture(_ capture: CameraCapture, didOutput sampleBuffer: CMSampleBuffer)
    func cameraCapture(_ capture: CameraCapture, didEncounterError error: Error)
}

class CameraCapture: NSObject {
    weak var delegate: CameraCaptureDelegate?
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let outputQueue = DispatchQueue(label: "camera.output.queue")
    
    private var isRunning = false
    private let logger = Logger.shared
    
    var resolution: AVCaptureSession.Preset = .hd1920x1080
    var frameRate: Double = 30.0
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            defer { self.captureSession.commitConfiguration() }
            
            // Set session preset
            if self.captureSession.canSetSessionPreset(self.resolution) {
                self.captureSession.sessionPreset = self.resolution
            }
            
            // Get default video device
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                self.logger.error("No video device available")
                return
            }
            
            // Create input
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                } else {
                    self.logger.error("Cannot add video input to session")
                    return
                }
            } catch {
                self.logger.error("Error creating video input: \(error)")
                return
            }
            
            // Configure output
            self.videoOutput.setSampleBufferDelegate(self, queue: self.outputQueue)
            
            // Prefer YUV format for efficiency
            let pixelFormats = [
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelFormatType_32BGRA
            ]
            
            for format in pixelFormats {
                if self.videoOutput.availableVideoPixelFormatTypes.contains(format) {
                    self.videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: format
                    ]
                    break
                }
            }
            
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            } else {
                self.logger.error("Cannot add video output to session")
                return
            }
            
            // Configure frame rate
            self.configureFrameRate(videoDevice: videoDevice)
            
            self.logger.info("Camera session configured successfully")
        }
    }
    
    private func configureFrameRate(videoDevice: AVCaptureDevice) {
        do {
            try videoDevice.lockForConfiguration()
            defer { videoDevice.unlockForConfiguration() }
            
            // Get supported frame rate ranges
            let format = videoDevice.activeFormat
            let ranges = format.videoSupportedFrameRateRanges
            
            guard !ranges.isEmpty else {
                logger.warning("No supported frame rate ranges found")
                return
            }
            
            // Log supported ranges for debugging
            let rangeDescriptions = ranges.map { range in
                "\(range.minFrameRate)-\(range.maxFrameRate) fps"
            }.joined(separator: ", ")
            logger.debug("Supported frame rate ranges: \(rangeDescriptions)")
            
            // Find the best matching frame rate
            var targetFrameRate = frameRate
            
            // Find the closest supported frame rate (don't assume exact match due to floating point precision)
            var bestRange: AVFrameRateRange?
            var useMaxRate = true
            var smallestDifference: Double = Double.greatestFiniteMagnitude
            
            // Find the closest frame rate from all available ranges
            for range in ranges {
                // Check if we can use the max rate of this range
                let maxDifference = abs(range.maxFrameRate - frameRate)
                if maxDifference < smallestDifference {
                    smallestDifference = maxDifference
                    bestRange = range
                    useMaxRate = true
                    targetFrameRate = range.maxFrameRate
                }
                
                // Also check the min rate of this range (though most are single-rate ranges)
                let minDifference = abs(range.minFrameRate - frameRate)
                if minDifference < smallestDifference {
                    smallestDifference = minDifference
                    bestRange = range
                    useMaxRate = false
                    targetFrameRate = range.minFrameRate
                }
            }
            
            if let range = bestRange {
                
                // Use the exact duration from the range to avoid floating point precision issues
                let targetDuration = useMaxRate ? range.maxFrameDuration : range.minFrameDuration
                videoDevice.activeVideoMinFrameDuration = targetDuration
                videoDevice.activeVideoMaxFrameDuration = targetDuration
                
                let difference = abs(targetFrameRate - frameRate)
                if difference > 0.1 { // Only warn if significantly different
                    logger.warning("Requested \(frameRate) fps not supported. Using closest match: \(targetFrameRate) fps")
                } else {
                    logger.info("Frame rate set to \(targetFrameRate) fps")
                }
            } else {
                logger.error("No compatible frame rate found. Using device default.")
            }
            
        } catch {
            logger.error("Error configuring frame rate: \(error)")
        }
    }
    
    func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isRunning {
                self.captureSession.startRunning()
                self.isRunning = true
                self.logger.info("Camera capture started")
            }
        }
    }
    
    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.isRunning {
                self.captureSession.stopRunning()
                self.isRunning = false
                self.logger.info("Camera capture stopped")
            }
        }
    }
    
    func requestCameraAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            logger.error("Camera access denied. Please enable in System Preferences > Security & Privacy > Camera")
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, 
                      didOutput sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        delegate?.cameraCapture(self, didOutput: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didDrop sampleBuffer: CMSampleBuffer, 
                      from connection: AVCaptureConnection) {
        logger.warning("Dropped frame")
    }
}