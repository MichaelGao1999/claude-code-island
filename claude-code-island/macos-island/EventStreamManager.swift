import Foundation
import Combine

// MARK: - ConnectionState

enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(Error)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - WebSocketError

enum WebSocketError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case sendFailed(String)
    case invalidURL
    case maxRetriesExceeded
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "连接失败: \(reason)"
        case .sendFailed(let reason):
            return "发送失败: \(reason)"
        case .invalidURL:
            return "无效的URL地址"
        case .maxRetriesExceeded:
            return "已达到最大重试次数"
        case .invalidMessage:
            return "无效的消息格式"
        }
    }
}

// MARK: - EventStreamManager

@MainActor
final class EventStreamManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var events: [ClaudeEvent] = []
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var pendingApproval: ApprovalInfo?
    @Published private(set) var currentEvent: ClaudeEvent?

    // MARK: - Private Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private var reconnectAttempts = 0
    private let maxRetries = 3
    private var currentURL: URL?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Singleton

    static let shared = EventStreamManager()

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Public Methods

    /// 连接到 Claude Code WebSocket 服务器
    func connect(url: URL) {
        guard connectionState != .connected else { return }

        currentURL = url
        reconnectAttempts = 0
        establishConnection(to: url)
    }

    /// 断开连接
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        currentURL = nil
        reconnectAttempts = 0
    }

    /// 发送审批结果
    /// - Parameters:
    ///   - eventId: 事件ID
    ///   - approved: 是否批准
    func sendApproval(eventId: String, approved: Bool) {
        let message: [String: Any] = [
            "type": "approval_response",
            "event_id": eventId,
            "approved": approved,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)

        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleError(.sendFailed(error.localizedDescription))
                }
            } else {
                Task { @MainActor in
                    self?.clearPendingApproval()
                    let eventType: EventType = approved ? .approved : .rejected
                    self?.addEvent(ClaudeEvent(type: eventType, message: approved ? "命令已批准" : "命令已拒绝"))
                }
            }
        }
    }

    /// 清空事件历史
    func clearEvents() {
        events.removeAll()
    }

    // MARK: - Private Methods

    private func establishConnection(to url: URL) {
        connectionState = .connecting

        webSocketTask?.cancel(with: .goingAway, reason: nil)

        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()
        sendPing()

        connectionState = .connected
        addEvent(ClaudeEvent(type: .connected, message: "已连接到 Claude Code"))
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage()

                case .failure(let error):
                    self?.handleError(.connectionFailed(error.localizedDescription))
                    self?.attemptReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseJSONMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseJSONMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseJSONMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // 尝试解析为 ClaudeEvent
        if let event = try? JSONDecoder().decode(ClaudeEvent.self, from: data) {
            addEvent(event)

            if event.type == .approvalRequired {
                pendingApproval = ApprovalInfo(from: event)
            }
            return
        }

        // 尝试解析为通用消息格式
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let typeString = json["type"] as? String,
           let eventType = EventType(rawValue: typeString) {

            let payload = EventPayload(
                taskDescription: json["task_description"] as? String,
                message: json["message"] as? String,
                timestamp: Date(),
                commandSummary: json["command_summary"] as? String,
                commandDetails: json["command_details"] as? String,
                riskLevel: (json["risk_level"] as? String).flatMap { RiskLevel(rawValue: $0) },
                eventId: json["event_id"] as? String,
                rawCommand: json["raw_command"] as? String,
                progress: json["progress"] as? Double,
                status: json["status"] as? String
            )

            let event = ClaudeEvent(type: eventType, payload: payload)
            addEvent(event)

            if eventType == .approvalRequired {
                pendingApproval = ApprovalInfo(from: event)
            }
        }
    }

    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.handleError(.connectionFailed(error.localizedDescription))
                }
            }
        }

        // 每30秒发送一次ping
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            Task { @MainActor in
                if self.connectionState.isConnected {
                    self.sendPing()
                }
            }
        }
    }

    private func addEvent(_ event: ClaudeEvent) {
        events.insert(event, at: 0)
        currentEvent = event

        // 保持事件列表最多100条
        if events.count > 100 {
            events = Array(events.prefix(100))
        }
    }

    private func clearPendingApproval() {
        pendingApproval = nil
    }

    private func handleError(_ error: WebSocketError) {
        addEvent(ClaudeEvent(type: .error, message: error.localizedDescription))
    }

    private func attemptReconnect() {
        guard reconnectAttempts < maxRetries,
              let url = currentURL else {
            connectionState = .failed(WebSocketError.maxRetriesExceeded)
            addEvent(ClaudeEvent(type: .disconnected, message: "连接断开，重试次数已用尽"))
            return
        }

        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts)

        Task {
            try? await Task.sleep(nanoseconds: UInt64(reconnectAttempts * 2_000_000_000))
            Task { @MainActor in
                self.establishConnection(to: url)
            }
        }
    }
}

// MARK: - Convenience Methods for Testing

extension EventStreamManager {
    /// 添加模拟审批事件（用于开发测试）
    func addMockApprovalEvent() {
        let event = ClaudeEvent.sampleApprovalEvent
        addEvent(event)
        pendingApproval = ApprovalInfo(from: event)
    }

    /// 添加模拟状态事件（用于开发测试）
    func addMockEvent(type: EventType) {
        addEvent(ClaudeEvent.sample(type: type))
    }

    /// 模拟批准命令
    func mockApprove() {
        if let approval = pendingApproval {
            sendApproval(eventId: approval.eventId, approved: true)
        }
    }

    /// 模拟拒绝命令
    func mockReject() {
        if let approval = pendingApproval {
            sendApproval(eventId: approval.eventId, approved: false)
        }
    }
}
