import Foundation
import WatchConnectivity

/// watchOS 侧会话管理器
/// 接收 iPhone 通过 WCSession 转发的 Claude Code 事件
final class SessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = SessionManager()

    @Published var isReachable: Bool = false
    @Published var currentEvent: ClaudeEvent?
    @Published var eventHistory: [ClaudeEvent] = []
    @Published var connectionStatus: String = "未连接"

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            isReachable = session.isReachable
            print("[SessionManager] WCSession 已激活")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        isReachable = session.isReachable
    }

    /// 收到 iPhone 发来的事件
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingMessage(message, reply: replyHandler)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // 后台上下文更新（用于 Complication 刷新）
        handleContextUpdate(applicationContext)
    }

    // MARK: - Private

    private func handleIncomingMessage(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        guard let type = message["type"] as? String else {
            reply(["status": "unknown_type"])
            return
        }

        switch type {
        case "event":
            // 包含完整的 ClaudeEvent JSON
            if let jsonData = try? JSONSerialization.data(withJSONObject: message["data"] as? [String: Any] ?? [:]),
               let event = try? JSONDecoder().decode(ClaudeEvent.self, from: jsonData) {
                DispatchQueue.main.async {
                    self.currentEvent = event
                    self.eventHistory.append(event)
                    self.connectionStatus = event.type.displayName
                    // 限制历史
                    if self.eventHistory.count > 20 {
                        self.eventHistory.removeFirst(self.eventHistory.count - 20)
                    }
                }
                reply(["status": "ok"])
            } else {
                reply(["status": "parse_error"])
            }

        case "status":
            // 连接状态更新
            if let status = message["statusText"] as? String {
                DispatchQueue.main.async {
                    self.connectionStatus = status
                }
            }
            reply(["status": "ok"])

        default:
            reply(["status": "ignored"])
        }
    }

    private func handleContextUpdate(_ context: [String: Any]) {
        // 后台更新（用于 Complication）
        if let statusText = context["status"] as? String {
            DispatchQueue.main.async {
                self.connectionStatus = statusText
            }
        }
    }
}