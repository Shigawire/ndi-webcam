import Foundation
import CoreMedia

enum NDIEncodingMode {
    case uncompressed  // Original BGRA encoding
    case hx3          // H.264 encoding for bandwidth efficiency
}

class NDISender {
    private var sender: OpaquePointer?
    private let ndiLib = NDILibrary.shared
    private let logger = Logger.shared
    private let frameConverter = FrameConverter()
    private let sendQueue = DispatchQueue(label: "ndi.send.queue")
    
    // HX3 support
    private var h264Encoder: H264Encoder?
    private var encodingMode: NDIEncodingMode = .uncompressed
    private var currentResolution: (width: Int32, height: Int32) = (0, 0)
    private var currentFrameRate: Double = 30.0
    
    var sourceName: String
    
    init(sourceName: String = "Swift NDI Camera", encodingMode: NDIEncodingMode = .uncompressed) {
        self.sourceName = sourceName
        self.encodingMode = encodingMode
    }
    
    func start() -> Bool {
        guard ndiLib.load() else {
            logger.error("Failed to load NDI library")
            return false
        }
        
        sender = ndiLib.createSender(name: sourceName)
        
        guard sender != nil else {
            logger.error("Failed to create NDI sender")
            return false
        }
        
        // Check HX3 support if needed
        if encodingMode == .hx3 {
            if ndiLib.supportsHX3 {
                logger.info("NDI HX3 encoding enabled")
            } else {
                logger.warning("NDI HX3 not supported, falling back to uncompressed")
                encodingMode = .uncompressed
            }
        }
        
        logger.info("NDI sender created: \(sourceName) (mode: \(encodingMode))")
        return true
    }
    
    func stop() {
        h264Encoder?.stop()
        h264Encoder = nil
        
        if let sender = sender {
            ndiLib.destroySender(sender)
            self.sender = nil
            logger.info("NDI sender destroyed")
        }
    }
    
    func sendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let sender = sender else { return }
        
        switch encodingMode {
        case .uncompressed:
            sendUncompressedFrame(sampleBuffer, sender: sender)
        case .hx3:
            sendHX3Frame(sampleBuffer, sender: sender)
        }
    }
    
    private func sendUncompressedFrame(_ sampleBuffer: CMSampleBuffer, sender: OpaquePointer) {
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                // Convert frame to BGRA
                guard let frameData = self.frameConverter.convertToBGRA(from: sampleBuffer) else {
                    self.logger.warning("Failed to convert frame")
                    return
                }
                
                // Create NDI frame
                var ndiFrame = NDIlib_video_frame_v2_t(
                    width: frameData.width,
                    height: frameData.height,
                    fourCC: NDI_FourCC_BGRA
                )
                ndiFrame.p_data = frameData.data
                ndiFrame.line_stride_in_bytes = frameData.stride
                
                // Send frame
                self.ndiLib.sendVideo(sender, frame: &ndiFrame)
            }
        }
    }
    
    private func sendHX3Frame(_ sampleBuffer: CMSampleBuffer, sender: OpaquePointer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("Failed to get image buffer from sample")
            return
        }
        
        // Get frame dimensions
        let width = Int32(CVPixelBufferGetWidth(imageBuffer))
        let height = Int32(CVPixelBufferGetHeight(imageBuffer))
        
        // Initialize H.264 encoder if needed
        if h264Encoder == nil || currentResolution.width != width || currentResolution.height != height {
            setupH264Encoder(width: width, height: height, sender: sender)
        }
        
        // For now, we'll request keyframes periodically (every 2 seconds)
        // This matches NDI's recommended I-frame interval
        let forceKeyframe = false // We'll let the encoder handle keyframe timing
        
        // Encode frame
        h264Encoder?.encode(imageBuffer, forceKeyframe: forceKeyframe)
    }
    
    private func setupH264Encoder(width: Int32, height: Int32, sender: OpaquePointer) {
        // Stop existing encoder
        h264Encoder?.stop()
        
        // Calculate appropriate bitrate for H.264 encoding
        let bitRate = calculateDefaultBitRate(width: width, height: height, frameRate: currentFrameRate)
        
        // Create new encoder
        h264Encoder = H264Encoder(width: width, height: height, frameRate: currentFrameRate, bitRate: bitRate)
        h264Encoder?.delegate = self
        
        if h264Encoder?.start() == true {
            currentResolution = (width, height)
            logger.info("H.264 encoder initialized: \(width)x\(height) @ \(Int(bitRate)) bps")
        } else {
            logger.error("Failed to initialize H.264 encoder")
            h264Encoder = nil
        }
    }
    
    private func calculateDefaultBitRate(width: Int32, height: Int32, frameRate: Double) -> Int32 {
        // Conservative bitrate calculation for H.264
        // Roughly 0.1 bits per pixel per frame for good quality
        let pixelsPerFrame = Double(width * height)
        let bitsPerSecond = pixelsPerFrame * frameRate * 0.1
        return Int32(bitsPerSecond)
    }
    
    func setFrameRate(_ frameRate: Double) {
        self.currentFrameRate = frameRate
    }
    
    func getConnectionCount() -> Int32 {
        guard let sender = sender else { return 0 }
        return ndiLib.getConnectionCount(sender, timeout: 0)
    }
    
    func clearConnectionMetadata() {
        guard let sender = sender else { return }
        ndiLib.clearConnectionMetadata(sender)
    }
    
    deinit {
        stop()
    }
}

// MARK: - H264EncoderDelegate

extension NDISender: H264EncoderDelegate {
    func h264Encoder(_ encoder: H264Encoder, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, isKeyframe: Bool) {
        guard let sender = sender else { return }
        
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                // Extract H.264 data from sample buffer
                guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    self.logger.warning("Failed to get data buffer from H.264 sample")
                    return
                }
                
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                
                guard status == noErr, let data = dataPointer, length > 0 else {
                    self.logger.warning("Failed to get H.264 data pointer")
                    return
                }
                
                // Get timing information
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // Create NDI frame for H.264 compressed data
                var ndiFrame = NDIlib_video_frame_v2_t(
                    width: self.currentResolution.width,
                    height: self.currentResolution.height,
                    frameRateN: Int32(self.currentFrameRate),
                    frameRateD: 1,
                    fourCC: NDI_FourCC_H264
                )
                
                // Set H.264 compressed data
                ndiFrame.p_data = UnsafeMutableRawPointer(data)
                ndiFrame.data_size_in_bytes = Int32(length)  // Use data_size for compressed format
                ndiFrame.timestamp = presentationTime.value
                
                // Send compressed frame
                self.ndiLib.sendVideoAsync(sender, frame: &ndiFrame)
            }
        }
    }
    
    func h264Encoder(_ encoder: H264Encoder, didEncounterError error: Error) {
        logger.error("H.264 encoder error: \(error)")
        
        // Try to recover by reinitializing the encoder
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let sender = self.sender else { return }
            self.setupH264Encoder(width: self.currentResolution.width, height: self.currentResolution.height, sender: sender)
        }
    }
}