import Foundation

enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
}

class Logger {
    static let shared = Logger()
    var logLevel: LogLevel = .info
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    private init() {}
    
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    func info(_ message: String) {
        log(message, level: .info)
    }
    
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    func error(_ message: String) {
        log(message, level: .error)
    }
    
    private func log(_ message: String, level: LogLevel) {
        guard level.rawValue >= logLevel.rawValue else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let levelStr = levelString(for: level)
        print("[\(timestamp)] [\(levelStr)] \(message)")
    }
    
    private func levelString(for level: LogLevel) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}