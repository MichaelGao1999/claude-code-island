import Foundation
import Combine

/// WebSocket 客户端管理器，负责连接 Claude Code 事件流
/// 使用 URLSession WebSocket 实现，支持自动重连
@MainActor
final class EventStreamManager: ObservableObject, Sendable {
    
    // MARK: - Published Properties
    
    @Published var isConnected: Bool = false
    @Published var currentEvent: ClaudeEvent?
    @Published var eventHistory: [ClaudeEvent] = []
    @Published var connectionError: String?
    
    // MARK: - Private Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession
    private let serverURL: URL
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    private var reconnectTimer: Timer?
    
    // MARK: - Constants
    
    static let defaultServerURL = URL(string: "ws://localhost:8080/events")!
    
    // MARK: - Initialization
    
    init(serverURL: URL = Self.defaultServerURL) {
        self.serverURL = serverURL
        self.urlSession = URLSession.shared
    }
    
    // MARK: - Public Methods
    
    /// 连接到 WebSocket 服务器
    func connect() {
        guard !isConnected else { return }
        
        let request = URLRequest(url: serverURL)
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        isConnected = true
        connectionError = nil
        reconnectAttempts = 0
        
        // 发送连接事件
        handleEvent(ClaudeEvent(type: .connected, message: "已连接到 Claude Code"))
        
        // 开始接收消息
        receiveMessage()
    }
    
    /// 断开连接
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        
        // 发送断开事件
        handleEvent(ClaudeEvent(type: .disconnected, message: "连接已断开"))
        
        // 取消重连定时器
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    /// 发送审批响应
    /// - Parameters:
    ///   - eventId: 审批事件 ID
    ///   - approved: 是否批准
    func sendApprovalResponse(eventId: String, approved: Bool) {
        let response: [String: Any] = [
            "type": approved ? "APPROVED" : "REJECTED",
            "eventId": eventId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
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
    
    /// 接收 WebSocket 消息（递归调用）
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
                
                // 继续接收下一条消息
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
        if eventHistory.count > 100 {
            eventHistory.removeFirst(eventHistory.count - 100)
        }
    }
    
    /// 处理断开连接
    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
        
        // 尝试重连
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            let delay = TimeInterval(reconnectAttempts * 2) // 递增延迟
            
            reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.connect()
                }
            }
        } else {
            connectionError = "无法连接到 Claude Code，已达到最大重连次数"
            handleEvent(ClaudeEvent(type: .error, message: connectionError ?? "连接失败"))
        }
    }
    
    // MARK: - Mock Mode
    
    /// 启用 Mock 模式（用于测试）
    func enableMockMode() {
        isConnected = true
        connectionError = nil
        
        // 模拟事件流
        Task {
            for eventType in [EventType.thinking, .coding, .waiting, .approvalRequired] {
                try? await Task.sleep(for: .seconds(2))
                handleEvent(ClaudeEvent.sample(type: eventType))
            }
        }
    }
}