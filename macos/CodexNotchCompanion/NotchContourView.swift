import AppKit
import QuartzCore
import SwiftUI

struct NotchContourView: NSViewRepresentable {
    let weeklyPercent: Double
    let hovering: Bool
    let expanded: Bool
    var glowVisible: Bool = true
    var style: ProgressBarStyle = .pacman
    var progressReplayToken: Int = 0
    var progressReplayTarget: Double = 0
    var onReplayComplete: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NotchContourLayerView {
        NotchContourLayerView(frame: .zero)
    }

    func updateNSView(_ nsView: NotchContourLayerView, context: Context) {
        nsView.update(
            weeklyPercent: weeklyPercent,
            hovering: hovering,
            expanded: expanded,
            glowVisible: glowVisible,
            style: style
        )

        if progressReplayToken > 0,
           progressReplayToken != context.coordinator.lastReplayToken {
            context.coordinator.lastReplayToken = progressReplayToken
            nsView.runProgressReplay(
                target: progressReplayTarget,
                progressDuration: 0.55,
                glowFadeDuration: 0.35,
                completion: onReplayComplete
            )
        }
    }

    final class Coordinator {
        var lastReplayToken = 0
    }
}

@MainActor
final class NotchContourLayerView: NSView {
    private let bodyLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let metal = NotchContourMetalRenderer()

    private var flowTimer: Timer?
    private var progressTimer: Timer?
    private var glowTimer: Timer?
    private var flowPhase: CGFloat = 0
    private var pelletSeconds: Double = 0
    private let pelletCellsPerSecond: Double = 0.55
    private var weeklyProgress: CGFloat = 0
    private var glowIntensity: CGFloat = 1
    private var hovering = false
    private var expanded = false
    private var glowVisible = true
    private var style: ProgressBarStyle = .pacman
    private var isAnimatingProgress = false

    private var progressAnimationStart: CFTimeInterval = 0
    private var progressAnimationFrom: CGFloat = 0
    private var progressAnimationTo: CGFloat = 0
    private var progressAnimationDuration: TimeInterval = 0
    private var progressAnimationCompletion: (() -> Void)?

    private var glowAnimationStart: CFTimeInterval = 0
    private var glowAnimationFrom: CGFloat = 0
    private var glowAnimationTo: CGFloat = 0
    private var glowAnimationDuration: TimeInterval = 0
    private var glowAnimationCompletion: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFlowTimer()
            stopProgressAnimation()
            stopGlowAnimation()
        } else {
            needsLayout = true
            layoutSubtreeIfNeeded()
            updateFlowAnimations()
        }
    }

    func update(
        weeklyPercent: Double,
        hovering: Bool,
        expanded: Bool,
        glowVisible: Bool = true,
        style: ProgressBarStyle = .pacman
    ) {
        self.hovering = hovering
        self.expanded = expanded
        self.glowVisible = glowVisible
        self.style = style

        if !isAnimatingProgress {
            weeklyProgress = NotchContourGeometry.normalizedProgress(weeklyPercent)
            if glowVisible {
                glowIntensity = 1
            }
        }

        needsLayout = true
        layoutSubtreeIfNeeded()
        applyProgressToRenderer()
        applyGlowVisibility()
        updateFlowAnimations()
    }

    func runProgressReplay(
        target: Double,
        progressDuration: TimeInterval,
        glowFadeDuration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        stopProgressAnimation()
        stopGlowAnimation()
        stopFlowTimer()

        isAnimatingProgress = true
        glowVisible = true
        glowIntensity = 0
        weeklyProgress = 0
        applyProgressToRenderer()
        applyGlowVisibility()

        animateWeeklyProgress(to: target, duration: progressDuration) { [weak self] in
            guard let self else { return }
            self.fadeGlowIn(duration: glowFadeDuration) {
                self.isAnimatingProgress = false
                self.updateFlowAnimations()
                completion?()
            }
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let geometry = NotchContourGeometry(
            size: bounds.size,
            bodyInset: NotchMetrics.glowMargin,
            strokeInset: 2
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer?.frame = bounds
        bodyLayer.frame = bounds
        bodyLayer.path = geometry.bodyPath
        applyBodyAppearance()

        trackLayer.frame = bounds
        trackLayer.path = geometry.contourPath
        trackLayer.lineWidth = hovering ? 1.25 : 1.05
        trackLayer.opacity = 0

        metal.layout(in: bounds, geometry: geometry)
        applyProgressToRenderer()

        CATransaction.commit()
    }

    private func configureLayers() {
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.clear.cgColor
        root.masksToBounds = false
        root.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer = root

        bodyLayer.name = "notch-body"
        bodyLayer.lineWidth = 0.7
        bodyLayer.masksToBounds = false
        applyBodyAppearance()

        trackLayer.name = "track"
        trackLayer.fillColor = nil
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.55).cgColor
        trackLayer.lineCap = .round
        trackLayer.lineJoin = .round
        trackLayer.opacity = 0
        trackLayer.masksToBounds = false

        metal.metalLayer.masksToBounds = false

        root.addSublayer(bodyLayer)
        root.addSublayer(trackLayer)
        root.addSublayer(metal.metalLayer)
    }

    private func applyBodyAppearance() {
        bodyLayer.fillColor = NSColor(deviceRed: 0.014, green: 0.018, blue: 0.018, alpha: 1).cgColor
        bodyLayer.strokeColor = NSColor.white.withAlphaComponent(0.035).cgColor
    }

    private func applyGlowVisibility() {
        let showMetal = (glowVisible || isAnimatingProgress) && !expanded
        metal.metalLayer.opacity = showMetal ? 1 : 0
    }

    private func applyProgressToRenderer() {
        metal.update(
            weeklyPercent: Double(weeklyProgress * 100),
            hovering: hovering,
            expanded: expanded,
            glowIntensity: glowIntensity,
            style: style.shaderValue
        )
    }

    private func animateWeeklyProgress(
        to target: Double,
        duration: TimeInterval,
        completion: (() -> Void)? = nil
    ) {
        stopProgressAnimation()
        progressAnimationFrom = weeklyProgress
        progressAnimationTo = NotchContourGeometry.normalizedProgress(target)
        progressAnimationDuration = max(duration, 0.01)
        progressAnimationStart = CACurrentMediaTime()
        progressAnimationCompletion = completion

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickProgressAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func fadeGlowIn(duration: TimeInterval, completion: (() -> Void)? = nil) {
        stopGlowAnimation()
        glowAnimationFrom = glowIntensity
        glowAnimationTo = 1
        glowAnimationDuration = max(duration, 0.01)
        glowAnimationStart = CACurrentMediaTime()
        glowAnimationCompletion = completion

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickGlowAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        glowTimer = timer
    }

    private func tickProgressAnimation() {
        let elapsed = CACurrentMediaTime() - progressAnimationStart
        let raw = min(1, elapsed / progressAnimationDuration)
        let eased = 1 - pow(1 - raw, 3)
        weeklyProgress = progressAnimationFrom + (progressAnimationTo - progressAnimationFrom) * eased
        applyProgressToRenderer()

        guard raw >= 1 else { return }
        weeklyProgress = progressAnimationTo
        applyProgressToRenderer()
        let completion = progressAnimationCompletion
        stopProgressAnimation()
        completion?()
    }

    private func tickGlowAnimation() {
        let elapsed = CACurrentMediaTime() - glowAnimationStart
        let raw = min(1, elapsed / glowAnimationDuration)
        let eased = raw * raw * (3 - 2 * raw)
        glowIntensity = glowAnimationFrom + (glowAnimationTo - glowAnimationFrom) * eased
        applyProgressToRenderer()

        guard raw >= 1 else { return }
        glowIntensity = glowAnimationTo
        applyProgressToRenderer()
        let completion = glowAnimationCompletion
        stopGlowAnimation()
        completion?()
    }

    private func updateFlowAnimations() {
        guard glowVisible, !expanded, !isAnimatingProgress, weeklyProgress > 0.001, metal.isReady else {
            stopFlowTimer()
            metal.advanceFlow(to: 0)
            return
        }

        metal.advanceFlow(to: flowPhase)
        guard window != nil else {
            stopFlowTimer()
            return
        }
        guard flowTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickFlowTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        flowTimer = timer
    }

    private func stopProgressAnimation() {
        progressTimer?.invalidate()
        progressTimer = nil
        progressAnimationCompletion = nil
    }

    private func stopGlowAnimation() {
        glowTimer?.invalidate()
        glowTimer = nil
        glowAnimationCompletion = nil
    }

    private func stopFlowTimer() {
        flowTimer?.invalidate()
        flowTimer = nil
    }

    private func tickFlowTimer() {
        // Color/chomp use a seamless small loop; pellets use a continuous, non-looping
        // clock so they simply keep flowing right->left and dissolve at the head.
        let dt = 1.0 / 30.0
        flowPhase = (flowPhase + dt / 4.6).truncatingRemainder(dividingBy: 1)
        pelletSeconds += dt
        metal.advancePellets(seconds: pelletSeconds, cellsPerSecond: pelletCellsPerSecond)
        metal.advanceFlow(to: flowPhase)
    }

    func advanceFlow(to phase: CGFloat) {
        flowPhase = min(max(phase, 0), 1)
        metal.advanceFlow(to: flowPhase)
    }
}
