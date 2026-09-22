import SwiftUI

struct AppSettingsView: View {
    @ObservedObject var store: UsageStore

    @State private var proxyMode: NetworkProxyMode
    @State private var proxyURL: String
    @State private var enableAiUsageFallback: Bool
    @State private var localDailyCSVPath: String
    @State private var localUsageBaseURL: String
    @State private var statusMessage: String?

    init(store: UsageStore) {
        self.store = store
        let settings = store.networkSettings
        _proxyMode = State(initialValue: settings.proxyMode)
        _proxyURL = State(initialValue: settings.proxyURL ?? AppNetworkSettings.suggestedProxyURL)
        _enableAiUsageFallback = State(initialValue: settings.enableAiUsageFallback)
        _localDailyCSVPath = State(initialValue: settings.localDailyCSVPath ?? "")
        _localUsageBaseURL = State(initialValue: settings.localUsageBaseURL ?? "")
    }

    var body: some View {
        Form {
            Section {
                Picker("模式", selection: $proxyMode) {
                    ForEach(NetworkProxyMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                if proxyMode == .custom {
                    TextField("代理地址", text: $proxyURL)
                        .textFieldStyle(.roundedBorder)
                    Text("推荐 HTTP：\(AppNetworkSettings.suggestedProxyURL)\n也可 SOCKS5：socks5://127.0.0.1:12335")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if proxyMode == .environment {
                    Text("从启动台打开时通常读不到 shell 环境变量，更建议用自定义。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("本地 aiusage 回退", isOn: $enableAiUsageFallback)
            } header: {
                Text("网络代理")
            }

            Section {
                TextField("日汇总 CSV 路径", text: $localDailyCSVPath)
                    .textFieldStyle(.roundedBorder)
                TextField("本地上报 Base URL", text: $localUsageBaseURL)
                    .textFieldStyle(.roundedBorder)
                Text("留空则关闭对应数据源。支持 ~ 路径。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("本地上报")
            }

            Section {
                Picker("进度条样式", selection: Binding(
                    get: { store.progressStyle },
                    set: { store.progressStyle = $0 }
                )) {
                    ForEach(ProgressBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外观")
            } footer: {
                Text("影响刘海轮廓进度与展开页进度条样式。")
            }

            Button("保存并刷新额度") {
                saveNetwork()
            }
            .keyboardShortcut(.defaultAction)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 460, height: 460)
        .onAppear {
            let settings = store.networkSettings
            proxyMode = settings.proxyMode
            proxyURL = settings.proxyURL ?? AppNetworkSettings.suggestedProxyURL
            enableAiUsageFallback = settings.enableAiUsageFallback
            localDailyCSVPath = settings.localDailyCSVPath ?? ""
            localUsageBaseURL = settings.localUsageBaseURL ?? ""
        }
    }

    private func saveNetwork() {
        let trimmedProxy = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCSV = localDailyCSVPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFeed = localUsageBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = AppNetworkSettings(
            proxyMode: proxyMode,
            proxyURL: proxyMode == .custom ? (trimmedProxy.isEmpty ? nil : trimmedProxy) : nil,
            enableAiUsageFallback: enableAiUsageFallback,
            localDailyCSVPath: trimmedCSV.isEmpty ? nil : trimmedCSV,
            localUsageBaseURL: trimmedFeed.isEmpty ? nil : trimmedFeed
        )
        store.updateNetworkSettings(settings)
        statusMessage = "已保存，正在刷新额度…"
    }
}
