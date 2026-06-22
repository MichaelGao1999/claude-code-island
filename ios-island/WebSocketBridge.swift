import Foundation
import Combine

/// WebSocket 桥接器，用于 iOS App 连接到 Mac relay
/// Mac 作为 WebSocket relay，转发 Claude Code 事件到 iOS
@MainActor
final class WebSocketBridge: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isConnected: Bool = false
    @Published var currentEvent: ClaudeEvent?
    @Published var eventHistory: [ClaudeEvent] = []
    @Published var connectionError: String?
    
    // MARK: - Private Properties
    
    var webSocketTask: URLSessionWebSocketTask?  // internal for HMACSigner extension
    private var urlSession: URLSession
    private let relayURL: URL
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var reconnectTimer: Timer?
    
    // MARK: - Constants
    
    static let defaultRelayURL = URL(string: "ws://localhost:8081/relay")!
    
    // MARK: - Initialization
    
    init(relayURL: URL? = nil) {
        self.relayURL = relayURL ?? Self.defaultRelayURL
        self.urlSession = URLSession.shared
    }
    
    // MARK: - Public Methods
    
    /// 连接到 Mac relay
    func connect() {
        guard !isConnected else { return }
        
        let request = URLRequest(url: relayURL)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        connectionError = nil
        reconnectAttempts = 0
        
        receiveMessage()
    }
    
    /// 断开连接
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    /// 发送审批响应到 Mac relay
    /// - Parameters:
    ///   - eventId: 审批事件 ID
    ///   - approved: 是否批准
    func sendApprovalResponse(eventId: String, approved: Bool) {
        let response: [String: Any] = [
            "type": approved ? "APPROVED" : "REJECTED",
            "eventId": eventId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": "iOS"
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        webSocketTask?.send(.string(jsonString), completionHandler: { error in
            if let error = error {
                print("发送审批响应失败: \(error.localizedDescription)")
            }
        })
    }
    
    // MARK: - Private Methods
    
    /// 接收 WebSocket 消息
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            Task { @MainActor in
                switch result {
                case .success(.string(let jsonString)):
                    self.handleRawMessage(jsonString)
                    
                case .success(.data(let data)):
                    if let jsonString = String(data: data, encoding: .utf8) {
                        self.handleRawMessage(jsonString)
                    }
                    
                case .failure(let error):
                    print("接收消息失败: \(error.localizedDescription)")
                    self.handleDisconnect()
                    
                default:
                    break
                }
                
                if self.isConnected {
                    self.receiveMessage()
                }
            }
        }
    }
    
    /// 处理原始 JSON 消息
    private func handleRawMessage(_ jsonString: String) {
        guard let jsonData = jsonString.data(using: .utf8),
              let event = try? JSONDecoder().decode(ClaudeEvent.self, from: jsonData) else {
            print("无法解析事件: \(jsonString)")
            return
        }
        
        handleEvent(event)
    }
    
    /// 处理事件
    private func handleEvent(_ event: ClaudeEvent) {
        currentEvent = event
        eventHistory.append(event)
        
        // 限制历史记录长度
        if eventHistory.count > 50 {
            eventHistory.removeFirst(eventHistory.count - 50)
        }
        
        // 更新 Live Activity
        LiveActivityManager.shared.updateActivity(with: event)
    }
    
    /// 处理断开连接
    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = TimeInterval(reconnectAttempts * 2)
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.connect()
                }
            }
        } else {
            connectionError = "无法连接到 Mac relay，已达到最大重连次数"
        }
    }
    
    // MARK: - Mock Mode
    
    /// 启用 Mock 模式（用于测试）
    func enableMockMode() {
        isConnected = true
        connectionError = nil
        
        Task {
            for eventType in [EventType.thinking, .coding, .waiting, .approvalRequired] {
                try? await Task.sleep(for: .seconds(2))
                handleEvent(ClaudeEvent.sample(type: eventType))
            }
        }
    }
}

// MARK: - HMACSigner Integration

/// 扩展 WebSocketBridge 以支持 HMAC 签名验证（在 HMACSigner.swift 中实现）