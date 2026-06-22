import SwiftUI

/// 远程审批视图
/// 在 iOS App 中显示审批请求，支持 Approve/Reject 操作
struct RemoteApprovalView: View {
    
    // MARK: - Properties
    
    let approvalInfo: ApprovalInfo
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @State private var showDetails: Bool = false
    @State private var isProcessing: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        #if os(iOS)
        NavigationStack {
            contentView
                .navigationTitle("审批请求")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showDetails.toggle()
                        } label: {
                            Image(systemName: showDetails ? "eye.slash" : "eye")
                        }
                    }
                }
        }
        #else
        contentView
        #endif
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                warningIcon
                approvalTitle
                commandSummaryCard
                riskLevelIndicator
                
                if showDetails {
                    commandDetailsSection
                }
                
                actionButtons
                sourceInfo
            }
            .padding()
        }
    }
    
    // MARK: - Warning Icon
    
    private var warningIcon: some View {
        ZStack {
            Circle()
                .fill(riskLevelColor(approvalInfo.riskLevel).opacity(0.2))
                .frame(width: 80, height: 80)
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(riskLevelColor(approvalInfo.riskLevel))
        }
    }
    
    // MARK: - Approval Title
    
    private var approvalTitle: some View {
        VStack(spacing: 8) {
            Text("需要审批")
                .font(.system(size: 24, weight: .bold))
            
            Text("Claude Code 正在请求执行高风险操作")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Command Summary Card
    
    private var commandSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("命令摘要")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(approvalInfo.commandSummary)
                .font(.system(size: 16, weight: .medium))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                )
        }
    }
    
    // MARK: - Risk Level Indicator
    
    private var riskLevelIndicator: some View {
        HStack(spacing: 12) {
            // 风险等级徽章
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 16))
                
                Text(approvalInfo.riskLevel.displayName)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(riskLevelColor(approvalInfo.riskLevel))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(riskLevelColor(approvalInfo.riskLevel).opacity(0.2))
            )
            
            Spacer()
            
            // 风险说明
            VStack(alignment: .trailing, spacing: 4) {
                Text(riskLevelTitle)
                    .font(.system(size: 12, weight: .medium))
                
                Text(riskLevelDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var riskLevelTitle: String {
        switch approvalInfo.riskLevel {
        case .low: return "低风险"
        case .medium: return "中等风险"
        case .high: return "高风险"
        case .critical: return "严重风险"
        }
    }
    
    private var riskLevelDescription: String {
        switch approvalInfo.riskLevel {
        case .low: return "操作通常安全"
        case .medium: return "建议仔细检查"
        case .high: return "可能导致数据丢失"
        case .critical: return "不可逆的后果"
        }
    }
    
    // MARK: - Command Details Section
    
    private var commandDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("完整命令")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // 原始命令
            Text(approvalInfo.rawCommand)
                .font(.system(size: 14, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                )
            
            // 详细说明
            Text(approvalInfo.commandDetails)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 批准按钮
            Button {
                isProcessing = true
                onApprove()
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    
                    Text("批准执行")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green)
                )
            }
            .disabled(isProcessing)
            
            // 拒绝按钮
            Button {
                isProcessing = true
                onReject()
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle.fill")
                    }
                    
                    Text("拒绝执行")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                )
            }
            .disabled(isProcessing)
        }
    }
    
    // MARK: - Source Info
    
    private var sourceInfo: some View {
        VStack(spacing: 8) {
            Divider()
            
            HStack {
                Image(systemName: "desktopcomputer")
                    .foregroundColor(.secondary)
                
                Text("来自 Mac")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Event ID: \(approvalInfo.eventId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
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

// RemoteApprovalView(
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