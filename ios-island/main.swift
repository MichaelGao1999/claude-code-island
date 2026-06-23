import SwiftUI
import Combine

// MARK: - App Entry Point

/// Claude Code Island iOS 伴侣应用入口
/// 提供 Live Activity 和远程审批功能
@main
struct iOSCompanionApp: App {
    
    // MARK: - State
    
    @StateObject private var bridge = WebSocketBridge()
    
    // MARK: - Scene
    
    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            ContentView(bridge: bridge)
                .onAppear {
                    bridge.connect()
                    LiveActivityManager.shared.startActivity()
                }
                .onReceive(bridge.$currentEvent) { event in
                    guard let event = event else { return }
                    LiveActivityManager.shared.updateActivity(with: event)
                }
        }
        #else
        WindowGroup {
            ContentView(bridge: bridge)
                .onAppear {
                    bridge.connect()
                }
        }
        #endif
    }
}

// MARK: - Content View

/// 主内容视图
struct ContentView: View {
    
    @ObservedObject var bridge: WebSocketBridge
    @State private var showApprovalSheet: Bool = false
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            contentView
                .navigationTitle("Claude Code Island")
        }
        #else
        contentView
        #endif
    }
    
    private var contentView: some View {
        VStack(spacing: 20) {
            connectionStatusView
            
            if let event = bridge.currentEvent {
                currentEventView(event)
            } else {
                waitingView
            }
            
            if !bridge.eventHistory.isEmpty {
                eventHistoryView
            }
            
            Spacer()
            
            actionButtons
        }
        .padding()
        .sheet(isPresented: $showApprovalSheet) {
            if let event = bridge.currentEvent,
               event.type == .approvalRequired {
                RemoteApprovalView(
                    approvalInfo: ApprovalInfo(from: event),
                    onApprove: {
                        bridge.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: true
                        )
                        showApprovalSheet = false
                    },
                    onReject: {
                        bridge.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: false
                        )
                        showApprovalSheet = false
                    }
                )
            }
        }
    }
    
    // MARK: - Connection Status View
    
    private var connectionStatusView: some View {
        HStack(spacing: 12) {
            // 状态图标
            ZStack {
                Circle()
                    .fill(bridge.isConnected ? Color.green : Color.red)
                    .frame(width: 40, height: 40)
                
                Image(systemName: bridge.isConnected ? "wifi" : "wifi.slash")
                    .foregroundColor(.white)
                    .font(.system(size: 18))
            }
            
            // 状态文本
            VStack(alignment: .leading, spacing: 4) {
                Text(bridge.isConnected ? "已连接" : "未连接")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Mac Relay")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 事件计数
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(bridge.eventHistory.count)")
                    .font(.system(size: 20, weight: .bold))
                
                Text("事件")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Current Event View
    
    private func currentEventView(_ event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 事件类型标题
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor(for: event.type))
                    .frame(width: 12, height: 12)
                
                Text(event.type.displayName)
                    .font(.system(size: 18, weight: .semibold))
                
                Spacer()
                
                Text(timeAgoString(from: event.receivedAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // 任务描述
            if let description = event.payload.taskDescription {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // 进度条
            if let progress = event.payload.progress {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.green)
                    
                    Text("\(Int(progress * 100))% 完成")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // 审批按钮
            if event.type == .approvalRequired {
                Button {
                    showApprovalSheet = true
                } label: {
                    Text("查看审批请求")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red)
                        )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
        )
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
    
    // MARK: - Waiting View
    
    private var waitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("等待 Claude Code...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Event History View
    
    private var eventHistoryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近事件")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            ForEach(bridge.eventHistory.suffix(5)) { event in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(for: event.type))
                        .frame(width: 8, height: 8)
                    
                    Text(event.type.displayName)
                        .font(.system(size: 12))
                    
                    Spacer()
                    
                    Text(timeAgoString(from: event.receivedAt))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // 连接/断开
            Button {
                if bridge.isConnected {
                    bridge.disconnect()
                } else {
                    bridge.connect()
                }
            } label: {
                Label(
                    bridge.isConnected ? "断开" : "连接",
                    systemImage: bridge.isConnected ? "wifi.slash" : "wifi"
                )
                .font(.system(size: 14))
            }
            .buttonStyle(.bordered)
            
            // Mock 模式
            Button {
                bridge.enableMockMode()
            } label: {
                Label("Mock", systemImage: "wand.and.stars")
                    .font(.system(size: 14))
            }
            .buttonStyle(.bordered)
        }
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

// MARK: - Activity Manager Protocol

/// ActivityManager 协议，用于版本兼容
protocol ActivityManagerProtocol: ObservableObject {
    func startActivity()
    func updateActivity(with event: ClaudeEvent)
    func endActivity()
}

// MARK: - Preview

// ContentView(bridge: WebSocketBridge())