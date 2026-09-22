import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var quota = QuotaSnapshot.unknown
    @Published private(set) var resetCredits = RateLimitResetCreditsSnapshot.empty
    @Published private(set) var localUsage: LocalDailyUsage?
    @Published private(set) var localUsageHistory: [LocalDailyPoint] = []
    @Published private(set) var aiUsage: AiUsageSummary?
    @Published private(set) var activeSessions = 0
    @Published private(set) var refreshedAt = Date()
    @Published private(set) var networkSettings = AppNetworkSettings.default
    @Published var progressStyle: ProgressBarStyle = .pacman {
        didSet { progressStyle.save() }
    }

    init() {
        progressStyle = ProgressBarStyle.load()
        networkSettings = AppNetworkSettings.load()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func updateNetworkSettings(_ settings: AppNetworkSettings) {
        settings.save()
        networkSettings = settings
        refresh()
    }

    func refresh() {
        let previous = quota
        networkSettings = AppNetworkSettings.load()
        let settings = networkSettings
        Task {
            do {
                quota = try await CodexQuotaClient.fetchQuota(settings: settings)
            } catch {
                if previous.status == .ready || previous.status == .stale {
                    quota = .init(fiveHour: previous.fiveHour, weekly: previous.weekly, status: .stale)
                } else {
                    quota = .init(
                        fiveHour: .init(usedPercent: 0, resetAt: nil),
                        weekly: .init(usedPercent: 0, resetAt: nil),
                        status: .error
                    )
                }
            }

            if let credits = try? await CodexQuotaClient.fetchResetCredits(settings: settings) {
                resetCredits = credits
            }

            if let csvPath = settings.localDailyCSVPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !csvPath.isEmpty {
                let url = URL(fileURLWithPath: (csvPath as NSString).expandingTildeInPath)
                localUsage = (try? String(contentsOf: url, encoding: .utf8)).flatMap(LocalDailyUsage.latest)
            } else {
                localUsage = nil
            }

            let feedSession = URLSession(configuration: .ephemeral)
            if let history = try? await UsageFeedsClient.fetchLocalUsageHistory(
                settings: settings,
                session: feedSession
            ) {
                localUsageHistory = history
            } else {
                localUsageHistory = []
            }
            if let summary = try? await UsageFeedsClient.fetchAiUsageSummary(session: feedSession) {
                aiUsage = summary
            }
            activeSessions = ActiveSessionMonitor.activeCount()

            refreshedAt = Date()
        }
    }
}
