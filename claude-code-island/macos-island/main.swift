import SwiftUI

// MARK: - App Entry Point

/// Claude Code Island macOS 应用入口
/// 使用 MenuBarExtra 在菜单栏/灵动岛显示状态
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

// MARK: - Menu Bar Content View

/// 菜单栏内容视图
struct MenuBarContentView: View {
    
    @ObservedObject var eventManager: EventStreamManager
    
    var body: some View {
        VStack(spacing: 12) {
            // 状态概览
            statusOverview
            
            Divider()
            
            // 当前任务
            if let event = eventManager.currentEvent {
                currentTaskView(event)
            }
            
            Divider()
            
            // 操作按钮
            actionButtons
        }
        .padding()
        .frame(width: 280)
    }
    
    // MARK: - Status Overview
    
    private var statusOverview: some View {
        HStack(spacing: 8) {
            // 连接状态图标
            Image(systemName: eventManager.isConnected ? "wifi" : "wifi.slash")
                .foregroundColor(eventManager.isConnected ? .green : .red)
            
            Text(eventManager.isConnected ? "已连接" : "未连接")
                .font(.system(size: 12, weight: .medium))
            
            Spacer()
            
            // 事件计数
            Text("\(eventManager.eventHistory.count) 事件")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Current Task View
    
    private func currentTaskView(_ event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 事件类型
            HStack {
                Circle()
                    .fill(statusColor(for: event.type))
                    .frame(width: 8, height: 8)
                
                Text(event.type.displayName)
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text(timeAgoString(from: event.receivedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 任务描述
            if let description = event.payload.taskDescription {
                Text(description)
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            
            // 进度条
            if let progress = event.payload.progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                
                Text("\(Int(progress * 100))% 完成")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 审批提示
            if event.type == .approvalRequired {
                HStack(spacing: 8) {
                    Button("批准") {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: true
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("拒绝") {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: false
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private func statusColor(for type: EventType) -> Color {
        switch type {
        case .thinking: return .blue
        case .coding: return .green
        case .waiting: return .orange
        case .approvalRequired: return .red
        case .approved: return .green
        case .rejected: return .red
        case .error: return .red
        case .connected: return .green
        case .disconnected: return .gray
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 8) {
            // 连接/断开
            Button {
                if eventManager.isConnected {
                    eventManager.disconnect()
                } else {
                    eventManager.connect()
                }
            } label: {
                Label(
                    eventManager.isConnected ? "断开连接" : "连接",
                    systemImage: eventManager.isConnected ? "wifi.slash" : "wifi"
                )
            }
            
            // Mock 模式
            Button {
                eventManager.enableMockMode()
            } label: {
                Label("Mock 模式", systemImage: "wand.and.stars")
            }
            
            Divider()
            
            // 打开设置
            Button {
                // 打开设置窗口
            } label: {
                Label("设置", systemImage: "gear")
            }
            
            // 退出
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else {
            return "\(Int(interval / 3600))小时前"
        }
    }
}

// MARK: - Settings View

/// 设置视图
struct SettingsView: View {
    
    @ObservedObject var eventManager: EventStreamManager
    @AppStorage("serverURL") private var serverURL: String = "ws://localhost:8080/events"
    @AppStorage("autoConnect") private var autoConnect: Bool = true
    @AppStorage("showNotifications") private var showNotifications: Bool = true
    
    var body: some View {
        Form {
            Section("连接设置") {
                LabeledContent("服务器地址") {
                    TextField("WebSocket URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                
                Toggle("自动连接", isOn: $autoConnect)
                Toggle("显示通知", isOn: $showNotifications)
            }
            
            Section("状态") {
                LabeledContent("连接状态") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(eventManager.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        
                        Text(eventManager.isConnected ? "已连接" : "未连接")
                    }
                }
                
                LabeledContent("事件历史") {
                    Text("\(eventManager.eventHistory.count) 条")
                }
                
                if let error = eventManager.connectionError {
                    LabeledContent("错误信息") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section("操作") {
                Button("清除历史记录") {
                    eventManager.eventHistory.removeAll()
                }
                
                Button("重新连接") {
                    eventManager.disconnect()
                    eventManager.connect()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
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