import Foundation
import SwiftUI
import UserNotifications

/// macOS 通知和状态管理器
/// 使用 App Groups 在主 App 和 Widget Extension 之间共享数据
@MainActor
final class IslandLiveActivityManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = IslandLiveActivityManager()
    
    // MARK: - Properties
    
    @Published var isActive: Bool = false
    @Published var currentState: String = "等待中"
    
    private let appGroupDefaults: UserDefaults?
    
    // MARK: - Initialization
    
    private init() {
        self.appGroupDefaults = UserDefaults(suiteName: SharedKeys.appGroupIdentifier)
    }
    
    // MARK: - Public Methods
    
    /// 启动状态
    func startActivity() {
        isActive = true
        currentState = "已连接"
        
        // 写入初始状态到 App Groups
        updateSharedState(
            eventType: "已连接",
            taskDescription: "Claude Code Island 已启动",
            progress: 0,
            riskLevel: nil
        )
        
        print("[IslandManager] 已启动")
    }
    
    /// 更新状态
    func updateActivity(with event: ClaudeEvent) {
        currentState = event.type.displayName
        
        // 写入状态到 App Groups
        updateSharedState(
            eventType: event.type.displayName,
            taskDescription: event.payload.taskDescription ?? event.payload.message ?? "",
            progress: event.payload.progress ?? 0,
            riskLevel: event.payload.riskLevel?.displayName
        )
        
        // 审批请求时发送系统通知
        if event.type == .approvalRequired {
            sendApprovalNotification(event: event)
        }
    }
    
    /// 结束状态
    func endActivity() {
        isActive = false
        currentState = "已断开"
        
        // 清除共享状态
        appGroupDefaults?.removeObject(forKey: SharedKeys.activityState)
        
        print("[IslandManager] 已结束")
    }
    
    // MARK: - Shared State
    
    private func updateSharedState(
        eventType: String,
        taskDescription: String,
        progress: Double,
        riskLevel: String?
    ) {
        let state = ClaudeIslandActivityState(
            eventType: eventType,
            taskDescription: truncate(taskDescription, maxLength: 100),
            progress: progress,
            riskLevel: riskLevel,
            isCompact: false,
            startTime: Date()
        )
        
        guard let data = try? JSONEncoder().encode(state) else { return }
        appGroupDefaults?.set(data, forKey: SharedKeys.activityState)
    }
    
    private func truncate(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength - 1)) + "…"
    }
    
    // MARK: - Notifications
    
    /// 发送审批通知
    private func sendApprovalNotification(event: ClaudeEvent) {
        let content = UNMutableNotificationContent()
        content.title = "需要审批"
        content.body = event.payload.commandSummary ?? "Claude Code 正在请求执行操作"
        content.sound = .default
        content.categoryIdentifier = "APPROVAL_CATEGORY"
        
        // 添加操作按钮
        let approveAction = UNNotificationAction(
            identifier: "APPROVE",
            title: "批准",
            options: .foreground
        )
        let rejectAction = UNNotificationAction(
            identifier: "REJECT",
            title: "拒绝",
            options: .destructive
        )
        
        let approvalCategory = UNNotificationCategory(
            identifier: "APPROVAL_CATEGORY",
            actions: [approveAction, rejectAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([approvalCategory])
        
        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}
