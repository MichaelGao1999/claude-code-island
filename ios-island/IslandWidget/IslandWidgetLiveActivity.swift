import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Vibe Notch Dynamic Island Widget

/// Claude Code Island 的 Live Activity + Dynamic Island 实现
/// 使用共享的 ClaudeCodeActivityAttributes
struct IslandWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeCodeActivityAttributes.self) { context in
            // ── 锁屏视图（Always-On Display） ──
            LockScreenView(context: context)

        } dynamicIsland: { context in
            // ── 灵动岛视图 ──
            DynamicIsland {
                // 展开态
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeadingView(context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    expandedTrailingView(context)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedCenterView(context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedBottomView(context)
                }
            } compactLeading: {
                compactLeadingView(context)
            } compactTrailing: {
                compactTrailingView(context)
            } minimal: {
                minimalView(context)
            }
            .widgetURL(nil)
            .keylineTint(color(for: context.state.eventType))
        }
    }

    // MARK: - 紧凑态左侧

    private func compactLeadingView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        Image(systemName: iconName(for: context.state.eventType))
            .foregroundColor(color(for: context.state.eventType))
    }

    // MARK: - 紧凑态右侧

    private func compactTrailingView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        Text(eventTypeShort(context.state.eventType))
            .font(.caption2)
            .fontWeight(.bold)
    }

    // MARK: - 极简态

    private func minimalView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        Image(systemName: iconName(for: context.state.eventType))
            .foregroundColor(color(for: context.state.eventType))
    }

    // MARK: - 展开态-左侧

    private func expandedLeadingView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: iconName(for: context.state.eventType))
                .foregroundColor(color(for: context.state.eventType))
                .font(.title2)
            Text(context.state.eventType)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 展开态-中间

    private func expandedCenterView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        Text(context.state.taskDescription)
            .font(.caption)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    // MARK: - 展开态-右侧

    @ViewBuilder
    private func expandedTrailingView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        if let risk = context.state.riskLevel {
            RiskBadge(level: risk)
        }
    }

    // MARK: - 展开态-底部

    @ViewBuilder
    private func expandedBottomView(_ context: ActivityViewContext<ClaudeCodeActivityAttributes>) -> some View {
        if context.state.progress > 0 {
            ProgressView(value: context.state.progress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(color(for: context.state.eventType))
                .padding(.horizontal)
        }
    }

    // MARK: - Helpers

    private func iconName(for eventType: String) -> String {
        switch eventType {
        case "思考中", "thinking": return "brain.head.profile"
        case "编码中", "coding": return "chevron.left.forwardslash.chevron.right"
        case "等待中", "waiting": return "hourglass"
        case "需要审批", "approvalRequired": return "exclamationmark.shield"
        case "已批准", "approved": return "checkmark.shield"
        case "已拒绝", "rejected": return "xmark.shield"
        case "错误", "error": return "exclamationmark.triangle"
        case "已连接", "connected": return "antenna.radiowaves.left.and.right"
        case "已断开", "disconnected": return "antenna.radiowaves.left.and.right.slash"
        default: return "circle"
        }
    }

    private func color(for eventType: String) -> Color {
        switch eventType {
        case "思考中", "thinking": return .blue
        case "编码中", "coding": return .green
        case "等待中", "waiting": return .orange
        case "需要审批", "approvalRequired": return .red
        case "已批准", "approved": return .green
        case "已拒绝", "rejected": return .red
        case "错误", "error": return .red
        case "已连接", "connected": return .green
        case "已断开", "disconnected": return .gray
        default: return .gray
        }
    }

    private func eventTypeShort(_ type: String) -> String {
        switch type {
        case "思考中", "thinking": return "思考"
        case "编码中", "coding": return "编码"
        case "等待中", "waiting": return "等待"
        case "需要审批", "approvalRequired": return "审批"
        case "已连接", "connected": return "在线"
        case "已断开", "disconnected": return "离线"
        case "错误", "error": return "错误"
        case "已批准", "approved": return "通过"
        case "已拒绝", "rejected": return "拒绝"
        default: return "··"
        }
    }
}

// MARK: - 锁屏视图（Always-On Display）

struct LockScreenView: View {
    let context: ActivityViewContext<ClaudeCodeActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: context.state.eventType))
                        .foregroundColor(color(for: context.state.eventType))
                        .font(.system(size: 14))

                    Text(context.state.eventType)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Text(context.state.taskDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let risk = context.state.riskLevel {
                RiskBadge(level: risk)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func iconName(for eventType: String) -> String {
        switch eventType {
        case "思考中", "thinking": return "brain.head.profile"
        case "编码中", "coding": return "chevron.left.forwardslash.chevron.right"
        case "等待中", "waiting": return "hourglass"
        case "需要审批", "approvalRequired": return "exclamationmark.shield"
        case "已批准", "approved": return "checkmark.shield"
        case "已拒绝", "rejected": return "xmark.shield"
        case "错误", "error": return "exclamationmark.triangle"
        case "已连接", "connected": return "antenna.radiowaves.left.and.right"
        case "已断开", "disconnected": return "antenna.radiowaves.left.and.right.slash"
        default: return "circle"
        }
    }

    private func color(for eventType: String) -> Color {
        switch eventType {
        case "思考中", "thinking": return .blue
        case "编码中", "coding": return .green
        case "等待中", "waiting": return .orange
        case "需要审批", "approvalRequired": return .red
        case "已批准", "approved": return .green
        case "已拒绝", "rejected": return .red
        case "错误", "error": return .red
        case "已连接", "connected": return .green
        case "已断开", "disconnected": return .gray
        default: return .gray
        }
    }
}

// MARK: - 风险标识组件

struct RiskBadge: View {
    let level: String

    var body: some View {
        Text(level)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor)
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch level {
        case "低风险", "low": return .green
        case "中风险", "medium": return .orange
        case "高风险", "high": return .red
        case "严重风险", "critical": return .purple
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview("Notification", as: .content, using: previewAttributes) {
    IslandWidgetLiveActivity()
} contentStates: {
    ClaudeCodeActivityAttributes.ContentState(
        eventType: "思考中",
        taskDescription: "分析项目结构",
        progress: 0.65,
        riskLevel: nil
    )
    ClaudeCodeActivityAttributes.ContentState(
        eventType: "需要审批",
        taskDescription: "rm -rf /node_modules",
        progress: 0.0,
        riskLevel: "高风险"
    )
}

private let previewAttributes = ClaudeCodeActivityAttributes(
    connectionStatus: "已连接",
    startTime: Date()
)
