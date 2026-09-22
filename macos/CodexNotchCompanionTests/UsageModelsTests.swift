import AppKit
import XCTest
@testable import CodexNotchCompanion

final class UsageModelsTests: XCTestCase {
    func testDecodesAiUsageQuotaWindows() throws {
        let data = Data("""
        {"rate_limit":{"primary_window":{"used_percent":58,"reset_at":1720620000},"secondary_window":{"used_percent":31,"reset_at":1720965600}}}
        """.utf8)

        let snapshot = try QuotaSnapshot.decode(data: data)

        XCTAssertEqual(snapshot.fiveHour.usedPercent, 58)
        XCTAssertEqual(snapshot.weekly.usedPercent, 31)
        XCTAssertEqual(snapshot.status, .ready)
    }

    func testDecodesPartialLegacyQuotaPreferringWeeklyWindow() throws {
        let data = Data("""
        {"rate_limit":{"secondary_window":{"used_percent":44,"reset_at":1720965600,"limit_window_seconds":604800}}}
        """.utf8)

        let snapshot = try QuotaSnapshot.decode(data: data)

        XCTAssertEqual(snapshot.weekly.usedPercent, 44)
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 0)
        XCTAssertEqual(snapshot.status, .ready)
    }


    func testDecodesAiUsageQuotasEnvelopeWeeklyTier() throws {
        let data = Data("""
        {"quotas":[{"tool":"codex","success":true,"tiers":[{"name":"five_hour","utilization":12,"resetsAt":"2026-07-14T12:00:00Z"},{"name":"weekly_limit","utilization":47,"resetsAt":"2026-07-20T08:00:00Z"}],"error":null}]}
        """.utf8)

        let snapshot = try QuotaSnapshot.decode(data: data)

        XCTAssertEqual(snapshot.fiveHour.usedPercent, 12)
        XCTAssertEqual(snapshot.weekly.usedPercent, 47)
        XCTAssertEqual(snapshot.status, .ready)
        XCTAssertNotNil(snapshot.weekly.resetAt)
        XCTAssertTrue(QuotaDateFormat.resetLabel(snapshot.weekly.resetAt!).contains("2026"))
    }

    func testDecodesRateLimitResetCredits() throws {
        let data = Data("""
        {"credits":[{"id":"RateLimitResetCredit_1","status":"available","title":"Full reset","granted_at":"2026-06-17T00:00:00Z","expires_at":"2026-07-17T00:00:00Z"},{"id":"RateLimitResetCredit_2","status":"redeemed","title":"Used reset","granted_at":"2026-05-01T00:00:00Z","expires_at":"2026-06-01T00:00:00Z"}],"available_count":1}
        """.utf8)

        let snapshot = try RateLimitResetCreditsSnapshot.decode(data: data)

        XCTAssertEqual(snapshot.availableCount, 1)
        XCTAssertEqual(snapshot.credits.count, 2)
        XCTAssertEqual(snapshot.credits[0].statusLabel, "可用")
        XCTAssertEqual(snapshot.credits[1].statusLabel, "已使用")
        XCTAssertNotNil(snapshot.credits[0].expiresAt)
    }

    func testRejectsFailedCodexQuotaWithoutFakePercent() {
        let data = Data("""
        {"quotas":[{"tool":"codex","success":false,"tiers":[],"error":"Network error: TimeoutError"}]}
        """.utf8)

        XCTAssertThrowsError(try QuotaSnapshot.decode(data: data)) { error in
            XCTAssertEqual(
                error as? QuotaSnapshot.DecodeError,
                .upstream("Network error: TimeoutError")
            )
        }
    }

    func testReadsLatestLocalDailyCsvRow() throws {
        let csv = """
        date,turns,input_tokens,cached_input_tokens,output_tokens,reasoning_output_tokens,total_tokens,upload_code,upload_message,last_success_at
        2026-07-09,3,100,20,60,40,220,0,ok,2026-07-09T10:00:00Z
        2026-07-10,5,200,30,90,80,400,0,ok,2026-07-10T10:00:00Z
        """

        let usage = try XCTUnwrap(LocalDailyUsage.latest(csv: csv))

        XCTAssertEqual(usage.date, "2026-07-10")
        XCTAssertEqual(usage.totalTokens, 400)
        XCTAssertEqual(usage.turns, 5)
    }

    func testAggregatesLocalDailyLatestDayAcrossModelsAndStripsBOM() throws {
        let csv = """
        \u{FEFF}date,username,model,turns,total_tokens,upload_message
        2026-07-12,Alice,gpt-a,10,100,old
        2026-07-13,Alice,gpt-a,100,1000,ok
        2026-07-13,Alice,gpt-b,50,500,ok
        """

        let usage = try XCTUnwrap(LocalDailyUsage.latest(csv: csv))

        XCTAssertEqual(usage.date, "2026-07-13")
        XCTAssertEqual(usage.turns, 150)
        XCTAssertEqual(usage.totalTokens, 1500)
        XCTAssertEqual(usage.uploadMessage, "ok")
    }

    func testSystemProxyKeepsURLSessionDefaultBehavior() {
        let settings = AppNetworkSettings(proxyMode: .system, proxyURL: nil, enableAiUsageFallback: true)
        XCTAssertNil(NetworkProxyFactory.connectionProxyDictionary(for: settings))
    }

    func testCustomHTTPProxyDictionary() throws {
        let settings = AppNetworkSettings(
            proxyMode: .custom,
            proxyURL: "http://127.0.0.1:9098",
            enableAiUsageFallback: true
        )
        let dictionary = try XCTUnwrap(NetworkProxyFactory.connectionProxyDictionary(for: settings))
        XCTAssertEqual(dictionary["HTTPProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(dictionary["HTTPPort"] as? NSNumber, 9098)
        XCTAssertEqual(dictionary["HTTPSProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(dictionary["HTTPSPort"] as? NSNumber, 9098)
    }

    func testEnvironmentProxyDictionaryPrefersAllProxy() throws {
        let settings = AppNetworkSettings(proxyMode: .environment, proxyURL: nil, enableAiUsageFallback: true)
        let dictionary = try XCTUnwrap(
            NetworkProxyFactory.connectionProxyDictionary(
                for: settings,
                environment: ["ALL_PROXY": "socks5://127.0.0.1:9099"]
            )
        )
        XCTAssertEqual(dictionary["SOCKSProxy"] as? String, "127.0.0.1")
        XCTAssertEqual(dictionary["SOCKSPort"] as? NSNumber, 9099)
    }

    func testLoadsCodexCredentialsWithoutExposingTokenInErrors() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "codex-auth-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("""
        {"auth_mode":"chatgpt","tokens":{"access_token":"test-token","account_id":"acct-1"}}
        """.utf8).write(to: url)

        let token = try CodexCredentials.load(from: url)
        XCTAssertEqual(token.accessToken, "test-token")
        XCTAssertEqual(token.accountId, "acct-1")
    }

    func testGlowSweepNeverEscapesQuotaSegment() {
        let range = GlowSweep.segment(start: 0.5, length: 0.155, phase: 0.98)

        XCTAssertGreaterThanOrEqual(range.lowerBound, 0.5)
        XCTAssertLessThanOrEqual(range.upperBound, 0.655)
        XCTAssertGreaterThan(range.upperBound, range.lowerBound)
    }

    func testNativeNotchMetricsLeaveSideWingsForIcons() {
        let size = NotchMetrics.collapsedSize(notchWidth: 185, safeTop: 32)

        XCTAssertEqual(size.width, 233)
        XCTAssertEqual(size.height, 36)
    }

    func testContourGeometryUsesOneFullEdgePath() {
        let geometry = NotchContourGeometry(
            size: CGSize(width: 269, height: 54),
            bodyInset: 18,
            strokeInset: 2
        )

        XCTAssertEqual(geometry.start.x, 20, accuracy: 0.001)
        XCTAssertEqual(geometry.end.x, 249, accuracy: 0.001)
        XCTAssertEqual(geometry.start.y, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.end.y, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.bottomCenter.x, geometry.bodyRect.midX, accuracy: 0.001)
        XCTAssertEqual(geometry.bottomCenter.y, 34, accuracy: 0.001)
    }

    func testContourStrokeSitsOutsideThePhysicalNotchOnEveryVisibleEdge() {
        let geometry = NotchContourGeometry(
            size: CGSize(width: 269, height: 54),
            bodyInset: 18,
            strokeInset: 2
        )
        let physicalNotch = CGRect(x: 42, y: 0, width: 185, height: 32)

        XCTAssertLessThan(geometry.start.x, physicalNotch.minX)
        XCTAssertGreaterThan(geometry.end.x, physicalNotch.maxX)
        XCTAssertGreaterThan(geometry.bottomCenter.y, physicalNotch.maxY)
    }

    func testContourProgressClampsToVisibleRange() {
        XCTAssertEqual(NotchContourGeometry.normalizedProgress(-3), 0)
        XCTAssertEqual(NotchContourGeometry.normalizedProgress(58), 0.58, accuracy: 0.001)
        XCTAssertEqual(NotchContourGeometry.normalizedProgress(140), 1)
    }

    func testCompactPanelLeavesEighteenPointGlowMarginAroundBody() {
        let panel = NotchMetrics.compactPanelSize(notchWidth: 185, safeTop: 32)
        let body = NotchMetrics.compactBodyFrame(panelSize: panel)

        XCTAssertEqual(panel, CGSize(width: 269, height: 54))
        XCTAssertEqual(body, CGRect(x: 18, y: 0, width: 233, height: 36))
    }

    func testStatusDotSitsInsideRightWingAwayFromContour() {
        let body = CGSize(width: 233, height: 36)
        let center = NotchMetrics.statusDotCenter(bodySize: body)
        let geometry = NotchContourGeometry(
            size: CGSize(width: 269, height: 54),
            bodyInset: 18,
            strokeInset: 2
        )

        XCTAssertEqual(center.x, 221, accuracy: 0.001)
        XCTAssertEqual(center.y, 17, accuracy: 0.001)
        XCTAssertLessThan(center.x + NotchMetrics.glowMargin, geometry.end.x - 4)
    }

    func testPercentLabelStaysInsideLeftWingForNinetyNinePercent() {
        let body = CGSize(width: 233, height: 36)
        let frame = NotchMetrics.percentLabelFrame(bodySize: body)

        XCTAssertGreaterThanOrEqual(frame.minX, 3)
        XCTAssertGreaterThanOrEqual(frame.width, 20)
        XCTAssertLessThanOrEqual(frame.maxX, NotchMetrics.horizontalOutlineExpansion + 3)
        XCTAssertEqual(NotchMetrics.compactQuotaBadgeText(usedPercent: 99), "99%")
        XCTAssertEqual(NotchMetrics.compactQuotaBadgeText(usedPercent: 99.4), "99%")
        XCTAssertNil(NotchMetrics.compactQuotaBadgeText(usedPercent: 99.5))
        XCTAssertNil(NotchMetrics.compactQuotaBadgeText(usedPercent: 100))
        XCTAssertEqual(NotchMetrics.compactFullQuotaSymbolName, "flame.fill")
    }

    func testDecodesAiUsageSummary() throws {
        let data = Data("""
        {"inputTokens":100,"outputTokens":40,"cacheReadTokens":20,"cacheWriteTokens":5,"thinkingTokens":30,"totalTokens":195,"totalCost":1.25,"activeDays":3,"totalSessions":7}
        """.utf8)

        let summary = try AiUsageSummary.decode(data)

        XCTAssertEqual(summary.inputTokens, 100)
        XCTAssertEqual(summary.thinkingTokens, 30)
        XCTAssertEqual(summary.totalTokens, 195)
        XCTAssertEqual(summary.totalSessions, 7)
        XCTAssertEqual(summary.totalCost, 1.25, accuracy: 0.0001)
        XCTAssertTrue(summary.hasData)
    }

    func testAiUsageSummaryToleratesMissingFields() throws {
        let summary = try AiUsageSummary.decode(Data("{}".utf8))
        XCTAssertEqual(summary, .empty)
        XCTAssertFalse(summary.hasData)
    }

    func testLocalUsageHistoryAggregatesRowsPerDateAscending() throws {
        let data = Data("""
        {"rows":[
          {"date":"2026-06-08","turns":10,"total_tokens":100},
          {"date":"2026-06-07","turns":5,"total_tokens":50},
          {"date":"2026-06-08","turns":2,"total_tokens":25}
        ]}
        """.utf8)

        let points = try LocalUsageHistory.decode(data)

        XCTAssertEqual(points.map(\.date), ["2026-06-07", "2026-06-08"])
        XCTAssertEqual(points[1].totalTokens, 125)
        XCTAssertEqual(points[1].turns, 12)
    }

    func testProgressBarStyleDefaultsToPacmanAndPersists() {
        let defaults = UserDefaults(suiteName: "ProgressBarStyleTests")!
        defaults.removePersistentDomain(forName: "ProgressBarStyleTests")

        XCTAssertEqual(ProgressBarStyle.load(defaults: defaults), .pacman)
        XCTAssertEqual(ProgressBarStyle.classic.shaderValue, 0)
        XCTAssertEqual(ProgressBarStyle.pacman.shaderValue, 1)

        ProgressBarStyle.classic.save(defaults: defaults)
        XCTAssertEqual(ProgressBarStyle.load(defaults: defaults), .classic)

        defaults.removePersistentDomain(forName: "ProgressBarStyleTests")
    }

    func testActiveSessionCountUsesRecencyWindow() {
        let now = Date()
        let dates = [
            now.addingTimeInterval(-30),
            now.addingTimeInterval(-120),
            now.addingTimeInterval(-600),
            now.addingTimeInterval(-3600),
        ]
        XCTAssertEqual(ActiveSessionMonitor.countActive(modificationDates: dates, now: now, window: 300), 2)
        XCTAssertEqual(ActiveSessionMonitor.countActive(modificationDates: [], now: now, window: 300), 0)
    }

    @MainActor
    func testContourPathSamplerProducesMonotonicSegments() {
        let geometry = NotchContourGeometry(
            size: CGSize(width: 269, height: 54),
            bodyInset: 18,
            strokeInset: 2
        )
        let segments = NotchContourPathSampler.segments(from: geometry)

        XCTAssertGreaterThan(segments.count, 8)
        XCTAssertEqual(Double(segments.first?.t0 ?? -1), 0, accuracy: 0.001)
        XCTAssertEqual(Double(segments.last?.t1 ?? -1), 1, accuracy: 0.001)
        for index in 1..<segments.count {
            XCTAssertEqual(Double(segments[index - 1].t1), Double(segments[index].t0), accuracy: 0.001)
        }
    }

    @MainActor
    func testContourRendererUsesMetalLayerInsteadOfLayeredGlowStrokes() {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 31, hovering: true, expanded: false)
        view.layoutSubtreeIfNeeded()

        let layerNames = Set(view.layer?.sublayers?.compactMap(\.name) ?? [])
        XCTAssertTrue(layerNames.contains("notch-body"))
        XCTAssertTrue(layerNames.contains("track"))
        XCTAssertTrue(layerNames.contains(NotchContourMetalRenderer.layerName))
        XCTAssertFalse(layerNames.contains("soft-glow"))
        XCTAssertFalse(layerNames.contains("outer-glow"))
        XCTAssertFalse(layerNames.contains("mid-glow"))
    }

    @MainActor
    func testMetalRendererTracksWeeklyProgressAndFlowPhase() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 62, hovering: false, expanded: false)
        view.layoutSubtreeIfNeeded()
        view.advanceFlow(to: 0.55)

        let metalLayer = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == NotchContourMetalRenderer.layerName })
        )
        XCTAssertFalse(metalLayer.isOpaque)
        XCTAssertGreaterThan(metalLayer.bounds.width, 0)
    }

    @MainActor
    func testFlowPhaseLoopsWithoutLayerWrapSegments() {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 62, hovering: false, expanded: false)
        view.layoutSubtreeIfNeeded()

        view.advanceFlow(to: 0.0)
        view.advanceFlow(to: 0.45)
        view.advanceFlow(to: 0.0)

        let metalLayer = view.layer?.sublayers?.first(where: { $0.name == NotchContourMetalRenderer.layerName })
        XCTAssertNotNil(metalLayer)
    }

    @MainActor
    func testContourHidesTrackBackground() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 62, hovering: false, expanded: false)
        view.layoutSubtreeIfNeeded()

        let track = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == "track" }) as? CAShapeLayer
        )
        XCTAssertEqual(track.opacity, 0)
    }

    @MainActor
    func testCollapsedBodyFillIsOpaque() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 62, hovering: false, expanded: false)
        view.layoutSubtreeIfNeeded()

        let body = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == "notch-body" }) as? CAShapeLayer
        )
        XCTAssertGreaterThan(body.fillColor?.alpha ?? 0, 0.99)
    }

    @MainActor
    func testExpandedBodyFillIsOpaque() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 472, height: 496))
        view.update(weeklyPercent: 62, hovering: false, expanded: true)
        view.layoutSubtreeIfNeeded()

        let body = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == "notch-body" }) as? CAShapeLayer
        )
        XCTAssertGreaterThan(body.fillColor?.alpha ?? 0, 0.99)
    }

    @MainActor
    func testContourHidesGlowWhenRequested() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 269, height: 54))
        view.update(weeklyPercent: 62, hovering: false, expanded: false, glowVisible: false)
        view.layoutSubtreeIfNeeded()

        let track = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == "track" }) as? CAShapeLayer
        )
        let metalLayer = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == NotchContourMetalRenderer.layerName })
        )
        XCTAssertEqual(track.opacity, 0)
        XCTAssertEqual(metalLayer.opacity, 0)
    }

    @MainActor
    func testExpandedRendererHidesMetalContour() throws {
        let view = NotchContourLayerView(frame: CGRect(x: 0, y: 0, width: 472, height: 496))
        view.update(weeklyPercent: 62, hovering: false, expanded: true)
        view.layoutSubtreeIfNeeded()

        let track = try XCTUnwrap(
            view.layer?.sublayers?.first(where: { $0.name == "track" }) as? CAShapeLayer
        )
        XCTAssertEqual(track.opacity, 0)
    }
}
