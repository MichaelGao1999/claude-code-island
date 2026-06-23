import Foundation

/// Live Activity 状态数据
/// 用于在主 App 和 Widget Extension 之间共享数据
/// 注意：此文件需要与主 App 和 Widget Extension 共享
struct ClaudeIslandActivityState: Codable, Hashable {
    var eventType: String
    var taskDescription: String
    var progress: Double
    var riskLevel: String?
    var isCompact: Bool
    var startTime: Date
    
    var riskColor: String {
        switch riskLevel {
        case "低风险": return "green"
        case "中风险": return "orange"
        case "高风险": return "red"
        case "严重风险": return "purple"
        default: return "gray"
        }
    }
}

/// 共享的 App Groups UserDefaults key
enum SharedKeys {
    static let activityState = "ClaudeIslandActivityState"
    static let appGroupIdentifier = "group.com.claudecode.island"
}
