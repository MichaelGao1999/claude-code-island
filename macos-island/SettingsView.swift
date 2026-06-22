import SwiftUI

// MARK: - Settings View

/// 设置视图
struct SettingsView: View {
    
    @ObservedObject var eventManager: EventStreamManager
    @AppStorage("serverURL") private var serverURL: String = "ws://localhost:8080/events"
    @AppStorage("autoConnect") private var autoConnect: Bool = true
    @AppStorage("showNotifications") private var showNotifications: Bool = true
    
    var body: some View {
        Form {
            Section("连接设置") {
                LabeledContent("服务器地址") {
                    TextField("WebSocket URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                
                Toggle("自动连接", isOn: $autoConnect)
                Toggle("显示通知", isOn: $showNotifications)
            }
            
            Section("状态") {
                LabeledContent("连接状态") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(eventManager.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        
                        Text(eventManager.isConnected ? "已连接" : "未连接")
                    }
                }
                
                LabeledContent("事件历史") {
                    Text("\(eventManager.eventHistory.count) 条")
                }
                
                if let error = eventManager.connectionError {
                    LabeledContent("错误信息") {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Section("操作") {
                Button("清除历史记录") {
                    eventManager.eventHistory.removeAll()
                }
                
                Button("重新连接") {
                    eventManager.disconnect()
                    eventManager.connect()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}