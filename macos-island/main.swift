import SwiftUI

// MARK: - App Entry Point

/// Claude Code Island macOS 应用入口
/// 使用 MenuBarExtra 在菜单栏显示状态 + 系统通知
@main
struct IslandApp: App {
    
    // MARK: - State
    
    @StateObject private var eventManager = EventStreamManager()
    
    // MARK: - Scene
    
    var body: some Scene {
        // 菜单栏应用（macOS 13+）
        MenuBarExtra("Claude Code Island", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarContentView(eventManager: eventManager)
        }
        .menuBarExtraStyle(.window)
        
        // 设置窗口（可选）
        WindowGroup("设置") {
            SettingsView(eventManager: eventManager)
        }
        .defaultSize(width: 400, height: 300)
        
        // 审批窗口（弹出式）
        WindowGroup("审批请求", id: "approval") {
            if let event = eventManager.currentEvent,
               event.type == .approvalRequired {
                ApprovalView(
                    approvalInfo: ApprovalInfo(from: event),
                    onApprove: {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: true
                        )
                    },
                    onReject: {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: false
                        )
                    }
                )
            }
        }
        .defaultSize(width: 400, height: 500)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - App Delegate

/// 应用代理，处理启动和生命周期事件
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为菜单栏应用（不显示在 Dock）
        NSApplication.shared.setActivationPolicy(.accessory)
        
        // 自动连接
        if UserDefaults.standard.bool(forKey: "autoConnect") {
            // 延迟连接，等待 UI 初始化
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // 通过 EventStreamManager 连接
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // 断开连接
    }
}