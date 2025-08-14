import CoreMedia
import CoreVideo
import Accelerate

class FrameConverter {
    private let logger = Logger.shared
    private var rgbaBuffer: UnsafeMutableRawPointer?
    private var rgbaBufferSize: Int = 0
    
    deinit {
        if let buffer = rgbaBuffer {
            buffer.deallocate()
        }
    }
    
    func convertToBGRA(from sampleBuffer: CMSampleBuffer) -> (data: UnsafeMutableRawPointer, width: Int32, height: Int32, stride: Int32)? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            logger.error("Failed to get pixel buffer from sample buffer")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Calculate BGRA buffer size
        let bytesPerPixel = 4
        let stride = width * bytesPerPixel
        let bufferSize = stride * height
        
        // Allocate or resize BGRA buffer if needed
        if rgbaBufferSize < bufferSize {
            rgbaBuffer?.deallocate()
            rgbaBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
            rgbaBufferSize = bufferSize
        }
        
        guard let destBuffer = rgbaBuffer else {
            logger.error("Failed to allocate BGRA buffer")
            return nil
        }
        
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            // Already in BGRA format, just copy
            if let sourceAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
                
                if sourceStride == stride {
                    // Can do a single memcpy
                    memcpy(destBuffer, sourceAddress, bufferSize)
                } else {
                    // Need to copy row by row due to different strides
                    for row in 0..<height {
                        let sourceRow = sourceAddress.advanced(by: row * sourceStride)
                        let destRow = destBuffer.advanced(by: row * stride)
                        memcpy(destRow, sourceRow, stride)
                    }
                }
            }
            
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // Convert YUV to BGRA
            convertYUVToBGRA(pixelBuffer: pixelBuffer, 
                           destBuffer: destBuffer, 
                           width: width, 
                           height: height,
                           isFullRange: pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            
        default:
            logger.error("Unsupported pixel format: \(pixelFormat)")
            return nil
        }
        
        return (data: destBuffer, width: Int32(width), height: Int32(height), stride: Int32(stride))
    }
    
    private func convertYUVToBGRA(pixelBuffer: CVPixelBuffer, 
                                 destBuffer: UnsafeMutableRawPointer,
                                 width: Int, 
                                 height: Int,
                                 isFullRange: Bool) {
        // Get Y and UV planes
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            logger.error("Failed to get YUV planes")
            return
        }
        
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        
        let yPtr = yPlane.assumingMemoryBound(to: UInt8.self)
        let uvPtr = uvPlane.assumingMemoryBound(to: UInt8.self)
        let bgraPtr = destBuffer.assumingMemoryBound(to: UInt8.self)
        
        // YUV to RGB conversion coefficients
        let yOffset: Float = isFullRange ? 0.0 : 16.0
        let yScale: Float = isFullRange ? 1.0 : (255.0 / 219.0)
        
        // Process each pixel
        for y in 0..<height {
            for x in 0..<width {
                let yIndex = y * yStride + x
                let uvIndex = (y / 2) * uvStride + (x / 2) * 2
                let bgraIndex = (y * width + x) * 4
                
                let yValue = Float(yPtr[yIndex]) - yOffset
                let uValue = Float(uvPtr[uvIndex]) - 128.0
                let vValue = Float(uvPtr[uvIndex + 1]) - 128.0
                
                // YUV to RGB conversion
                let r = yValue * yScale + vValue * 1.5748
                let g = yValue * yScale - uValue * 0.1873 - vValue * 0.4681
                let b = yValue * yScale + uValue * 1.8556
                
                // Write BGRA
                bgraPtr[bgraIndex] = UInt8(max(0, min(255, b)))     // B
                bgraPtr[bgraIndex + 1] = UInt8(max(0, min(255, g))) // G
                bgraPtr[bgraIndex + 2] = UInt8(max(0, min(255, r))) // R
                bgraPtr[bgraIndex + 3] = 255                         // A
            }
        }
    }
}