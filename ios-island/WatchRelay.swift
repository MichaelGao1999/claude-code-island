import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// 将 Claude Code 事件通过 WCSession 转发到 Apple Watch
final class WatchRelay: NSObject, WCSessionDelegate {
    
    static let shared = WatchRelay()
    private var session: WCSession?
    
    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[WatchRelay] WCSession 激活状态: \(activationState.rawValue)")
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    
    // MARK: - Public
    
    /// 转发事件到手表
    func forwardEvent(_ event: ClaudeEvent) {
        guard let session = session, session.isReachable else { return }
        
        let encoder = JSONEncoder()
        guard let eventData = try? encoder.encode(event),
              let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else { return }
        
        let message: [String: Any] = [
            "type": "event",
            "data": eventDict
        ]
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("[WatchRelay] 发送失败: \(error.localizedDescription)")
        }
    }
    
    /// 同步连接状态到手表（后台上下文）
    func syncStatus(_ statusText: String) {
        guard let session = session else { return }
        let context: [String: Any] = [
            "type": "status",
            "statusText": statusText,
            "timestamp": Date().timeIntervalSince1970
        ]
        try? session.updateApplicationContext(context)
    }
}
#endif