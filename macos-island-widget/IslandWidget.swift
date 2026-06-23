import SwiftUI
import WidgetKit

@main
struct IslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        IslandStatusWidget()
    }
}

// MARK: - Status Widget

struct IslandStatusWidget: Widget {
    let kind: String = "IslandStatusWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Code Island")
        .description("显示 Claude Code 运行状态")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline Provider

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), state: nil)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let state = loadCurrentState()
        let entry = StatusEntry(date: Date(), state: state)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let state = loadCurrentState()
        let entry = StatusEntry(date: Date(), state: state)
        
        // 每分钟更新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    private func loadCurrentState() -> ClaudeIslandActivityState? {
        // 从 App Groups UserDefaults 读取状态
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupIdentifier),
              let data = defaults.data(forKey: SharedKeys.activityState),
              let state = try? JSONDecoder().decode(ClaudeIslandActivityState.self, from: data) else {
            return nil
        }
        return state
    }
}

// MARK: - Timeline Entry

struct StatusEntry: TimelineEntry {
    let date: Date
    let state: ClaudeIslandActivityState?
}

// MARK: - Widget View

struct StatusWidgetView: View {
    let entry: StatusEntry
    
    var body: some View {
        if let state = entry.state {
            activeView(state)
        } else {
            inactiveView
        }
    }
    
    private func activeView(_ state: ClaudeIslandActivityState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.blue)
                    .font(.headline)
                
                Text("Claude Code")
                    .font(.headline)
                
                Spacer()
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            
            Divider()
            
            // 状态信息
            HStack {
                Image(systemName: iconName(for: state.eventType))
                    .font(.title2)
                    .foregroundColor(iconColor(for: state.eventType))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.eventType)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if !state.taskDescription.isEmpty {
                        Text(state.taskDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // 进度
                if state.progress > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(state.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ProgressView(value: state.progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(width: 50)
                    }
                }
            }
            
            // 风险等级
            if let risk = state.riskLevel {
                HStack {
                    Text(risk)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(riskColor(risk).opacity(0.2))
                        .foregroundColor(riskColor(risk))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Text(elapsedTime(since: state.startTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    private var inactiveView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundColor(.gray)
            
            Text("Claude Code Island")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("未连接")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Helpers
    
    private func iconName(for eventType: String) -> String {
        switch eventType {
        case "思考中": return "brain.head.profile"
        case "编码中": return "chevron.left.forwardslash.chevron.right"
        case "等待中": return "hourglass"
        case "需要审批": return "exclamationmark.triangle.fill"
        case "已批准": return "checkmark.circle.fill"
        case "已拒绝": return "xmark.circle.fill"
        case "错误": return "exclamationmark.circle.fill"
        default: return "antenna.radiowaves.left.and.right"
        }
    }
    
    private func iconColor(for eventType: String) -> Color {
        switch eventType {
        case "思考中": return .blue
        case "编码中", "已批准": return .green
        case "等待中": return .orange
        case "需要审批", "错误", "已拒绝": return .red
        default: return .gray
        }
    }
    
    private func riskColor(_ risk: String) -> Color {
        switch risk {
        case "高风险", "严重风险": return .red
        case "中风险": return .orange
        default: return .gray
        }
    }
    
    private func elapsedTime(since startDate: Date) -> String {
        let interval = Date().timeIntervalSince(startDate)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
