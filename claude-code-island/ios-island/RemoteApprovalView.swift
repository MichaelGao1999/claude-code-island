import SwiftUI
import WidgetKit

// MARK: - Risk Level

enum RiskLevel: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var color: Color {
        switch self {
        case .low:
            return .green
        case .medium:
            return .yellow
        case .high:
            return .orange
        case .critical:
            return .red
        }
    }

    var label: String {
        switch self {
        case .low:
            return "低风险"
        case .medium:
            return "中等风险"
        case .high:
            return "高风险"
        case .critical:
            return "极高风险"
        }
    }

    var icon: String {
        switch self {
        case .low:
            return "shield.checkered"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.octagon"
        case .critical:
            return "xmark.octagon.fill"
        }
    }

    static func from(string: String?) -> RiskLevel {
        guard let string = string?.lowercased() else { return .low }
        return RiskLevel(rawValue: string) ?? .low
    }
}

// MARK: - Remote Approval View

struct RemoteApprovalView: View {
    @ObservedObject var webSocketBridge: WebSocketBridge
    @ObservedObject var liveActivityManager: LiveActivityManager
    @State private var showingApprovalSheet: Bool = false
    @State private var pendingEvent: ClaudeEvent?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    connectionStatusCard

                    if let event = webSocketBridge.currentEvent {
                        approvalCard(for: event)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("远程审批")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Connection Status Card

    private var connectionStatusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(webSocketBridge.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            Text(webSocketBridge.isConnected ? "已连接" : "未连接")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            if !webSocketBridge.isConnected {
                Button("重连") {
                    webSocketBridge.connect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("暂无待审批命令")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("当有需要审批的命令时，将在此显示")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Approval Card

    @ViewBuilder
    private func approvalCard(for event: ClaudeEvent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.accentColor)

                Text("命令审批请求")
                    .font(.headline)

                Spacer()

                Text(event.payload.riskLevel ?? "unknown")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RiskLevel.from(string: event.payload.riskLevel).color.opacity(0.2))
                    .foregroundColor(RiskLevel.from(string: event.payload.riskLevel).color)
                    .cornerRadius(6)
            }

            Divider()

            // Command Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("命令摘要")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(event.payload.summary ?? event.payload.command ?? "无描述")
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            }

            // Risk Warning
            if RiskLevel.from(string: event.payload.riskLevel) == .high ||
               RiskLevel.from(string: event.payload.riskLevel) == .critical {
                riskWarningView(for: RiskLevel.from(string: event.payload.riskLevel))
            }

            // Description
            if let description = event.payload.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("详细说明")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                }
            }

            Divider()

            // Action Buttons
            HStack(spacing: 16) {
                Button(action: {
                    handleApproval(event: event, approved: false)
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("拒绝")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }

                Button(action: {
                    handleApproval(event: event, approved: true)
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("批准")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Risk Warning View

    private func riskWarningView(for riskLevel: RiskLevel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: riskLevel.icon)
                .font(.title2)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("⚠️ \(riskLevel.label)警告")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("此操作可能会对系统造成影响，请仔细确认")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [riskLevel.color, riskLevel.color.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }

    // MARK: - Handle Approval

    private func handleApproval(event: ClaudeEvent, approved: Bool) {
        webSocketBridge.sendApproval(eventId: event.id, approved: approved)

        let status = approved ? "Approved" : "Rejected"
        liveActivityManager.updateActivity(status: status, progress: approved ? 1.0 : 0.0)

        if approved {
            liveActivityManager.updateActivity(status: "执行中", progress: 0.5)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                liveActivityManager.endActivity()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RemoteApprovalView(
        webSocketBridge: WebSocketBridge(),
        liveActivityManager: LiveActivityManager()
    )
}
