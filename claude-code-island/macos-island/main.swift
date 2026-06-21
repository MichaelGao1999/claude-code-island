import SwiftUI
import AppKit

// MARK: - IslandApp

@main
struct IslandApp: App {
    @StateObject private var eventManager = EventStreamManager.shared
    @State private var showingApproval = false
    @State private var isExpanded = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                manager: eventManager,
                showingApproval: $showingApproval,
                isExpanded: $isExpanded
            )
        } label: {
            MenuBarLabel(manager: eventManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - MenuBarLabel

struct MenuBarLabel: View {
    @ObservedObject var manager: EventStreamManager

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text("Claude Island")
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var statusColor: Color {
        guard let eventType = manager.currentEvent?.type else {
            return .gray
        }
        switch eventType {
        case .thinking: return .blue
        case .coding: return .green
        case .waiting: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .error: return .red
        case .connected: return .green
        case .disconnected: return .gray
        case .approvalRequired: return .orange
        }
    }
}

// MARK: - MenuBarContent

struct MenuBarContent: View {
    @ObservedObject var manager: EventStreamManager
    @Binding var showingApproval: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            statusBar

            Divider()

            // 主要内容
            if isExpanded {
                expandedContent
            } else {
                compactContent
            }

            Divider()

            // 底部操作
            footerActions
        }
        .frame(minWidth: 320, maxWidth: 400)
        .sheet(isPresented: $showingApproval) {
            ApprovalView(manager: manager, isPresented: $showingApproval)
                .frame(minWidth: 420, minHeight: 300)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Image(systemName: connectionIcon)
                .font(.system(size: 12))
                .foregroundStyle(connectionColor)

            Text(connectionText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text(manager.currentEvent?.type.displayName ?? "空闲")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor)

            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Compact Content

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let currentEvent = manager.currentEvent,
               let description = currentEvent.payload.taskDescription ?? currentEvent.payload.message {
                Text(description)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            } else {
                Text("等待 Claude Code 活动...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }

            // 进度条
            if let progress = manager.currentEvent?.payload.progress {
                ProgressView(value: progress)
                    .tint(statusColor)
                    .padding(.horizontal, 12)
            }

            // 审批提示
            if manager.pendingApproval != nil {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)

                    Text("有待审批的命令")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("查看") {
                        showingApproval = true
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 当前任务
            if let currentEvent = manager.currentEvent {
                VStack(alignment: .leading, spacing: 6) {
                    Text("当前任务")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if let description = currentEvent.payload.taskDescription {
                        Text(description)
                            .font(.system(size: 13))
                    }

                    if let message = currentEvent.payload.message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
            }

            // 进度
            if let progress = manager.currentEvent?.payload.progress {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("进度")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                    }

                    ProgressView(value: progress)
                        .tint(statusColor)
                }
                .padding(.horizontal, 12)
            }

            // 最近事件
            VStack(alignment: .leading, spacing: 6) {
                Text("最近活动")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(manager.events.prefix(8)) { event in
                            eventRow(event: event)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .padding(.horizontal, 12)

            // 审批区域
            if let approval = manager.pendingApproval {
                approvalSection(approval: approval)
            }
        }
        .padding(.vertical, 12)
    }

    private func eventRow(event: ClaudeEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorForEventType(event.type))
                .frame(width: 6, height: 6)

            Text(event.type.displayName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Text(event.receivedAt, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func approvalSection(approval: ApprovalInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(riskColor(for: approval.riskLevel))

                Text("待审批: \(approval.commandSummary)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Button("批准") {
                    manager.sendApproval(eventId: approval.eventId, approved: true)
                }
                .font(.system(size: 11))
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("拒绝") {
                    manager.sendApproval(eventId: approval.eventId, approved: false)
                }
                .font(.system(size: 11))
                .foregroundStyle(.red)
            }

            Button("查看详情...") {
                showingApproval = true
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(riskColor(for: approval.riskLevel).opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 12)
    }

    // MARK: - Footer Actions

    private var footerActions: some View {
        HStack {
            Button(action: { manager.clearEvents() }) {
                Label("清空历史", systemImage: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            // 连接状态
            connectionStatusButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionStatusButton: some View {
        Button(action: toggleConnection) {
            HStack(spacing: 4) {
                Image(systemName: manager.connectionState.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 10))

                Text(manager.connectionState.isConnected ? "断开" : "连接")
                    .font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(manager.connectionState.isConnected ? .red : .green)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        guard let eventType = manager.currentEvent?.type else {
            return .gray
        }
        return colorForEventType(eventType)
    }

    private func colorForEventType(_ type: EventType) -> Color {
        switch type {
        case .thinking: return .blue
        case .coding: return .green
        case .waiting: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .error: return .red
        case .connected: return .green
        case .disconnected: return .gray
        case .approvalRequired: return .orange
        }
    }

    private func riskColor(for level: RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }

    private var connectionIcon: String {
        switch manager.connectionState {
        case .connected: return "wifi"
        case .connecting, .reconnecting: return "wifi.exclamationmark"
        case .disconnected: return "wifi.slash"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var connectionColor: Color {
        switch manager.connectionState {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected, .failed: return .red
        }
    }

    private var connectionText: String {
        switch manager.connectionState {
        case .connected: return "已连接"
        case .connecting: return "连接中..."
        case .reconnecting(let attempt): return "重连中 (\(attempt)/3)"
        case .disconnected: return "未连接"
        case .failed: return "连接失败"
        }
    }

    private func toggleConnection() {
        if manager.connectionState.isConnected {
            manager.disconnect()
        } else {
            // 默认连接本地 Claude Code
            if let url = URL(string: "ws://localhost:8080/events") {
                manager.connect(url: url)
            }
        }
    }
}

// MARK: - Fallback for older macOS

struct IslandAppFallback: App {
    @StateObject private var eventManager = EventStreamManager.shared
    @State private var showingApproval = false
    @State private var statusItem: NSStatusItem?

    var body: some Scene {
        WindowGroup {
            IslandView(manager: eventManager)
                .frame(minWidth: 320, maxHeight: 400)
        }
    }

    init() {
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "puzzlepiece.extension.fill", accessibilityDescription: "Claude Island")
        }
    }
}
