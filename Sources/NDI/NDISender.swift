import Foundation
import CoreMedia

enum NDIEncodingMode {
    case uncompressed  // Original BGRA encoding
    case hx3          // H.264 encoding for bandwidth efficiency
    case hevc         // H.265/HEVC encoding for better compression
}

class NDISender {
    private var sender: OpaquePointer?
    private let ndiLib = NDILibrary.shared
    private let logger = Logger.shared
    private let frameConverter = FrameConverter()
    private let sendQueue = DispatchQueue(label: "ndi.send.queue")
    private var framesSent = 0
    private var h264FrameCount = 0
    private var h265FrameCount = 0
    
    // Compressed video support
    private var h264Encoder: H264Encoder?
    private var h265Encoder: H265Encoder?
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
        
        // Check compressed encoding support if needed
        if encodingMode == .hx3 {
            if ndiLib.supportsHX3 {
                logger.info("NDI HX3 encoding enabled")
            } else {
                logger.warning("NDI HX3 not supported, falling back to uncompressed")
                encodingMode = .uncompressed
            }
        } else if encodingMode == .hevc {
            // For now, assume HEVC is supported if we can create the encoder
            logger.info("NDI H.265/HEVC encoding enabled")
        }
        
        logger.info("NDI sender created: \(sourceName) (mode: \(encodingMode))")
        return true
    }
    
    func stop() {
        h264Encoder?.stop()
        h264Encoder = nil
        h265Encoder?.stop()
        h265Encoder = nil
        
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
        case .hevc:
            sendHEVCFrame(sampleBuffer, sender: sender)
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
                
                // Debug logging for first few frames
                self.framesSent += 1
                if self.framesSent <= 3 {
                    self.logger.debug("Sending uncompressed NDI frame \(self.framesSent): \(frameData.width)x\(frameData.height)")
                }
                
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
    
    private func sendHEVCFrame(_ sampleBuffer: CMSampleBuffer, sender: OpaquePointer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.warning("Failed to get image buffer from H.265 sample")
            return
        }
        
        // Get frame dimensions
        let width = Int32(CVPixelBufferGetWidth(imageBuffer))
        let height = Int32(CVPixelBufferGetHeight(imageBuffer))
        
        // Initialize H.265 encoder if needed
        if h265Encoder == nil || currentResolution.width != width || currentResolution.height != height {
            setupH265Encoder(width: width, height: height, sender: sender)
        }
        
        // Let encoder handle keyframe timing
        let forceKeyframe = false
        
        // Encode frame
        h265Encoder?.encode(imageBuffer, forceKeyframe: forceKeyframe)
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
    
    private func setupH265Encoder(width: Int32, height: Int32, sender: OpaquePointer) {
        // Stop existing encoder
        h265Encoder?.stop()
        
        // Calculate appropriate bitrate for H.265 encoding (more efficient than H.264)
        let bitRate = calculateDefaultBitRate(width: width, height: height, frameRate: currentFrameRate) * 3 / 4 // 25% less bitrate for H.265
        
        // Create new encoder
        h265Encoder = H265Encoder(width: width, height: height, frameRate: currentFrameRate, bitRate: bitRate)
        h265Encoder?.delegate = self
        
        if h265Encoder?.start() == true {
            currentResolution = (width, height)
            logger.info("H.265 encoder initialized: \(width)x\(height) @ \(Int(bitRate)) bps")
        } else {
            logger.error("Failed to initialize H.265 encoder")
            h265Encoder = nil
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
        
        // Debug log H.264 output
        h264FrameCount += 1
        if h264FrameCount <= 5 {
            logger.debug("🎥 H.264 encoder output frame \(h264FrameCount), keyframe: \(isKeyframe)")
        }
        
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
                
                // Create proper frame rate fraction for NDI
                let frameRateNum: Int32
                let frameRateDen: Int32
                if abs(self.currentFrameRate - 29.97) < 0.1 {
                    frameRateNum = 30000
                    frameRateDen = 1001
                } else {
                    frameRateNum = Int32(self.currentFrameRate)
                    frameRateDen = 1
                }
                
                // Create NDI frame for H.264 compressed data
                var ndiFrame = NDIlib_video_frame_v2_t(
                    width: self.currentResolution.width,
                    height: self.currentResolution.height,
                    frameRateN: frameRateNum,
                    frameRateD: frameRateDen,
                    fourCC: NDI_FourCC_H264
                )
                
                // Set H.264 compressed data
                ndiFrame.p_data = UnsafeMutableRawPointer(data)
                ndiFrame.data_size_in_bytes = Int32(length)  // Use data_size for compressed format
                
                // Set proper timestamp - use timescale-aware conversion
                if presentationTime.timescale != 0 {
                    // Convert to NDI timestamp (nanoseconds since epoch)
                    let timeInSeconds = Double(presentationTime.value) / Double(presentationTime.timescale)
                    ndiFrame.timestamp = Int64(timeInSeconds * 1_000_000_000) // Convert to nanoseconds
                } else {
                    ndiFrame.timestamp = 0 // Let NDI handle timing
                }
                
                // Debug log NDI send for H.264 with enhanced info
                if self.h264FrameCount <= 5 {
                    self.logger.debug("📡 Sending H.264 NDI frame \(self.h264FrameCount): \(length) bytes, \(frameRateNum)/\(frameRateDen) fps, ts: \(ndiFrame.timestamp)")
                }
                
                // Send compressed frame
                self.ndiLib.sendVideoAsync(sender, frame: &ndiFrame)
            }
        }
    }
    
    func h264Encoder(_ encoder: H264Encoder, didEncounterError error: Error) {
        logger.error("❌ H.264 encoder error: \(error)")
        logger.error("⚠️ This will cause video to appear stuck or frozen")
        
        // Try to recover by reinitializing the encoder
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let sender = self.sender else { return }
            self.setupH264Encoder(width: self.currentResolution.width, height: self.currentResolution.height, sender: sender)
        }
    }
}

// MARK: - H265EncoderDelegate

extension NDISender: H265EncoderDelegate {
    func h265Encoder(_ encoder: H265Encoder, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, isKeyframe: Bool) {
        guard let sender = sender else { return }
        
        // Debug log H.265 output
        h265FrameCount += 1
        if h265FrameCount <= 5 {
            logger.debug("🎥 H.265 encoder output frame \(h265FrameCount), keyframe: \(isKeyframe)")
        }
        
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            
            autoreleasepool {
                // Extract H.265 data from sample buffer
                guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    self.logger.warning("Failed to get data buffer from H.265 sample")
                    return
                }
                
                var length: Int = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
                
                guard status == noErr, let data = dataPointer, length > 0 else {
                    self.logger.warning("Failed to get H.265 data pointer")
                    return
                }
                
                // Get timing information
                let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // Create proper frame rate fraction for NDI
                let frameRateNum: Int32
                let frameRateDen: Int32
                if abs(self.currentFrameRate - 29.97) < 0.1 {
                    frameRateNum = 30000
                    frameRateDen = 1001
                } else {
                    frameRateNum = Int32(self.currentFrameRate)
                    frameRateDen = 1
                }
                
                // Create NDI frame for H.265 compressed data
                var ndiFrame = NDIlib_video_frame_v2_t(
                    width: self.currentResolution.width,
                    height: self.currentResolution.height,
                    frameRateN: frameRateNum,
                    frameRateD: frameRateDen,
                    fourCC: NDI_FourCC_HEVC  // Use HEVC FourCC
                )
                
                // Set H.265 compressed data
                ndiFrame.p_data = UnsafeMutableRawPointer(data)
                ndiFrame.data_size_in_bytes = Int32(length)
                
                // Set proper timestamp
                if presentationTime.timescale != 0 {
                    let timeInSeconds = Double(presentationTime.value) / Double(presentationTime.timescale)
                    ndiFrame.timestamp = Int64(timeInSeconds * 1_000_000_000)
                } else {
                    ndiFrame.timestamp = 0
                }
                
                // Debug log NDI send for H.265
                if self.h265FrameCount <= 5 {
                    self.logger.debug("📡 Sending H.265 NDI frame \(self.h265FrameCount): \(length) bytes, \(frameRateNum)/\(frameRateDen) fps, ts: \(ndiFrame.timestamp)")
                }
                
                // Send compressed frame
                self.ndiLib.sendVideoAsync(sender, frame: &ndiFrame)
            }
        }
    }
    
    func h265Encoder(_ encoder: H265Encoder, didEncounterError error: Error) {
        logger.error("❌ H.265 encoder error: \(error)")
        logger.error("⚠️ This will cause video to appear stuck or frozen")
        
        // Try to recover by reinitializing the encoder
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, let sender = self.sender else { return }
            self.setupH265Encoder(width: self.currentResolution.width, height: self.currentResolution.height, sender: sender)
        }
    }
}