import SwiftUI

// MARK: - IslandView

struct IslandView: View {
    @ObservedObject var manager: EventStreamManager

    var body: some View {
        VStack(spacing: 0) {
            compactView
        }
        .frame(minWidth: 300, maxWidth: 360)
    }

    // MARK: - Compact View (灵动岛压缩状态)

    private var compactView: some View {
        HStack(spacing: 12) {
            // 状态指示器
            statusIndicator

            // 任务描述
            if let currentEvent = manager.currentEvent,
               let description = currentEvent.payload.taskDescription ?? currentEvent.payload.message {
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(statusColor)
            } else {
                Text("等待 Claude Code...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 连接状态
            connectionIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Expanded View (灵动岛展开状态)

    var expandedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部：状态和连接
            headerSection

            Divider()

            // 当前任务
            if let currentEvent = manager.currentEvent {
                currentTaskSection(event: currentEvent)
            }

            // 进度条（如有）
            if let progress = manager.currentEvent?.payload.progress {
                progressSection(progress: progress)
            }

            // 最近事件
            recentEventsSection

            Spacer()

            // 操作按钮
            actionButtons
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 280)
    }

    // MARK: - Subviews

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay {
                if manager.currentEvent?.type == .thinking {
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 2)
                        .frame(width: 18, height: 18)
                        .modifier(PulseAnimation())
                }
            }
    }

    private var connectionIndicator: some View {
        Group {
            switch manager.connectionState {
            case .connected:
                Image(systemName: "wifi")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            case .connecting, .reconnecting:
                ProgressView()
                    .scaleEffect(0.5)
            case .disconnected:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Claude Island")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(manager.currentEvent?.type.displayName ?? "空闲")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private func currentTaskSection(event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前任务")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let description = event.payload.taskDescription {
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
            } else if let message = event.payload.message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressSection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("进度")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            ProgressView(value: progress)
                .tint(statusColor)
        }
    }

    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近活动")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(manager.events.prefix(5)) { event in
                        eventRow(event: event)
                    }
                }
            }
            .frame(maxHeight: 100)
        }
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

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { manager.clearEvents() }) {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            Spacer()

            if manager.pendingApproval != nil {
                Button(action: { manager.mockReject() }) {
                    Text("拒绝")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)

                Button(action: { manager.mockApprove() }) {
                    Text("批准")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .opacity(isAnimating ? 0.0 : 0.8)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Preview

#Preview {
    IslandView(manager: EventStreamManager.shared)
        .frame(width: 360, height: 300)
}
