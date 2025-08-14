import Foundation

protocol SubscriberMonitorDelegate: AnyObject {
    func subscriberMonitor(_ monitor: SubscriberMonitor, subscribersChanged count: Int32)
    func subscriberMonitorShouldStartCamera(_ monitor: SubscriberMonitor)
    func subscriberMonitorShouldStopCamera(_ monitor: SubscriberMonitor)
}

class SubscriberMonitor {
    weak var delegate: SubscriberMonitorDelegate?
    
    private let ndiSender: NDISender
    private let logger = Logger.shared
    private var monitorTimer: Timer?
    private var lastConnectionCount: Int32 = 0
    private var zeroConnectionTime: Date?
    private let hysteresisDelay: TimeInterval = 2.0 // 2 seconds before stopping camera
    private let pollInterval: TimeInterval = 0.5 // Check every 500ms
    
    private var isCameraActive = false
    
    init(ndiSender: NDISender) {
        self.ndiSender = ndiSender
    }
    
    func startMonitoring() {
        stopMonitoring() // Ensure we don't have duplicate timers
        
        monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkSubscribers()
        }
        
        logger.info("Subscriber monitoring started")
    }
    
    func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        logger.info("Subscriber monitoring stopped")
    }
    
    private func checkSubscribers() {
        let currentCount = ndiSender.getConnectionCount()
        
        // Notify if count changed
        if currentCount != lastConnectionCount {
            logger.info("Subscriber count changed: \(lastConnectionCount) → \(currentCount)")
            delegate?.subscriberMonitor(self, subscribersChanged: currentCount)
            
            // Handle new subscribers
            if currentCount > 0 && lastConnectionCount == 0 {
                handleSubscribersConnected()
            }
            // Handle all subscribers disconnected
            else if currentCount == 0 && lastConnectionCount > 0 {
                handleSubscribersDisconnected()
            }
            
            lastConnectionCount = currentCount
        }
        
        // Check hysteresis for camera stop
        if currentCount == 0 && isCameraActive {
            if let zeroTime = zeroConnectionTime {
                let elapsed = Date().timeIntervalSince(zeroTime)
                if elapsed >= hysteresisDelay {
                    // Enough time has passed with zero connections
                    stopCamera()
                }
            }
        }
    }
    
    private func handleSubscribersConnected() {
        logger.info("First subscriber connected")
        zeroConnectionTime = nil // Reset hysteresis timer
        
        if !isCameraActive {
            startCamera()
        }
    }
    
    private func handleSubscribersDisconnected() {
        logger.info("All subscribers disconnected, starting hysteresis timer")
        zeroConnectionTime = Date() // Start hysteresis timer
    }
    
    private func startCamera() {
        logger.info("Starting camera due to subscriber activity")
        isCameraActive = true
        delegate?.subscriberMonitorShouldStartCamera(self)
    }
    
    private func stopCamera() {
        logger.info("Stopping camera after hysteresis delay")
        isCameraActive = false
        zeroConnectionTime = nil
        delegate?.subscriberMonitorShouldStopCamera(self)
    }
    
    deinit {
        stopMonitoring()
    }
}