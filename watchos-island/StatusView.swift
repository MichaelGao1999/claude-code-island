import SwiftUI

/// 手表主视图 — 显示当前 Claude Code 状态
struct StatusView: View {
    @ObservedObject var session = SessionManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 连接状态指示器
                connectionIndicator

                // 当前事件
                if let event = session.currentEvent {
                    eventCard(event)
                } else {
                    waitingView
                }

                // 连接状态文本
                Text(session.connectionStatus)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    // MARK: - Connection Indicator

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isReachable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(session.isReachable ? "已连接 iPhone" : "iPhone 未连接")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Event Card

    private func eventCard(_ event: ClaudeEvent) -> some View {
        VStack(spacing: 8) {
            // 事件类型
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(for: event.type))
                    .frame(width: 10, height: 10)

                Text(event.type.displayName)
                    .font(.headline)

                Spacer()
            }

            // 任务描述
            if let desc = event.payload.taskDescription {
                Text(desc)
                    .font(.body)
                    .lineLimit(3)
            }

            // 进度
            if let progress = event.payload.progress {
                ProgressView(value: progress, total: 1.0)
                    .tint(.green)

                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // 审批事件（手表上只显示警告，不处理审批）
            if event.type == .approvalRequired {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("请在 iPhone 上处理")
                        .font(.caption2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(16)
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

    private var waitingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)
            Text("等待事件...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(16)
    }
}