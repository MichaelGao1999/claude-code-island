import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Main App

@main
struct ClaudeCodeIslandApp: App {
    @StateObject private var webSocketBridge = WebSocketBridge()
    @StateObject private var liveActivityManager = LiveActivityManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        print("[App] ClaudeCodeIsland initializing...")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(webSocketBridge)
                .environmentObject(liveActivityManager)
                .onAppear {
                    setupApp()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    // MARK: - Setup

    private func setupApp() {
        print("[App] Setting up app...")
        connectWebSocket()
        checkLiveActivitySupport()
    }

    private func connectWebSocket() {
        print("[App] Connecting to WebSocket bridge...")
        webSocketBridge.connect()
    }

    private func checkLiveActivitySupport() {
        if #available(iOS 16.1, *) {
            let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            print("[App] Live Activities enabled: \(enabled)")
            if !enabled {
                print("[App] Warning: Live Activities are disabled in Settings")
            }
        } else {
            print("[App] Live Activities not supported on this iOS version")
        }
    }

    // MARK: - Scene Phase Handling

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            print("[App] Scene phase: active")
            if !webSocketBridge.isConnected {
                webSocketBridge.connect()
            }

        case .inactive:
            print("[App] Scene phase: inactive")

        case .background:
            print("[App] Scene phase: background")
            webSocketBridge.disconnect()

        @unknown default:
            break
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var webSocketBridge: WebSocketBridge
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var showingSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            statusCard
            RemoteApprovalView(
                webSocketBridge: webSocketBridge,
                liveActivityManager: liveActivityManager
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(webSocketBridge: webSocketBridge)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code Island")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                connectionIndicator
            }

            if let error = webSocketBridge.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var statusText: String {
        if webSocketBridge.isConnected {
            return "正在监听审批请求"
        } else {
            return "未连接到服务器"
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(webSocketBridge.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)

            Text(webSocketBridge.isConnected ? "在线" : "离线")
                .font(.caption)
                .foregroundColor(webSocketBridge.isConnected ? .green : .red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (webSocketBridge.isConnected ? Color.green : Color.red)
                .opacity(0.1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var webSocketBridge: WebSocketBridge
    @Environment(\.dismiss) private var dismiss
    @State private var host: String = "localhost"
    @State private var port: String = "8080"

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器配置") {
                    TextField("主机地址", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)

                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button("保存并重连") {
                        saveAndReconnect()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadCurrentSettings()
            }
        }
    }

    private func loadCurrentSettings() {
        // Settings would be loaded from UserDefaults in production
        // For now, keep default values
    }

    private func saveAndReconnect() {
        guard let portInt = Int(port) else { return }
        webSocketBridge.updateConnection(host: host, port: portInt)
        dismiss()
    }
}

// MARK: - Widget Trigger (Placeholder)

struct WidgetTrigger {
    static func startLiveActivity(task: String, status: String) {
        // This would be called from a Widget Extension
        // Currently placeholder for WidgetCenter integration
        print("[Widget] Would start Live Activity for: \(task)")
    }
}
