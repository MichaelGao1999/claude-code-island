import Foundation

// MARK: - EventType

enum EventType: String, Codable, CaseIterable, Sendable {
    case thinking
    case coding
    case waiting
    case approved
    case rejected
    case error
    case connected
    case disconnected
    case approvalRequired

    var displayName: String {
        switch self {
        case .thinking: return "思考中"
        case .coding: return "编码中"
        case .waiting: return "等待中"
        case .approved: return "已批准"
        case .rejected: return "已拒绝"
        case .error: return "错误"
        case .connected: return "已连接"
        case .disconnected: return "已断开"
        case .approvalRequired: return "需要审批"
        }
    }
}

// MARK: - RiskLevel

enum RiskLevel: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }

    var displayName: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高风险"
        case .critical: return "严重风险"
        }
    }
}

// MARK: - EventPayload

struct EventPayload: Codable, Sendable {
    // 通用字段
    var taskDescription: String?
    var message: String?
    var timestamp: Date?

    // 审批相关
    var commandSummary: String?
    var commandDetails: String?
    var riskLevel: RiskLevel?
    var eventId: String?
    var rawCommand: String?

    // 状态相关
    var progress: Double?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case taskDescription = "task_description"
        case message
        case timestamp
        case commandSummary = "command_summary"
        case commandDetails = "command_details"
        case riskLevel = "risk_level"
        case eventId = "event_id"
        case rawCommand = "raw_command"
        case progress
        case status
    }
}

// MARK: - ClaudeEvent

struct ClaudeEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let type: EventType
    let payload: EventPayload
    let receivedAt: Date

    init(id: UUID = UUID(), type: EventType, payload: EventPayload, receivedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.payload = payload
        self.receivedAt = receivedAt
    }

    // MARK: - 便捷初始化

    init(type: EventType, taskDescription: String? = nil, message: String? = nil) {
        self.id = UUID()
        self.type = type
        self.payload = EventPayload(
            taskDescription: taskDescription,
            message: message,
            timestamp: Date()
        )
        self.receivedAt = Date()
    }

    // MARK: - Sample Data

    static func sample(type: EventType = .thinking) -> ClaudeEvent {
        let payload: EventPayload
        switch type {
        case .approvalRequired:
            payload = EventPayload(
                commandSummary: "rm -rf /node_modules",
                commandDetails: "删除整个node_modules目录及其所有依赖包",
                riskLevel: .high,
                eventId: UUID().uuidString,
                rawCommand: "rm -rf ./node_modules"
            )
        case .thinking:
            payload = EventPayload(
                taskDescription: "分析项目结构并规划重构方案",
                message: "正在分析依赖关系..."
            )
        case .coding:
            payload = EventPayload(
                taskDescription: "重构用户认证模块",
                progress: 0.65,
                status: "coding"
            )
        case .waiting:
            payload = EventPayload(
                taskDescription: "等待API响应",
                message: "正在从服务器获取数据..."
            )
        case .approved:
            payload = EventPayload(
                message: "命令已批准执行",
                status: "approved"
            )
        case .rejected:
            payload = EventPayload(
                message: "命令已被拒绝",
                status: "rejected"
            )
        case .error:
            payload = EventPayload(
                message: "执行过程中发生错误",
                status: "error"
            )
        case .connected:
            payload = EventPayload(
                message: "已成功连接到Claude Code"
            )
        case .disconnected:
            payload = EventPayload(
                message: "与Claude Code的连接已断开"
            )
        }
        return ClaudeEvent(type: type, payload: payload)
    }

    static var sampleApprovalEvent: ClaudeEvent {
        .sample(type: .approvalRequired)
    }

    static var sampleThinkingEvent: ClaudeEvent {
        .sample(type: .thinking)
    }

    static var sampleCodingEvent: ClaudeEvent {
        .sample(type: .coding)
    }
}

// MARK: - ApprovalInfo

struct ApprovalInfo: Sendable {
    let eventId: String
    let commandSummary: String
    let commandDetails: String
    let riskLevel: RiskLevel
    let rawCommand: String

    init(from event: ClaudeEvent) {
        self.eventId = event.payload.eventId ?? event.id.uuidString
        self.commandSummary = event.payload.commandSummary ?? ""
        self.commandDetails = event.payload.commandDetails ?? ""
        self.riskLevel = event.payload.riskLevel ?? .low
        self.rawCommand = event.payload.rawCommand ?? ""
    }
}
