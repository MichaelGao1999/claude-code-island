import SwiftUI

// MARK: - ApprovalView

struct ApprovalView: View {
    @ObservedObject var manager: EventStreamManager
    @Binding var isPresented: Bool
    @State private var showInspectDetail = false

    private var approvalInfo: ApprovalInfo? {
        manager.pendingApproval
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            if showInspectDetail {
                inspectDetailSection
            } else {
                commandSummarySection
            }

            Divider()

            actionButtons
        }
        .frame(minWidth: 420, maxWidth: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(approvalInfo?.riskLevel == .critical ? 0.5 : 0), lineWidth: 2)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 20))
                .foregroundStyle(riskLevelColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("命令审批请求")
                    .font(.system(size: 15, weight: .semibold))

                Text(riskLevelText)
                    .font(.system(size: 12))
                    .foregroundStyle(riskLevelColor)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Command Summary Section

    private var commandSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 命令摘要
            VStack(alignment: .leading, spacing: 6) {
                Text("命令摘要")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(highlightedCommand)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }

            // 命令详情
            if let details = approvalInfo?.commandDetails, !details.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("详细说明")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(details)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                }
            }

            // 风险提示
            if approvalInfo?.riskLevel == .high || approvalInfo?.riskLevel == .critical {
                riskWarningBanner
            }
        }
        .padding(16)
    }

    // MARK: - Inspect Detail Section

    private var inspectDetailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("完整命令")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("返回") {
                    showInspectDetail = false
                }
                .font(.system(size: 11))
            }

            ScrollView {
                Text(approvalInfo?.rawCommand ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(16)
    }

    // MARK: - Risk Warning Banner

    private var riskWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("危险操作警告")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Text(warningMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Inspect 按钮
            Button(action: { showInspectDetail.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(showInspectDetail ? "收起详情" : "检查详情")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("i", modifiers: .command)

            Spacer()

            // Reject 按钮
            Button(action: { reject() }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("拒绝")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])

            // Approve 按钮
            Button(action: { approve() }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text("批准")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var riskLevelColor: Color {
        guard let level = approvalInfo?.riskLevel else { return .gray }
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .critical: return .purple
        }
    }

    private var riskLevelText: String {
        approvalInfo?.riskLevel.displayName ?? "未知风险"
    }

    private var warningMessage: String {
        guard let level = approvalInfo?.riskLevel else { return "" }
        switch level {
        case .high:
            return "此命令可能会修改或删除重要文件，请仔细检查后再操作"
        case .critical:
            return "极高风险操作！可能会对系统造成不可逆的损害"
        default:
            return ""
        }
    }

    private var highlightedCommand: AttributedString {
        guard let summary = approvalInfo?.commandSummary else {
            return AttributedString("")
        }

        var attributed = AttributedString(summary)

        // 高亮危险关键词
        let dangerKeywords = ["rm", "delete", "drop", "truncate", "shutdown", "reboot", "mkfs", "dd"]

        for keyword in dangerKeywords {
            if let range = attributed.range(of: keyword, options: .caseInsensitive) {
                attributed[range].foregroundColor = .red
                attributed[range].font = .system(size: 13, weight: .bold, design: .monospaced)
            }
        }

        return attributed
    }

    // MARK: - Actions

    private func approve() {
        guard let eventId = approvalInfo?.eventId else { return }
        manager.sendApproval(eventId: eventId, approved: true)
        dismiss()
    }

    private func reject() {
        guard let eventId = approvalInfo?.eventId else { return }
        manager.sendApproval(eventId: eventId, approved: false)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }
}

// MARK: - ApprovalView Representable

struct ApprovalViewRepresentable: UIViewControllerRepresentable {
    @ObservedObject var manager: EventStreamManager
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> ApprovalHostingController {
        ApprovalHostingController(manager: manager, isPresented: $isPresented)
    }

    func updateUIViewController(_ uiViewController: ApprovalHostingController, context: Context) {
        uiViewController.updateContent()
    }
}

class ApprovalHostingController: UIHostingController<ApprovalView> {
    private var isPresentedBinding: Binding<Bool>

    init(manager: EventStreamManager, isPresented: Binding<Bool>) {
        self.isPresentedBinding = isPresented
        super.init(rootView: ApprovalView(manager: manager, isPresented: isPresentedBinding))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateContent() {
        rootView = ApprovalView(manager: EventStreamManager.shared, isPresented: isPresentedBinding)
    }
}

// MARK: - Preview

#Preview {
    let manager = EventStreamManager.shared
    manager.addMockApprovalEvent()

    return ApprovalView(manager: manager, isPresented: .constant(true))
        .frame(width: 480, height: 320)
}
