import SwiftUI
import ClockKit

/// 时间轴入口提供者
struct ComplicationProvider: TimelineProvider {
    typealias Entry = ComplicationEntry

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), status: "等待中", eventType: .thinking)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let entry = ComplicationEntry(
            date: Date(),
            status: SessionManager.shared.connectionStatus,
            eventType: SessionManager.shared.currentEvent?.type ?? .thinking
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(
            date: Date(),
            status: SessionManager.shared.connectionStatus,
            eventType: SessionManager.shared.currentEvent?.type ?? .thinking
        )
        // 30 分钟后刷新
        let nextUpdate = Date().addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let status: String
    let eventType: EventType
}

/// Complication 视图（在表盘上）
struct ComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName(for: entry.eventType))
                .font(.system(size: 14))

            Text(shortStatus)
                .font(.system(size: 10))
                .minimumScaleFactor(0.5)
        }
    }

    private var shortStatus: String {
        switch entry.eventType {
        case .thinking: return "思考"
        case .coding: return "编码"
        case .waiting: return "等待"
        case .approvalRequired: return "审批!"
        case .approved: return "通过"
        case .rejected: return "拒绝"
        case .error: return "错误"
        case .connected: return "在线"
        case .disconnected: return "离线"
        }
    }

    private func iconName(for type: EventType) -> String {
        switch type {
        case .thinking: return "brain.head.profile"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .waiting: return "hourglass"
        case .approvalRequired: return "exclamationmark.triangle"
        case .approved: return "checkmark.circle"
        case .rejected: return "xmark.circle"
        case .error: return "exclamationmark.circle"
        case .connected: return "wifi"
        case .disconnected: return "wifi.slash"
        }
    }
}