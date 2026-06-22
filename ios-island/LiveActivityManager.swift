import Foundation
import ActivityKit

/// Live Activity 管理器
/// 使用 ActivityKit 在 iOS 锁屏显示 Claude Code 状态
/// 需要 iOS 16.1+ 和适当的权限配置
@available(iOS 16.1, *)
final class LiveActivityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LiveActivityManager()
    
    // MARK: - Properties
    
    private var activity: Activity<ClaudeCodeActivityAttributes>?
    @Published var isActive: Bool = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// 开始 Live Activity
    func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activity 未授权")
            return
        }
        
        let attributes = ClaudeCodeActivityAttributes(
            connectionStatus: "已连接",
            startTime: Date()
        )
        
        let initialState = ClaudeCodeActivityAttributes.ContentState(
            eventType: "等待中",
            taskDescription: "等待 Claude Code...",
            progress: 0,
            riskLevel: nil
        )
        
        activity = Activity.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil),
            pushType: nil
        )
        
        isActive = true
        print("Live Activity 已启动: \(activity?.id ?? "unknown")")
    }
    
    /// 更新 Live Activity 内容
    func updateActivity(with event: ClaudeEvent) {
        guard let activity = activity else {
            // 如果没有活动，尝试启动
            startActivity()
            return
        }
        
        let updatedState = ClaudeCodeActivityAttributes.ContentState(
            eventType: event.type.displayName,
            taskDescription: event.payload.taskDescription ?? event.payload.message ?? "",
            progress: event.payload.progress ?? 0,
            riskLevel: event.payload.riskLevel?.displayName
        )
        
        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
        }
        
        // 如果是审批事件，显示特殊状态
        if event.type == .approvalRequired {
            showApprovalAlert(event)
        }
    }
    
    /// 结束 Live Activity
    func endActivity() {
        guard let activity = activity else { return }
        
        let finalState = ClaudeCodeActivityAttributes.ContentState(
            eventType: "已完成",
            taskDescription: "任务已结束",
            progress: 1.0,
            riskLevel: nil
        )
        
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
        
        self.activity = nil
        isActive = false
    }
    
    // MARK: - Private Methods
    
    /// 显示审批提醒
    private func showApprovalAlert(_ event: ClaudeEvent) {
        // Live Activity 本身不支持交互按钮
        // 用户需要打开 App 来进行审批
        // 这里可以触发本地通知提醒用户
        
        let content = UNMutableNotificationContent()
        content.title = "需要审批"
        content.body = event.payload.commandSummary ?? "Claude Code 正在请求执行高风险操作"
        content.sound = .default
        content.categoryIdentifier = "APPROVAL_CATEGORY"
        
        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Activity Attributes

/// Live Activity 属性（静态数据）
struct ClaudeCodeActivityAttributes: ActivityAttributes {
    
    /// 静态属性
    var connectionStatus: String
    var startTime: Date
    
    /// 动态状态
    struct ContentState: Codable, Hashable {
        var eventType: String
        var taskDescription: String
        var progress: Double
        var riskLevel: String?
    }
}

// MARK: - Live Activity Widget

/// Live Activity Widget 视图（用于锁屏显示）
/// 注意：此视图需要在 Widget Extension 中实现
/// 这里仅作为参考示例
@available(iOS 16.1, *)
struct ClaudeCodeLiveActivity: Widget {
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeCodeActivityAttributes.self) { context in
            // 锁屏视图
            VStack(alignment: .leading, spacing: 8) {
                // 状态图标和类型
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .foregroundColor(.blue)
                    
                    Text(context.state.eventType)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Spacer()
                    
                    // 风险等级
                    if let riskLevel = context.state.riskLevel {
                        Text(riskLevel)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                
                // 任务描述
                Text(context.state.taskDescription)
                    .font(.system(size: 12))
                    .lineLimit(2)
                
                // 进度条
                if context.state.progress > 0 {
                    ProgressView(value: context.state.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.green)
                }
            }
            .padding()
            
        } dynamicIsland: { context in
            // Dynamic Island 视图
            DynamicIsland {
                // Expanded 视图
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "terminal")
                        .foregroundColor(.blue)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.system(size: 12))
                }
                
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.eventType)
                        .font(.system(size: 14, weight: .semibold))
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.taskDescription)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                
            } compactLeading: {
                // Compact Leading 视图
                Image(systemName: "terminal")
                    .foregroundColor(.blue)
                
            } compactTrailing: {
                // Compact Trailing 视图
                Text(context.state.eventType)
                    .font(.system(size: 10))
                
            } minimal: {
                // Minimal 视图
                Image(systemName: "terminal")
                    .foregroundColor(.blue)
            }
        }
    }
}

// MARK: - iOS 16.1 以下版本兼容

/// iOS 16.1 以下版本的空实现
@available(iOS, introduced: 16.0, deprecated: 16.1, message: "Use LiveActivityManager instead")
final class LegacyActivityManager: ObservableObject {
    
    static let shared = LegacyActivityManager()
    
    func startActivity() {
        print("Live Activity 需要 iOS 16.1+")
    }
    
    func updateActivity(with event: ClaudeEvent) {
        // 不支持
    }
    
    func endActivity() {
        // 不支持
    }
}