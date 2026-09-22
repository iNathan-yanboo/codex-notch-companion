import Foundation

enum UsageStatus: String, Equatable { case loading, ready, stale, error }

enum GlowSweep {
    static func segment(start: Double, length: Double, phase: Double, width: Double = 0.045) -> ClosedRange<Double> {
        let safeLength = max(0, length)
        let progress = min(max(phase, 0), 1) * safeLength
        let end = min(start + safeLength, start + progress + width)
        let begin = max(start, end - width)
        return begin...max(begin + 0.0001, end)
    }
}

enum NotchMetrics {
    /// Transparent margin around the body so soft glow is not clipped into a hard box.
    static let glowMargin: CGFloat = 18
    /// Extra width beyond the physical notch so icons/status sit in side wings.
    static let horizontalOutlineExpansion: CGFloat = 24
    static let bottomOutlineExpansion: CGFloat = 4
    static let expandedWidth: CGFloat = 440
    static let expandedHeight: CGFloat = 720

    static func collapsedSize(notchWidth: CGFloat, safeTop: CGFloat) -> CGSize {
        guard notchWidth > 0, safeTop > 0 else { return .init(width: 220, height: 40) }
        return .init(
            width: notchWidth + horizontalOutlineExpansion * 2,
            height: safeTop + bottomOutlineExpansion
        )
    }

    static func compactPanelSize(notchWidth: CGFloat, safeTop: CGFloat) -> CGSize {
        let body = collapsedSize(notchWidth: notchWidth, safeTop: safeTop)
        return .init(width: body.width + glowMargin * 2, height: body.height + glowMargin)
    }

    static func compactBodyFrame(panelSize: CGSize) -> CGRect {
        CGRect(
            x: glowMargin,
            y: 0,
            width: max(0, panelSize.width - glowMargin * 2),
            height: max(0, panelSize.height - glowMargin)
        )
    }

    static var expandedPanelSize: CGSize {
        .init(width: expandedWidth + glowMargin * 2, height: expandedHeight + glowMargin)
    }

    /// Place the status dot inside the right wing, clear of the contour stroke.
    static func statusDotCenter(bodySize: CGSize) -> CGPoint {
        CGPoint(x: max(12, bodySize.width - 12), y: min(17, bodySize.height / 2))
    }

    /// Left-wing badge frame; sits clear of the descending contour stroke + glow
    /// (~6pt from the body edge) while keeping "99%" inside the outline expansion.
    static func percentLabelFrame(bodySize: CGSize) -> CGRect {
        let strokeGlowClearance: CGFloat = 4
        let wing = horizontalOutlineExpansion
        let height: CGFloat = 16
        let y = min(17, bodySize.height / 2) - height / 2
        let x = strokeGlowClearance
        // Allow a hair of overlap into the notch edge so "99%" is never clipped.
        let width = max(20, wing - strokeGlowClearance + 2)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Compact left-wing quota: percent text for 0...99, nil means show the full-quota icon.
    static func compactQuotaBadgeText(usedPercent: Double) -> String? {
        let rounded = Int(usedPercent.rounded())
        if rounded >= 100 { return nil }
        return "\(min(max(rounded, 0), 99))%"
    }

    static let compactFullQuotaSymbolName = "flame.fill"
}

struct QuotaWindow: Equatable {
    let usedPercent: Double
    let resetAt: Date?
}

enum QuotaDateFormat {
    static func resetLabel(_ date: Date) -> String {
        "重置于 \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct RateLimitResetCredit: Equatable, Identifiable {
    let id: String
    let status: String
    let title: String?
    let description: String?
    let grantedAt: Date?
    let expiresAt: Date?

    var statusLabel: String {
        switch status.lowercased() {
        case "available": return "可用"
        case "redeemed": return "已使用"
        case "expired": return "已过期"
        case "redeeming": return "兑换中"
        default: return status
        }
    }
}

struct RateLimitResetCreditsSnapshot: Equatable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]

    static let empty = RateLimitResetCreditsSnapshot(availableCount: 0, credits: [])

    static func decode(data: Data) throws -> RateLimitResetCreditsSnapshot {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let credits = (payload.credits ?? []).map { item in
            RateLimitResetCredit(
                id: item.id,
                status: item.status ?? "unknown",
                title: item.title,
                description: item.description,
                grantedAt: parseISO8601(item.grantedAt),
                expiresAt: parseISO8601(item.expiresAt)
            )
        }
        let available = payload.availableCount
            ?? credits.filter { $0.status.lowercased() == "available" }.count
        return .init(availableCount: available, credits: credits)
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private struct Payload: Decodable {
        let credits: [Credit]?
        let availableCount: Int?

        enum CodingKeys: String, CodingKey {
            case credits
            case availableCount = "available_count"
        }
    }

    private struct Credit: Decodable {
        let id: String
        let status: String?
        let title: String?
        let description: String?
        let grantedAt: String?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id, status, title, description
            case grantedAt = "granted_at"
            case expiresAt = "expires_at"
        }
    }
}

struct QuotaSnapshot: Equatable {
    let fiveHour: QuotaWindow
    let weekly: QuotaWindow
    let status: UsageStatus

    static let preview = QuotaSnapshot(
        fiveHour: .init(usedPercent: 58, resetAt: nil),
        weekly: .init(usedPercent: 31, resetAt: nil),
        status: .stale
    )

    /// Empty state used before the first successful live fetch.
    static let unknown = QuotaSnapshot(
        fiveHour: .init(usedPercent: 0, resetAt: nil),
        weekly: .init(usedPercent: 0, resetAt: nil),
        status: .loading
    )

    enum DecodeError: Error, Equatable {
        case missingCodex
        case upstream(String)
        case missingWeekly
    }

    static func decode(data: Data) throws -> QuotaSnapshot {
        if let envelope = try? JSONDecoder().decode(QuotasEnvelope.self, from: data),
           envelope.quotas != nil {
            return try decodeQuotas(envelope)
        }

        let response = try JSONDecoder().decode(LegacyResponse.self, from: data)
        let primary = response.rateLimit.primaryWindow
        let secondary = response.rateLimit.secondaryWindow
        guard primary != nil || secondary != nil else { throw DecodeError.missingWeekly }

        let weeklyWindow = preferredWeekly(primary: primary, secondary: secondary)
        guard let weeklyWindow else { throw DecodeError.missingWeekly }
        let fiveHourWindow = preferredFiveHour(primary: primary, secondary: secondary, weekly: weeklyWindow)

        return .init(
            fiveHour: .init(
                usedPercent: fiveHourWindow?.usedPercent ?? 0,
                resetAt: fiveHourWindow?.resetAt.map(Date.init(timeIntervalSince1970:))
            ),
            weekly: .init(
                usedPercent: weeklyWindow.usedPercent,
                resetAt: weeklyWindow.resetAt.map(Date.init(timeIntervalSince1970:))
            ),
            status: .ready
        )
    }

    private static func preferredWeekly(primary: Window?, secondary: Window?) -> Window? {
        let windows = [primary, secondary].compactMap { $0 }
        if let bySeconds = windows.first(where: { ($0.limitWindowSeconds ?? 0) > 3600 * 6 }) {
            return bySeconds
        }
        return secondary ?? primary
    }

    private static func preferredFiveHour(primary: Window?, secondary: Window?, weekly: Window) -> Window? {
        let windows = [primary, secondary].compactMap { $0 }
        if let bySeconds = windows.first(where: {
            let seconds = $0.limitWindowSeconds ?? 0
            return seconds > 0 && seconds <= 3600 * 6
        }) {
            return bySeconds
        }
        if primary?.usedPercent != weekly.usedPercent || primary?.resetAt != weekly.resetAt {
            return primary
        }
        return nil
    }

    private static func decodeQuotas(_ envelope: QuotasEnvelope) throws -> QuotaSnapshot {
        guard let quotas = envelope.quotas else { throw DecodeError.missingCodex }
        guard let codex = quotas.first(where: { $0.tool == "codex" }) else {
            throw DecodeError.missingCodex
        }
        guard codex.success else {
            throw DecodeError.upstream(codex.error ?? "codex quota query failed")
        }

        let tiers = codex.tiers
        let weeklyTier = tiers.first(where: { ["weekly_limit", "seven_day"].contains($0.name) })
            ?? tiers.first(where: { $0.name.contains("week") || $0.name.contains("seven_day") })
        guard let weeklyTier else { throw DecodeError.missingWeekly }

        let fiveHourTier = tiers.first(where: { $0.name == "five_hour" || $0.name.contains("five_hour") })

        return .init(
            fiveHour: .init(
                usedPercent: fiveHourTier?.utilization ?? 0,
                resetAt: parseReset(fiveHourTier?.resetsAt)
            ),
            weekly: .init(
                usedPercent: weeklyTier.utilization,
                resetAt: parseReset(weeklyTier.resetsAt)
            ),
            status: .ready
        )
    }

    private static func parseReset(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private struct QuotasEnvelope: Decodable {
        let quotas: [QuotaTool]?
    }

    private struct QuotaTool: Decodable {
        let tool: String
        let success: Bool
        let tiers: [QuotaTier]
        let error: String?
    }

    private struct QuotaTier: Decodable {
        let name: String
        let utilization: Double
        let resetsAt: String?
    }

    private struct LegacyResponse: Decodable {
        let rateLimit: RateLimit
        enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit" }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct Window: Decodable, Equatable {
        let usedPercent: Double
        let resetAt: TimeInterval?
        let limitWindowSeconds: TimeInterval?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

struct LocalDailyUsage: Equatable {
    let date: String
    let turns: Int
    let totalTokens: Int
    let uploadMessage: String

    static func latest(csv: String) -> LocalDailyUsage? {
        let normalized = csv
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = normalized.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = rows.first else { return nil }
        let keys = header.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let records: [[String: String]] = rows.dropFirst().compactMap { line in
            let values = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count == keys.count else { return nil }
            return Dictionary(uniqueKeysWithValues: zip(keys, values))
        }
        guard let latestDate = records.compactMap({ $0["date"] }).max() else { return nil }
        let dayRows = records.filter { $0["date"] == latestDate }
        guard !dayRows.isEmpty else { return nil }

        let turns = dayRows.reduce(0) { $0 + (Int($1["turns"] ?? "0") ?? 0) }
        let totalTokens = dayRows.reduce(0) { $0 + (Int($1["total_tokens"] ?? "0") ?? 0) }
        let uploadMessage = dayRows.reversed()
            .compactMap { message in
                let value = message["upload_message"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (value?.isEmpty == false) ? value : nil
            }
            .first ?? "未同步"

        return .init(date: latestDate, turns: turns, totalTokens: totalTokens, uploadMessage: uploadMessage)
    }
}
