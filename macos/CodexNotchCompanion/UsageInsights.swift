import Foundation

/// Visual style for the collapsed notch progress stroke.
enum ProgressBarStyle: Int, CaseIterable, Identifiable {
    case classic = 0
    case pacman = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .classic: return "经典"
        case .pacman: return "吃豆人"
        }
    }

    /// Shader selector value.
    var shaderValue: Float { Float(rawValue) }

    private static let defaultsKey = "progressBarStyle"

    static func load(defaults: UserDefaults = .standard) -> ProgressBarStyle {
        guard defaults.object(forKey: defaultsKey) != nil else { return .pacman }
        return ProgressBarStyle(rawValue: defaults.integer(forKey: defaultsKey)) ?? .pacman
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Aggregated aiusage `/api/summary` payload (local read-only stats).
struct AiUsageSummary: Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var thinkingTokens: Int
    var totalTokens: Int
    var totalCost: Double
    var totalSessions: Int
    var activeDays: Int

    static let empty = AiUsageSummary(
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        thinkingTokens: 0,
        totalTokens: 0,
        totalCost: 0,
        totalSessions: 0,
        activeDays: 0
    )

    var hasData: Bool { totalTokens > 0 || totalSessions > 0 }

    /// Non-cache token breakdown used for the composition chart.
    var compositionSlices: [(label: String, value: Int)] {
        [
            ("输入", inputTokens),
            ("输出", outputTokens),
            ("缓存", cacheReadTokens),
            ("思考", thinkingTokens),
        ]
    }

    static func decode(_ data: Data) throws -> AiUsageSummary {
        try JSONDecoder().decode(AiUsageSummary.self, from: data)
    }
}

extension AiUsageSummary: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0 }
        func dbl(_ key: CodingKeys) -> Double { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? 0 }
        inputTokens = int(.inputTokens)
        outputTokens = int(.outputTokens)
        cacheReadTokens = int(.cacheReadTokens)
        cacheWriteTokens = int(.cacheWriteTokens)
        thinkingTokens = int(.thinkingTokens)
        totalTokens = int(.totalTokens)
        totalCost = dbl(.totalCost)
        totalSessions = int(.totalSessions)
        activeDays = int(.activeDays)
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens
        case thinkingTokens, totalTokens, totalCost, totalSessions, activeDays
    }
}

/// One aggregated day from a configured local usage `/api/usage` feed.
struct LocalDailyPoint: Equatable, Identifiable {
    let date: String
    let totalTokens: Int
    let turns: Int

    var id: String { date }
}

enum LocalUsageHistory {
    /// Parse `/api/usage`, aggregate rows per date, return chronologically ascending.
    static func decode(_ data: Data) throws -> [LocalDailyPoint] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        var tokensByDate: [String: Int] = [:]
        var turnsByDate: [String: Int] = [:]
        for row in envelope.rows {
            guard let date = row.date, !date.isEmpty else { continue }
            tokensByDate[date, default: 0] += row.totalTokens ?? 0
            turnsByDate[date, default: 0] += row.turns ?? 0
        }
        return tokensByDate.keys.sorted().map { date in
            LocalDailyPoint(
                date: date,
                totalTokens: tokensByDate[date] ?? 0,
                turns: turnsByDate[date] ?? 0
            )
        }
    }

    private struct Envelope: Decodable { let rows: [Row] }

    private struct Row: Decodable {
        let date: String?
        let turns: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey {
            case date, turns
            case totalTokens = "total_tokens"
        }
    }
}

/// Counts Codex rollout sessions that were written to recently ("in progress").
enum ActiveSessionMonitor {
    static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")
    }

    /// Pure helper: how many sessions were touched within `window` of `now`.
    static func countActive(modificationDates: [Date], now: Date, window: TimeInterval) -> Int {
        modificationDates.filter { now.timeIntervalSince($0) <= window && now.timeIntervalSince($0) >= -window }.count
    }

    static func activeCount(
        now: Date = Date(),
        window: TimeInterval = 300,
        root: URL = sessionsRoot
    ) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var dates: [Date] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate { dates.append(modified) }
        }
        return countActive(modificationDates: dates, now: now, window: window)
    }
}

enum UsageFeedsClient {
    static let aiUsageSummaryURL = URL(string: "http://127.0.0.1:3847/api/summary")!
    static let aiUsageWebURL = "http://127.0.0.1:3847/"

    static func fetchLocalUsageHistory(
        settings: AppNetworkSettings,
        session: URLSession
    ) async throws -> [LocalDailyPoint] {
        guard let url = settings.resolvedLocalUsageAPIURL else {
            throw CodexQuotaClient.FetchError.emptyBody
        }
        let data = try await body(from: url, session: session)
        return try LocalUsageHistory.decode(data)
    }

    static func fetchAiUsageSummary(session: URLSession) async throws -> AiUsageSummary {
        let data = try await body(from: aiUsageSummaryURL, session: session)
        return try AiUsageSummary.decode(data)
    }

    private static func body(from url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexQuotaClient.FetchError.emptyBody }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexQuotaClient.FetchError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw CodexQuotaClient.FetchError.emptyBody }
        return data
    }
}
