import SwiftUI
import AppKit
import Charts

struct NotchRootView: View {
    @ObservedObject var store: UsageStore
    let compactBodyHeight: CGFloat
    let onResize: (Bool) -> Void
    var onOpenSettings: () -> Void = {}
    @State private var expanded = false
    @State private var hovering = false
    @State private var contourPercent: Double = 0
    @State private var glowVisible = true
    @State private var isReplayingProgress = false
    @State private var progressReplayToken = 0
    @State private var progressReplayTarget: Double = 0

    private var contourWeeklyPercent: Double {
        isReplayingProgress ? contourPercent : store.quota.weekly.usedPercent
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchContourView(
                weeklyPercent: contourWeeklyPercent,
                hovering: hovering,
                expanded: expanded,
                glowVisible: glowVisible,
                style: store.progressStyle,
                progressReplayToken: progressReplayToken,
                progressReplayTarget: progressReplayTarget,
                onReplayComplete: {
                    isReplayingProgress = false
                    glowVisible = true
                    contourPercent = store.quota.weekly.usedPercent
                }
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Button { toggle() } label: { NotchHeader(quota: store.quota, expanded: expanded) }
                    .buttonStyle(.plain)
                    .frame(height: expanded ? 68 : compactBodyHeight)
                if expanded {
                    DetailsView(store: store, close: { toggle() }, openSettings: onOpenSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipShape(.rect(
                bottomLeadingRadius: expanded ? 24 : 14,
                bottomTrailingRadius: expanded ? 24 : 14
            ))
            .padding(.horizontal, NotchMetrics.glowMargin)
            .padding(.bottom, NotchMetrics.glowMargin)
        }
        .background(Color.clear)
        .scaleEffect(hovering && !expanded ? 1.01 : 1, anchor: .top)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onExitCommand { if expanded { toggle() } }
        .onHover { hovering = $0 }
        .onChange(of: store.quota.weekly.usedPercent) { _, newValue in
            guard !expanded, !isReplayingProgress else { return }
            contourPercent = newValue
        }
    }

    private func toggle() {
        if expanded {
            glowVisible = false
            contourPercent = 0
            isReplayingProgress = true
            expanded = false
            onResize(false)

            let target = store.quota.weekly.usedPercent
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                progressReplayTarget = target
                progressReplayToken += 1
            }
        } else {
            isReplayingProgress = false
            glowVisible = true
            contourPercent = store.quota.weekly.usedPercent
            expanded = true
            onResize(true)
        }
    }
}

private struct NotchHeader: View {
    let quota: QuotaSnapshot
    let expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let dotCenter = NotchMetrics.statusDotCenter(bodySize: proxy.size)
            let percentFrame = NotchMetrics.percentLabelFrame(bodySize: proxy.size)
            let color: Color = quota.status == .ready ? .mint : .orange

            if !expanded {
                compactQuotaBadge(color: color)
                    .frame(width: percentFrame.width, height: percentFrame.height)
                    .position(x: percentFrame.midX, y: percentFrame.midY)
            }

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .position(dotCenter)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func compactQuotaBadge(color: Color) -> some View {
        if let text = NotchMetrics.compactQuotaBadgeText(usedPercent: quota.weekly.usedPercent) {
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: NotchMetrics.compactFullQuotaSymbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DetailsView: View {
    @ObservedObject var store: UsageStore
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow

            quotaCard(
                title: "周额度",
                value: store.quota.weekly.usedPercent,
                resetAt: store.quota.weekly.resetAt,
                color: Color(red: 0.32, green: 0.95, blue: 0.72)
            )

            resetCreditsCard
            activeSessionsCard
            aiUsageCard
            localUsageCard

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("只读访问 · 不触发上传")
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.38))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 用量概览")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusLabel)
                    Text("·")
                    Text(store.refreshedAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.075), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.09), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("打开设置")

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.64))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.075), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.09), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var activeSessionsCard: some View {
        let accent = Color(red: 0.32, green: 0.95, blue: 0.72)
        let count = store.activeSessions
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(accent.opacity(0.12))
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(count > 0 ? accent : .white.opacity(0.4))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("正在进行的会话")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(count > 0 ? "最近 5 分钟内活跃的 Codex 会话" : "当前没有活跃会话")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? accent : .white.opacity(0.55))
                Text("个")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .panelCard(padding: 11)
    }

    private var aiUsageCard: some View {
        let accent = Color(red: 1, green: 0.55, blue: 0.35)
        let summary = store.aiUsage ?? .empty
        return Button {
            openWeb(UsageFeedsClient.aiUsageWebURL)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader(
                    icon: "chart.pie.fill",
                    title: "AIUsage",
                    eyebrow: "本地记录",
                    accent: accent,
                    trailing: "打开网页"
                )

                if summary.hasData {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatTokens(summary.totalTokens))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                            Text("总 Token · \(summary.totalSessions) 会话")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            if summary.totalCost > 0 {
                                Text(String(format: "$%.2f", summary.totalCost))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer(minLength: 0)
                        aiCompositionChart(summary: summary, accent: accent)
                            .frame(width: 150, height: 58)
                    }
                } else {
                    Text("暂无本地 AIUsage 统计（127.0.0.1:3847）")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func aiCompositionChart(summary: AiUsageSummary, accent: Color) -> some View {
        Chart(summary.compositionSlices, id: \.label) { slice in
            BarMark(
                x: .value("类别", slice.label),
                y: .value("Token", slice.value)
            )
            .foregroundStyle(accent.gradient)
            .cornerRadius(3)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private var localUsageCard: some View {
        let accent = Color(red: 0.38, green: 0.76, blue: 1)
        let points = Array(store.localUsageHistory.suffix(7))
        let webURL = store.networkSettings.resolvedLocalUsageWebURL
        return Button {
            if let webURL { openWeb(webURL) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader(
                    icon: "chart.bar.xaxis",
                    title: "本地上报",
                    eyebrow: "本地统计",
                    accent: accent,
                    trailing: webURL == nil ? "未配置" : "打开网页"
                )

                if let today = points.last {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatTokens(today.totalTokens))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                            Text("最新日 · \(today.turns) 回合")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(today.date)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                        localUsageTrendChart(points: points, accent: accent)
                            .frame(width: 150, height: 58)
                    }
                } else {
                    Text(webURL == nil ? "在设置中配置本地上报数据源" : "暂无本地上报历史")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelCard(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(webURL == nil && points.isEmpty)
    }

    private func localUsageTrendChart(points: [LocalDailyPoint], accent: Color) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("日期", String(point.date.suffix(5))),
                y: .value("Token", point.totalTokens)
            )
            .foregroundStyle(accent.gradient)
            .cornerRadius(2)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private func cardHeader(
        icon: String,
        title: String,
        eyebrow: String,
        accent: Color,
        trailing: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(eyebrow.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(accent.opacity(0.9))
            Spacer()
            HStack(spacing: 3) {
                Text(trailing)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func openWeb(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func formatTokens(_ value: Int) -> String {
        let d = Double(value)
        if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1e3) }
        return "\(value)"
    }

    private var statusColor: Color {
        store.quota.status == .ready ? .mint : .orange
    }

    private var statusLabel: String {
        switch store.quota.status {
        case .loading: "加载中"
        case .ready: "实时额度"
        case .stale: "离线缓存"
        case .error: "读取异常"
        }
    }

    private func quotaCard(
        title: String,
        value: Double,
        resetAt: Date?,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.66))
                Spacer()
                Circle().fill(color).frame(width: 5, height: 5)
                    .shadow(color: color.opacity(0.75), radius: 4)
            }

            Text("\(Int(value.rounded()))%")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            if store.progressStyle == .pacman {
                PacmanProgressBar(progress: value / 100, height: 26)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [color.opacity(0.62), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: proxy.size.width * min(max(value / 100, 0), 1))
                            .shadow(color: color.opacity(0.42), radius: 4)
                    }
                }
                .frame(height: 3)
            }

            Text(resetAt.map(QuotaDateFormat.resetLabel) ?? "等待重置时间")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(padding: 12)
    }

    private var resetCreditsCard: some View {
        let accent = Color(red: 0.98, green: 0.78, blue: 0.36)
        let snapshot = store.resetCredits
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("重置券")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(snapshot.availableCount > 0
                         ? "可用 \(snapshot.availableCount) 张"
                         : "当前没有可用重置券")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
            }

            if snapshot.credits.isEmpty {
                Text("暂无重置券明细")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            } else {
                ForEach(snapshot.credits) { credit in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text((credit.title?.isEmpty == false) ? (credit.title ?? "额度重置券") : "额度重置券")
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(credit.statusLabel)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(credit.status.lowercased() == "available" ? accent : .white.opacity(0.45))
                        }
                        if let expiresAt = credit.expiresAt {
                            Text("过期 \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.42))
                        } else if let grantedAt = credit.grantedAt {
                            Text("授予 \(grantedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panelCard(padding: 11)
    }

}

private extension View {
    func panelCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(.white.opacity(0.052), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            )
    }
}
