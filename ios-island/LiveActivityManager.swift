import Foundation
import Combine

// MARK: - iOS 16.1+ 真实现

#if os(iOS)
import ActivityKit
import UserNotifications
import SwiftUI

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
        
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Live Activity 请求失败: \(error)")
            return
        }
        
        isActive = true
        print("Live Activity 已启动: \(activity?.id ?? "unknown")")
    }
    
    /// 更新 Live Activity 内容
    func updateActivity(with event: ClaudeEvent) {
        guard let activity = activity else {
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
    
    private func showApprovalAlert(_ event: ClaudeEvent) {
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

/// iOS 16.1 以下版本兼容
@available(iOS, introduced: 16.0, deprecated: 16.1, message: "Use LiveActivityManager instead")
final class LegacyActivityManager: ObservableObject {
    static let shared = LegacyActivityManager()
    
    func startActivity() {
        print("Live Activity 需要 iOS 16.1+")
    }
    
    func updateActivity(with event: ClaudeEvent) {}
    
    func endActivity() {}
}

#endif

// MARK: - macOS CLI / 非 iOS 环境存根

#if !os(iOS)
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published var isActive: Bool = false
    private init() {}
    func startActivity() { print("[存根] LiveActivityManager.startActivity") }
    func updateActivity(with event: ClaudeEvent) {}
    func endActivity() { print("[存根] LiveActivityManager.endActivity") }
}

final class LegacyActivityManager: ObservableObject {
    static let shared = LegacyActivityManager()
    func startActivity() { print("[存根] LegacyActivityManager.startActivity") }
    func updateActivity(with event: ClaudeEvent) {}
    func endActivity() {}
}
#endif