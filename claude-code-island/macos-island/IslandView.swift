import SwiftUI

/// 菜单栏/灵动岛 UI 视图
/// 显示 Claude Code 当前状态、任务进度、审批请求
struct IslandView: View {
    
    // MARK: - Environment
    
    @ObservedObject var eventManager: EventStreamManager
    @State private var isExpanded: Bool = false
    @State private var showApprovalSheet: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Compact 模式（默认显示）
            compactView
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            
            // Expanded 模式（点击展开）
            if isExpanded {
                expandedView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 4)
        )
        .sheet(isPresented: $showApprovalSheet) {
            if let event = eventManager.currentEvent,
               event.type == .approvalRequired {
                ApprovalView(
                    approvalInfo: ApprovalInfo(from: event),
                    onApprove: {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: true
                        )
                        showApprovalSheet = false
                    },
                    onReject: {
                        eventManager.sendApprovalResponse(
                            eventId: ApprovalInfo(from: event).eventId,
                            approved: false
                        )
                        showApprovalSheet = false
                    }
                )
            }
        }
    }
    
    // MARK: - Compact View
    
    private var compactView: some View {
        HStack(spacing: 8) {
            // 状态图标
            statusIcon
            
            // 任务描述
            Text(currentTaskDescription)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // 连接状态指示
            connectionIndicator
            
            // 展开箭头
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Expanded View
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal, 12)
            
            // 当前事件详情
            if let event = eventManager.currentEvent {
                eventDetailView(event)
            } else {
                Text("等待事件...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
            }
            
            // 最近事件历史
            if !eventManager.eventHistory.isEmpty {
                recentEventsView
            }
            
            // 操作按钮
            actionButtons
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - Status Icon
    
    @ViewBuilder
    private var statusIcon: some View {
        let eventType = eventManager.currentEvent?.type ?? .disconnected
        
        ZStack {
            Circle()
                .fill(statusColor(for: eventType))
                .frame(width: 24, height: 24)
            
            Image(systemName: statusIconName(for: eventType))
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .animation(.easeInOut, value: eventType)
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
    
    private func statusIconName(for type: EventType) -> String {
        switch type {
        case .thinking: return "brain"
        case .coding: return "terminal"
        case .waiting: return "clock"
        case .approvalRequired: return "exclamationmark.triangle"
        case .approved: return "checkmark"
        case .rejected: return "xmark"
        case .error: return "bolt.trianglebadge.exclamationmark"
        case .connected: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "wifi.slash"
        }
    }
    
    // MARK: - Connection Indicator
    
    @ViewBuilder
    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(eventManager.isConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            
            Text(eventManager.isConnected ? "已连接" : "未连接")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Current Task Description
    
    private var currentTaskDescription: String {
        guard let event = eventManager.currentEvent else {
            return "等待 Claude Code..."
        }
        
        switch event.type {
        case .thinking:
            return event.payload.taskDescription ?? "思考中..."
        case .coding:
            return event.payload.taskDescription ?? "编码中..."
        case .waiting:
            return event.payload.taskDescription ?? "等待中..."
        case .approvalRequired:
            return "需要审批: \(event.payload.commandSummary ?? "未知命令")"
        case .approved:
            return "已批准"
        case .rejected:
            return "已拒绝"
        case .error:
            return event.payload.message ?? "发生错误"
        case .connected:
            return "已连接"
        case .disconnected:
            return "已断开"
        }
    }
    
    // MARK: - Event Detail View
    
    private func eventDetailView(_ event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 事件类型
            HStack {
                Text(event.type.displayName)
                    .font(.system(size: 13, weight: .semibold))
                
                Spacer()
                
                Text(timeAgoString(from: event.receivedAt))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 事件消息
            if let message = event.payload.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // 进度条（编码状态）
            if event.type == .coding,
               let progress = event.payload.progress {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.green)
                
                Text("\(Int(progress * 100))% 完成")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // 风险等级（审批状态）
            if event.type == .approvalRequired,
               let riskLevel = event.payload.riskLevel {
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .foregroundColor(riskLevelColor(riskLevel))
                    
                    Text(riskLevel.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(riskLevelColor(riskLevel))
                }
            }
        }
        .padding(.horizontal, 12)
    }
    
    private func riskLevelColor(_ level: RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
    
    // MARK: - Recent Events View
    
    private var recentEventsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近事件")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
            
            ForEach(eventManager.eventHistory.suffix(3)) { event in
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: event.type))
                        .frame(width: 8, height: 8)
                    
                    Text(event.type.displayName)
                        .font(.system(size: 10))
                    
                    Spacer()
                    
                    Text(timeAgoString(from: event.receivedAt))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // 连接/断开按钮
            Button {
                if eventManager.isConnected {
                    eventManager.disconnect()
                } else {
                    eventManager.connect()
                }
            } label: {
                Text(eventManager.isConnected ? "断开" : "连接")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            
            // 审批按钮（仅审批状态显示）
            if eventManager.currentEvent?.type == .approvalRequired {
                Button {
                    showApprovalSheet = true
                } label: {
                    Text("审批")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Mock 模式按钮
            Button {
                eventManager.enableMockMode()
            } label: {
                Text("Mock")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
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

// MARK: - Preview

// let manager = EventStreamManager()
// manager.enableMockMode()
// return IslandView(eventManager: manager)
//     .padding()