import SwiftUI

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