import Foundation
import Network

/// WebSocket Mock Server
/// 用于测试 Claude Code Island 的 WebSocket 通信
/// 模拟 Claude Code 发送事件流
@available(macOS 14.0, *)
final class WebSocketMockServer {
    
    // MARK: - Properties
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let port: UInt16
    private let eventQueue: [ClaudeEvent]
    private var currentIndex: Int = 0
    
    // MARK: - Constants
    
    static let defaultPort: UInt16 = 8080
    
    // MARK: - Initialization
    
    init(port: UInt16 = Self.defaultPort) {
        self.port = port
        self.eventQueue = Self.generateMockEventSequence()
    }
    
    // MARK: - Public Methods
    
    /// 启动 Mock Server
    func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Mock Server 已启动，监听端口 \(self.port)")
            case .failed(let error):
                print("Mock Server 启动失败: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { connection in
            self.handleNewConnection(connection)
        }
        
        listener?.start(queue: .main)
    }
    
    /// 停止 Mock Server
    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        print("Mock Server 已停止")
    }
    
    /// 发送下一个事件
    func sendNextEvent() {
        guard currentIndex < eventQueue.count else {
            print("事件队列已结束")
            return
        }
        
        let event = eventQueue[currentIndex]
        currentIndex += 1
        
        sendEvent(event)
    }
    
    /// 发送指定事件
    func sendEvent(_ event: ClaudeEvent) {
        guard let jsonData = try? JSONEncoder().encode(event),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        connections.forEach { connection in
            connection.send(content: jsonString.data(using: .utf8), completion: .contentProcessed({ error in
                if let error = error {
                    print("发送事件失败: \(error)")
                }
            }))
        }
        
        print("已发送事件: \(event.type.displayName)")
    }
    
    // MARK: - Private Methods
    
    /// 处理新连接
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("新客户端已连接")
                self.receiveMessages(connection)
            case .failed(let error):
                print("连接失败: \(error)")
                self.connections.removeAll { $0 == connection }
            case .cancelled:
                self.connections.removeAll { $0 == connection }
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    /// 接收消息
    private func receiveMessages(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
            if let data = data, !data.isEmpty {
                self.handleReceivedMessage(data, connection)
            }
            
            if let error = error {
                print("接收消息失败: \(error)")
                return
            }
            
            self.receiveMessages(connection)
        }
    }
    
    /// 处理接收的消息
    private func handleReceivedMessage(_ data: Data, _ connection: NWConnection) {
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return
        }
        
        let type = response["type"] as? String
        let eventId = response["eventId"] as? String
        
        print("收到审批响应: \(type ?? "unknown") for \(eventId ?? "unknown")")
        
        // 模拟 Claude Code 处理审批响应
        if type == "APPROVED" {
            // 继续执行
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.sendNextEvent()
            }
        } else if type == "REJECTED" {
            // 任务失败
            let failedEvent = ClaudeEvent(
                type: .error,
                message: "用户拒绝了操作"
            )
            self.sendEvent(failedEvent)
        }
    }
    
    // MARK: - Mock Event Generation
    
    /// 生成模拟事件序列
    private static func generateMockEventSequence() -> [ClaudeEvent] {
        return [
            // 任务开始
            ClaudeEvent(
                type: .coding,
                taskDescription: "重构用户认证模块",
                message: "任务开始"
            ),
            
            // 思考
            ClaudeEvent(
                type: .thinking,
                taskDescription: "分析现有代码结构",
                message: "正在读取文件..."
            ),
            
            // 编码
            ClaudeEvent(
                type: .coding,
                taskDescription: "重构用户认证模块",
                progress: 0.25,
                message: "已完成 25%"
            ),
            
            ClaudeEvent(
                type: .coding,
                taskDescription: "重构用户认证模块",
                progress: 0.50,
                message: "已完成 50%"
            ),
            
            // 等待审批
            ClaudeEvent.sample(type: .approvalRequired),
            
            // 审批后继续
            ClaudeEvent(
                type: .coding,
                taskDescription: "重构用户认证模块",
                progress: 0.75,
                message: "已完成 75%"
            ),
            
            ClaudeEvent(
                type: .coding,
                taskDescription: "重构用户认证模块",
                progress: 1.0,
                message: "已完成 100%"
            ),
            
            // 任务完成
            ClaudeEvent(
                type: .approved,
                message: "任务成功完成"
            )
        ]
    }
    
    /// 自动发送事件流
    func startAutoSend(interval: TimeInterval = 2.0) {
        currentIndex = 0
        
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            if self.currentIndex < self.eventQueue.count {
                self.sendNextEvent()
            } else {
                timer.invalidate()
                print("事件流结束")
            }
        }
    }
}

// MARK: - Command Line Interface

/// 命令行入口
@available(macOS 14.0, *)
func runMockServerCLI() {
    let server = WebSocketMockServer()
    server.start()
    
    print("WebSocket Mock Server 已启动")
    print("端口: 8080")
    print("命令:")
    print("  - send: 发送下一个事件")
    print("  - auto: 自动发送事件流")
    print("  - stop: 停止服务器")
    print("  - quit: 退出")
    
    while true {
        print("\n> ", terminator: "")
        let command = readLine()?.lowercased() ?? ""
        
        switch command {
        case "send":
            server.sendNextEvent()
        case "auto":
            server.startAutoSend()
        case "stop":
            server.stop()
        case "quit":
            server.stop()
            return
        default:
            print("未知命令")
        }
    }
}

// MARK: - Main Entry

/// 启动 Mock Server
/// 使用方式：swift WebSocketMockServer.swift
if #available(macOS 14.0, *) {
    runMockServerCLI()
} else {
    print("WebSocket Mock Server 需要 macOS 14.0+")
}