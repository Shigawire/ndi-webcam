import Foundation

class NDILibrary {
    static let shared = NDILibrary()
    
    private var libraryHandle: UnsafeMutableRawPointer?
    private let logger = Logger.shared
    
    // Function pointers
    private var _initialize: NDIlib_initialize_func?
    private var _destroy: NDIlib_destroy_func?
    private var _version: NDIlib_version_func?
    private var _send_create: NDIlib_send_create_func?
    private var _send_destroy: NDIlib_send_destroy_func?
    private var _send_send_video_v2: NDIlib_send_send_video_v2_func?
    private var _send_send_video_async_v2: NDIlib_send_send_video_async_v2_func?
    private var _send_get_no_connections: NDIlib_send_get_no_connections_func?
    private var _send_get_source_name: NDIlib_send_get_source_name_func?
    private var _send_clear_connection_metadata: NDIlib_send_clear_connection_metadata_func?
    
    
    // Possible NDI library paths on macOS
    private let libraryPaths = [
        "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
        "/usr/local/lib/libndi.dylib",
        "./libndi.dylib",
        "/Library/NDI/lib/libndi.dylib"
    ]
    
    private init() {}
    
    func load() -> Bool {
        // Try to load the library from known paths
        for path in libraryPaths {
            libraryHandle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if libraryHandle != nil {
                logger.info("NDI library loaded from: \(path)")
                break
            }
        }
        
        guard libraryHandle != nil else {
            logger.error("Failed to load NDI library. Please install NDI SDK from ndi.tv")
            logger.error("Tried paths: \(libraryPaths.joined(separator: ", "))")
            return false
        }
        
        // Load function pointers
        guard loadFunctions() else {
            logger.error("Failed to load NDI functions")
            unload()
            return false
        }
        
        // Initialize NDI
        guard initialize() else {
            logger.error("Failed to initialize NDI")
            unload()
            return false
        }
        
        // Log version
        if let versionStr = version() {
            logger.info("NDI Library Version: \(versionStr)")
        }
        
        return true
    }
    
    private func loadFunctions() -> Bool {
        guard let handle = libraryHandle else { return false }
        
        _initialize = unsafeBitCast(dlsym(handle, "NDIlib_initialize"), to: NDIlib_initialize_func?.self)
        _destroy = unsafeBitCast(dlsym(handle, "NDIlib_destroy"), to: NDIlib_destroy_func?.self)
        _version = unsafeBitCast(dlsym(handle, "NDIlib_version"), to: NDIlib_version_func?.self)
        _send_create = unsafeBitCast(dlsym(handle, "NDIlib_send_create"), to: NDIlib_send_create_func?.self)
        _send_destroy = unsafeBitCast(dlsym(handle, "NDIlib_send_destroy"), to: NDIlib_send_destroy_func?.self)
        _send_send_video_v2 = unsafeBitCast(dlsym(handle, "NDIlib_send_send_video_v2"), to: NDIlib_send_send_video_v2_func?.self)
        _send_send_video_async_v2 = unsafeBitCast(dlsym(handle, "NDIlib_send_send_video_async_v2"), to: NDIlib_send_send_video_async_v2_func?.self)
        _send_get_no_connections = unsafeBitCast(dlsym(handle, "NDIlib_send_get_no_connections"), to: NDIlib_send_get_no_connections_func?.self)
        _send_get_source_name = unsafeBitCast(dlsym(handle, "NDIlib_send_get_source_name"), to: NDIlib_send_get_source_name_func?.self)
        _send_clear_connection_metadata = unsafeBitCast(dlsym(handle, "NDIlib_send_clear_connection_metadata"), to: NDIlib_send_clear_connection_metadata_func?.self)
        
        
        // Check all required functions are loaded
        return _initialize != nil &&
               _send_create != nil &&
               _send_destroy != nil &&
               _send_send_video_v2 != nil &&
               _send_get_no_connections != nil
    }
    
    func unload() {
        if libraryHandle != nil {
            destroy()
            dlclose(libraryHandle)
            libraryHandle = nil
        }
    }
    
    // NDI API Wrappers
    
    func initialize() -> Bool {
        guard let fn = _initialize else { return false }
        return fn()
    }
    
    func destroy() {
        _destroy?()
    }
    
    func version() -> String? {
        guard let fn = _version,
              let ptr = fn() else { return nil }
        return String(cString: ptr)
    }
    
    func createSender(name: String) -> OpaquePointer? {
        guard let fn = _send_create else { return nil }
        
        var createSettings = NDIlib_send_create_t(name: name)
        defer { createSettings.cleanup() }
        
        return withUnsafePointer(to: &createSettings) { ptr in
            fn(UnsafeRawPointer(ptr))
        }
    }
    
    func destroySender(_ sender: OpaquePointer) {
        _send_destroy?(sender)
    }
    
    func sendVideo(_ sender: OpaquePointer, frame: inout NDIlib_video_frame_v2_t) {
        guard let fn = _send_send_video_v2 else { return }
        withUnsafePointer(to: &frame) { ptr in
            fn(sender, UnsafeRawPointer(ptr))
        }
    }
    
    func sendVideoAsync(_ sender: OpaquePointer, frame: inout NDIlib_video_frame_v2_t) {
        guard let fn = _send_send_video_async_v2 else { return }
        withUnsafePointer(to: &frame) { ptr in
            fn(sender, UnsafeRawPointer(ptr))
        }
    }
    
    func getConnectionCount(_ sender: OpaquePointer, timeout: UInt32 = 0) -> Int32 {
        return _send_get_no_connections?(sender, timeout) ?? 0
    }
    
    func clearConnectionMetadata(_ sender: OpaquePointer) {
        _send_clear_connection_metadata?(sender)
    }
    
    var supportsHX3: Bool {
        // H.264 compression works through standard NDI video frames with compressed FourCC
        // No special functions needed - just send H.264 data as compressed video frame
        return true
    }
    
    deinit {
        unload()
    }
}