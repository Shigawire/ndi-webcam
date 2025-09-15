import Foundation

// NDI FourCC codes
let NDI_FourCC_BGRA = UInt32(0x41524742) // 'BGRA'
let NDI_FourCC_BGRX = UInt32(0x58524742) // 'BGRX'
let NDI_FourCC_RGBA = UInt32(0x41424752) // 'RGBA'
let NDI_FourCC_RGBX = UInt32(0x58424752) // 'RGBX'

// NDI H.264 FourCC codes (based on NDI documentation)
// H.264 compressed video - using standard NDI approach
let NDI_FourCC_H264 = UInt32(NDI_LIB_FOURCC(Character("H").asciiValue!, Character("2").asciiValue!, Character("6").asciiValue!, Character("4").asciiValue!))

// Helper to create FourCC from characters
private func NDI_LIB_FOURCC(_ ch0: UInt8, _ ch1: UInt8, _ ch2: UInt8, _ ch3: UInt8) -> UInt32 {
    return UInt32(ch0) | (UInt32(ch1) << 8) | (UInt32(ch2) << 16) | (UInt32(ch3) << 24)
}

// NDI frame format types
let NDIlib_frame_format_type_progressive: Int32 = 1
let NDIlib_frame_format_type_interleaved: Int32 = 0
let NDIlib_frame_format_type_field_0: Int32 = 2
let NDIlib_frame_format_type_field_1: Int32 = 3

// NDI send timecode
let NDIlib_send_timecode_synthesize: Int64 = .max

// NDI structures matching C API
struct NDIlib_source_t {
    var p_ndi_name: UnsafePointer<CChar>?
    var p_ip_address: UnsafePointer<CChar>?
}

struct NDIlib_send_create_t {
    var p_ndi_name: UnsafePointer<CChar>?
    var p_groups: UnsafePointer<CChar>?
    var clock_video: Bool
    var clock_audio: Bool
    
    init(name: String) {
        let nameCopy = strdup(name)
        self.p_ndi_name = UnsafePointer(nameCopy)
        self.p_groups = nil
        self.clock_video = true
        self.clock_audio = false
    }
    
    func cleanup() {
        if let ptr = p_ndi_name {
            free(UnsafeMutablePointer(mutating: ptr))
        }
        if let ptr = p_groups {
            free(UnsafeMutablePointer(mutating: ptr))
        }
    }
}

struct NDIlib_video_frame_v2_t {
    var xres: Int32
    var yres: Int32
    var FourCC: UInt32
    var frame_rate_N: Int32
    var frame_rate_D: Int32
    var picture_aspect_ratio: Float
    var frame_format_type: Int32
    var timecode: Int64
    var p_data: UnsafeMutableRawPointer?
    var line_stride_in_bytes: Int32  // This is part of a union with data_size_in_bytes
    var p_metadata: UnsafePointer<CChar>?
    var timestamp: Int64
    
    // Computed property to access the union field for compressed data
    var data_size_in_bytes: Int32 {
        get { return line_stride_in_bytes }
        set { line_stride_in_bytes = newValue }
    }
    
    init(width: Int32, height: Int32, frameRateN: Int32 = 30, frameRateD: Int32 = 1, fourCC: UInt32 = NDI_FourCC_BGRA) {
        self.xres = width
        self.yres = height
        self.FourCC = fourCC
        self.frame_rate_N = frameRateN
        self.frame_rate_D = frameRateD
        self.picture_aspect_ratio = Float(width) / Float(height)
        self.frame_format_type = NDIlib_frame_format_type_progressive
        self.timecode = NDIlib_send_timecode_synthesize
        self.p_data = nil
        self.line_stride_in_bytes = fourCC == NDI_FourCC_BGRA ? width * 4 : 0 // Variable for compressed formats
        self.p_metadata = nil
        self.timestamp = 0
    }
}

// NDI compressed packet structure for H.264 data
struct NDIlib_compressed_packet_t {
    var pts: Int64
    var dts: Int64
    var data_size_in_bytes: Int32
    var p_data: UnsafeMutableRawPointer?
    var fourCC: UInt32
    var timestamp: Int64
    
    init(fourCC: UInt32 = NDI_FourCC_H264) {
        self.pts = 0
        self.dts = 0
        self.data_size_in_bytes = 0
        self.p_data = nil
        self.fourCC = fourCC
        self.timestamp = 0
    }
}

// NDI function pointer types
typealias NDIlib_initialize_func = @convention(c) () -> Bool
typealias NDIlib_destroy_func = @convention(c) () -> Void
typealias NDIlib_version_func = @convention(c) () -> UnsafePointer<CChar>?
typealias NDIlib_send_create_func = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
typealias NDIlib_send_destroy_func = @convention(c) (OpaquePointer?) -> Void
typealias NDIlib_send_send_video_v2_func = @convention(c) (OpaquePointer?, UnsafeRawPointer?) -> Void
typealias NDIlib_send_send_video_async_v2_func = @convention(c) (OpaquePointer?, UnsafeRawPointer?) -> Void
typealias NDIlib_send_get_no_connections_func = @convention(c) (OpaquePointer?, UInt32) -> Int32
typealias NDIlib_send_get_source_name_func = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void
typealias NDIlib_send_clear_connection_metadata_func = @convention(c) (OpaquePointer?) -> Void

// NDI HX3 function pointer types
typealias NDIlib_send_is_keyframe_required_func = @convention(c) (OpaquePointer?, Int64) -> Bool
typealias NDIlib_send_get_target_frame_size_func = @convention(c) (OpaquePointer?, Int32, Int32, Int32, Int32, UInt32) -> Int32
typealias NDIlib_send_get_target_bit_rate_func = @convention(c) (OpaquePointer?, Int32, Int32, Int32, Int32) -> Int32