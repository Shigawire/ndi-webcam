import Foundation
import CoreMedia

class NDISender {
    private var sender: OpaquePointer?
    private let ndiLib = NDILibrary.shared
    private let logger = Logger.shared
    private let frameConverter = FrameConverter()
    private let sendQueue = DispatchQueue(label: "ndi.send.queue")
    
    var sourceName: String
    
    init(sourceName: String = "Swift NDI Camera") {
        self.sourceName = sourceName
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
        
        logger.info("NDI sender created: \(sourceName)")
        return true
    }
    
    func stop() {
        if let sender = sender {
            ndiLib.destroySender(sender)
            self.sender = nil
            logger.info("NDI sender destroyed")
        }
    }
    
    func sendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let sender = sender else { return }
        
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
                    height: frameData.height
                )
                ndiFrame.p_data = frameData.data
                ndiFrame.line_stride_in_bytes = frameData.stride
                
                // Send frame
                self.ndiLib.sendVideo(sender, frame: &ndiFrame)
            }
        }
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