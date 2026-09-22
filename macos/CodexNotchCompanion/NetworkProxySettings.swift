import Foundation

enum NetworkProxyMode: String, Codable, Equatable, CaseIterable, Identifiable {
    case system
    case environment
    case custom
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "系统代理"
        case .environment: return "环境变量"
        case .custom: return "自定义"
        case .none: return "直连"
        }
    }
}

struct AppNetworkSettings: Codable, Equatable {
    var proxyMode: NetworkProxyMode
    var proxyURL: String?
    var enableAiUsageFallback: Bool
    /// Absolute path to a local daily-usage CSV. Nil disables CSV ingest.
    var localDailyCSVPath: String?
    /// Base URL for local usage HTTP feed, e.g. http://127.0.0.1:8765. Nil disables feed.
    var localUsageBaseURL: String?

    static let suggestedProxyURL = "http://127.0.0.1:16180"

    init(
        proxyMode: NetworkProxyMode,
        proxyURL: String? = nil,
        enableAiUsageFallback: Bool = true,
        localDailyCSVPath: String? = nil,
        localUsageBaseURL: String? = nil
    ) {
        self.proxyMode = proxyMode
        self.proxyURL = proxyURL
        self.enableAiUsageFallback = enableAiUsageFallback
        self.localDailyCSVPath = localDailyCSVPath
        self.localUsageBaseURL = localUsageBaseURL
    }

    static let `default` = AppNetworkSettings(
        proxyMode: .system,
        proxyURL: nil,
        enableAiUsageFallback: true,
        localDailyCSVPath: nil,
        localUsageBaseURL: nil
    )

    static var settingsURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return root.appending(path: "CodexNotchCompanion/settings.json")
    }

    static func load(from url: URL = settingsURL) -> AppNetworkSettings {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppNetworkSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save(to url: URL = settingsURL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var resolvedLocalUsageAPIURL: URL? {
        guard let base = localUsageBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty else { return nil }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: "\(trimmed)/api/usage")
    }

    var resolvedLocalUsageWebURL: String? {
        guard let base = localUsageBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !base.isEmpty else { return nil }
        return base.hasSuffix("/") ? base : base + "/"
    }
}

enum NetworkProxyFactory {
    /// `nil` keeps URLSession's system proxy behavior.
    /// An empty dictionary disables proxies.
    static func connectionProxyDictionary(
        for settings: AppNetworkSettings,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [AnyHashable: Any]? {
        switch settings.proxyMode {
        case .system:
            return nil
        case .none:
            return [:]
        case .environment:
            let raw = environment["ALL_PROXY"]
                ?? environment["all_proxy"]
                ?? environment["HTTPS_PROXY"]
                ?? environment["https_proxy"]
                ?? environment["HTTP_PROXY"]
                ?? environment["http_proxy"]
            guard let raw, let dictionary = proxyDictionary(from: raw) else { return nil }
            return dictionary
        case .custom:
            guard let raw = settings.proxyURL, let dictionary = proxyDictionary(from: raw) else {
                return nil
            }
            return dictionary
        }
    }

    static func proxyDictionary(from raw: String) -> [AnyHashable: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized: String
        if trimmed.contains("://") {
            normalized = trimmed
        } else if trimmed.hasPrefix("socks") {
            normalized = trimmed
        } else {
            normalized = "http://\(trimmed)"
        }

        guard let url = URL(string: normalized), let host = url.host, !host.isEmpty else { return nil }
        let port = url.port ?? defaultPort(for: url.scheme)

        let scheme = (url.scheme ?? "http").lowercased()
        if scheme.hasPrefix("socks") {
            return [
                "SOCKSEnable": NSNumber(value: 1),
                "SOCKSProxy": host,
                "SOCKSPort": NSNumber(value: port),
            ]
        }

        return [
            "HTTPEnable": NSNumber(value: 1),
            "HTTPProxy": host,
            "HTTPPort": NSNumber(value: port),
            "HTTPSEnable": NSNumber(value: 1),
            "HTTPSProxy": host,
            "HTTPSPort": NSNumber(value: port),
        ]
    }

    private static func defaultPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https": return 443
        case "socks", "socks5", "socks5h": return 1080
        default: return 80
        }
    }

    static func makeSession(settings: AppNetworkSettings) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        if let proxy = connectionProxyDictionary(for: settings) {
            configuration.connectionProxyDictionary = proxy
        }
        return URLSession(configuration: configuration)
    }
}
