import Foundation
import VideoToolbox
import CoreMedia

protocol H265EncoderDelegate: AnyObject {
    func h265Encoder(_ encoder: H265Encoder, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, isKeyframe: Bool)
    func h265Encoder(_ encoder: H265Encoder, didEncounterError error: Error)
}

class H265Encoder {
    weak var delegate: H265EncoderDelegate?
    
    private var compressionSession: VTCompressionSession?
    private let logger = Logger.shared
    private var frameCount: Int64 = 0
    
    // Encoder configuration
    private let width: Int32
    private let height: Int32
    private let frameRate: Double
    private let bitRate: Int32
    
    // Callback queue
    private let callbackQueue = DispatchQueue(label: "h265.encoder.callback")
    
    init(width: Int32, height: Int32, frameRate: Double, bitRate: Int32) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitRate = bitRate
    }
    
    func start() -> Bool {
        guard compressionSession == nil else { return true }
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: h265CompressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            logger.error("Failed to create H.265 compression session: \(status)")
            return false
        }
        
        // Configure encoder settings for low latency
        configureEncoderForLowLatency(session)
        
        return true
    }
    
    private func configureEncoderForLowLatency(_ session: VTCompressionSession) {
        // Set bitrate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
        
        // Enable real-time encoding
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        
        // Set frame rate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate as CFNumber)
        
        // Use hardware acceleration if available
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, value: kCFBooleanTrue)
        
        // Low latency settings
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: Int(frameRate * 2) as CFNumber) // I-frame every 2 seconds
        
        // Quality settings optimized for NDI
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.7 as CFNumber)
        
        // Profile and level - use Main profile for compatibility
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        
        logger.info("H.265 encoder configured for low latency")
    }
    
    func encode(_ pixelBuffer: CVPixelBuffer, forceKeyframe: Bool = false) {
        guard let session = compressionSession else {
            logger.error("No compression session available")
            return
        }
        
        let presentationTime = CMTime(value: frameCount, timescale: CMTimeScale(frameRate))
        frameCount += 1
        
        var frameProperties: CFDictionary? = nil
        if forceKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            logger.error("Failed to encode H.265 frame: \(status)")
        }
    }
    
    func stop() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - Compression Callback

private let h265CompressionOutputCallback: VTCompressionOutputCallback = { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
    guard status == noErr,
          let sampleBuffer = sampleBuffer,
          let encoder = outputCallbackRefCon else {
        return
    }
    
    let encoderInstance = Unmanaged<H265Encoder>.fromOpaque(encoder).takeUnretainedValue()
    
    // Check if this is a keyframe by examining sample buffer attachments
    var isKeyframe = false
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
       CFArrayGetCount(attachments) > 0 {
        let attachment = CFArrayGetValueAtIndex(attachments, 0)
        let attachmentDict = Unmanaged<CFDictionary>.fromOpaque(attachment!).takeUnretainedValue()
        isKeyframe = CFDictionaryGetValue(attachmentDict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) == nil
    }
    
    encoderInstance.delegate?.h265Encoder(encoderInstance, didOutputSampleBuffer: sampleBuffer, isKeyframe: isKeyframe)
}