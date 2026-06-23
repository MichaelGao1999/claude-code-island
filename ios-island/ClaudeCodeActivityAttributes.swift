import Foundation
import ActivityKit

// MARK: - Live Activity Attributes

/// Live Activity 属性（静态数据）
/// 在 Widget Extension 和主 App 之间共享
struct ClaudeCodeActivityAttributes: ActivityAttributes {
    var connectionStatus: String
    var startTime: Date

    struct ContentState: Codable, Hashable {
        var eventType: String
        var taskDescription: String
        var progress: Double
        var riskLevel: String?
    }
}
