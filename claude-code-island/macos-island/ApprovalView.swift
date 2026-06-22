import SwiftUI

/// 审批弹窗视图
/// 显示需要用户确认的高风险操作，支持键盘快捷键和点击操作
struct ApprovalView: View {
    
    // MARK: - Properties
    
    let approvalInfo: ApprovalInfo
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @State private var isInspecting: Bool = false
    @FocusState private var isFocused: Bool
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题
            headerView
            
            // 命令摘要
            commandSummaryView
            
            // 风险等级
            riskLevelView
            
            // 命令详情（可展开）
            if isInspecting {
                commandDetailsView
            }
            
            // 操作按钮
            actionButtons
            
            // 键盘快捷键提示
            keyboardHints
        }
        .padding(24)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 8)
        )
        .focused($isFocused)
        .onKeyPress(.return) {
            onApprove()
            return .handled
        }
        .onKeyPress(.escape) {
            onReject()
            return .handled
        }
        .onKeyPress("i") {
            isInspecting.toggle()
            return .handled
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // 警告图标
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(riskLevelColor(approvalInfo.riskLevel))
            
            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("需要审批")
                    .font(.system(size: 18, weight: .bold))
                
                Text("Claude Code 正在请求执行高风险操作")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Command Summary View
    
    private var commandSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("命令摘要")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(approvalInfo.commandSummary)
                .font(.system(size: 14, weight: .medium))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
    }
    
    // MARK: - Risk Level View
    
    private var riskLevelView: some View {
        HStack(spacing: 8) {
            // 风险等级标签
            HStack(spacing: 4) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 14))
                
                Text(approvalInfo.riskLevel.displayName)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(riskLevelColor(approvalInfo.riskLevel))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(riskLevelColor(approvalInfo.riskLevel).opacity(0.2))
            )
            
            Spacer()
            
            // 风险描述
            Text(riskDescription)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private var riskDescription: String {
        switch approvalInfo.riskLevel {
        case .low:
            return "低风险操作，通常安全"
        case .medium:
            return "中等风险，建议检查"
        case .high:
            return "高风险操作，请仔细审查"
        case .critical:
            return "严重风险，可能导致不可逆后果"
        }
    }
    
    // MARK: - Command Details View
    
    private var commandDetailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("完整命令")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(approvalInfo.rawCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
            .frame(maxHeight: 120)
            
            Text(approvalInfo.commandDetails)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // 检查按钮
            Button {
                isInspecting.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isInspecting ? "eye.slash" : "eye")
                    Text(isInspecting ? "隐藏详情" : "检查详情")
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            // 拒绝按钮
            Button {
                onReject()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("拒绝")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            
            // 批准按钮
            Button {
                onApprove()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("批准")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Keyboard Hints
    
    private var keyboardHints: some View {
        HStack(spacing: 16) {
            keyboardHint("Enter", "批准")
            keyboardHint("Esc", "拒绝")
            keyboardHint("I", "检查")
            
            Spacer()
            
            Text("Event ID: \(approvalInfo.eventId)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
    
    private func keyboardHint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                )
            
            Text(action)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func riskLevelColor(_ level: RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }
}

// MARK: - Preview

// ApprovalView(
//     approvalInfo: ApprovalInfo(
//         eventId: "evt_abc123",
//         commandSummary: "rm -rf ./node_modules",
//         commandDetails: "删除整个 node_modules 目录及其所有依赖包",
//         riskLevel: .high,
//         rawCommand: "rm -rf ./node_modules"
//     ),
//     onApprove: { print("Approved") },
//     onReject: { print("Rejected") }
// )