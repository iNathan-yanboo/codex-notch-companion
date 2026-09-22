# Native Notch Contour Renderer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the clipped SwiftUI quota strokes with a pixel-precise Core Animation contour that hugs the compact notch silhouette and visibly renders gradient progress, static glow, and hover shimmer.

**Architecture:** A pure `NotchContourGeometry` model owns the mirrored left/right paths and clamps progress values. An `NSViewRepresentable` hosts an AppKit layer-backed view whose `CAShapeLayer` tracks, `CAGradientLayer` masks, glow layers, and shimmer layers all consume the same geometry. SwiftUI continues to own expansion, details, and hover state, but no longer clips the contour renderer.

**Tech Stack:** Swift 5, SwiftUI, AppKit, QuartzCore/Core Animation, XCTest, Xcode macOS test runner.

## Global Constraints

- Compact black silhouette remains centered on the physical 185pt notch and stays close to 225pt wide and 40pt tall.
- Left progress represents Codex 5-hour `used_percent`; right progress represents weekly `used_percent`.
- Both progress paths start from their outer top edge, stay inside the 20pt of side overflow that remains visible beside the physical notch, and advance downward/inward as mirror images.
- The full inactive contour remains visible while active progress is trimmed independently.
- AIUsage and Local usage stay separate and read-only; this work must not trigger uploads.
- Static glow must remain visible without hover; hover adds a moving gradient highlight without moving the progress line.
- Compact, hover, and expanded states require fresh real-screen screenshots before completion.

---

### Task 1: Make contour geometry deterministic

**Files:**
- Create: `macos/CodexNotchCompanion/NotchContourGeometry.swift`
- Modify: `macos/CodexNotchCompanionTests/UsageModelsTests.swift`

**Interfaces:**
- Produces: `NotchContourGeometry(size:bodyInset:strokeInset:)`
- Produces: `leftPath: CGPath`, `rightPath: CGPath`, `bodyPath: CGPath`
- Produces: `static func normalizedProgress(_ percent: Double) -> CGFloat`

- [ ] **Step 1: Write failing geometry tests**

```swift
func testContourGeometryIsMirroredAndHugsBodyEdge() {
    let geometry = NotchContourGeometry(
        size: CGSize(width: 233, height: 44),
        bodyInset: 4,
        strokeInset: 2
    )
    XCTAssertEqual(geometry.leftStart.x, 6, accuracy: 0.001)
    XCTAssertEqual(geometry.rightStart.x, 227, accuracy: 0.001)
    XCTAssertEqual(geometry.leftStart.y, 0, accuracy: 0.001)
    XCTAssertEqual(geometry.rightStart.y, 0, accuracy: 0.001)
    XCTAssertEqual(geometry.leftEnd.x, 22, accuracy: 0.001)
    XCTAssertEqual(geometry.rightEnd.x, 211, accuracy: 0.001)
    XCTAssertEqual(geometry.leftEnd.y, geometry.rightEnd.y, accuracy: 0.001)
}

func testContourProgressClampsToVisibleRange() {
    XCTAssertEqual(NotchContourGeometry.normalizedProgress(-3), 0)
    XCTAssertEqual(NotchContourGeometry.normalizedProgress(58), 0.58, accuracy: 0.001)
    XCTAssertEqual(NotchContourGeometry.normalizedProgress(140), 1)
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
xcodebuild -project macos/CodexNotchCompanion.xcodeproj \
  -scheme CodexNotchCompanion \
  -destination 'platform=macOS' \
  -only-testing:CodexNotchCompanionTests/UsageModelsTests test
```

Expected: compilation fails because `NotchContourGeometry` does not exist.

- [ ] **Step 3: Implement the pure geometry model**

The body path starts at the screen top, uses one continuous bottom-left and bottom-right cubic corner, and stays inset from the transparent panel margin. The two progress paths are generated from mirrored cubic curves and terminate at the inner edge of each 20pt visible side-overflow region; no progress geometry is hidden behind the physical notch.

- [ ] **Step 4: Re-run the focused test and verify GREEN**

Expected: all geometry and existing usage-model tests pass.

---

### Task 2: Replace SwiftUI strokes with a Core Animation renderer

**Files:**
- Create: `macos/CodexNotchCompanion/NotchContourView.swift`
- Modify: `macos/CodexNotchCompanion/NotchRootView.swift`
- Modify: `macos/CodexNotchCompanion/AppDelegate.swift`
- Modify: `macos/CodexNotchCompanion/UsageModels.swift`
- Modify: `macos/project.yml`

**Interfaces:**
- Consumes: `NotchContourGeometry`
- Produces: `NotchContourView(fiveHourPercent:weeklyPercent:hovering:expanded:)`
- Produces: `NotchMetrics.compactPanelSize(notchWidth:safeTop:)`
- Produces: `NotchMetrics.compactBodyFrame(panelSize:)`

- [ ] **Step 1: Write failing panel/body metric tests**

```swift
func testCompactPanelLeavesFourPointGlowMarginAroundBody() {
    let panel = NotchMetrics.compactPanelSize(notchWidth: 185, safeTop: 32)
    let body = NotchMetrics.compactBodyFrame(panelSize: panel)
    XCTAssertEqual(panel, CGSize(width: 233, height: 44))
    XCTAssertEqual(body, CGRect(x: 4, y: 0, width: 225, height: 40))
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Expected: compilation fails because the new metric APIs do not exist.

- [ ] **Step 3: Implement the layer renderer**

Create one layer-backed `NSView` with these layers, all using the same left/right paths:

1. full inactive track at 1.2pt;
2. 9pt low-alpha active glow;
3. 4.5pt medium-alpha active glow;
4. 2.7pt active line masked by separate warm and mint `CAGradientLayer`s;
5. hover-only 6pt soft shimmer plus 2.8pt white core, animated with `strokeStart`/`strokeEnd` over the active range.

Set `masksToBounds = false` on the host and every glow container. Update paths and frames with actions disabled, and only animate shimmer presentation values.

- [ ] **Step 4: Integrate the renderer without root clipping**

Render the black body in its own rounded contour shape inside a transparent panel margin. Keep details clipped to the black body, but place `NotchContourView` above that clip. Pass hover and expanded state through the representable coordinator.

- [ ] **Step 5: Re-run tests and build**

Run the focused test, then:

```bash
xcodebuild -project macos/CodexNotchCompanion.xcodeproj \
  -scheme CodexNotchCompanion \
  -destination 'platform=macOS' build
```

Expected: tests pass and the app builds without Swift warnings or errors.

---

### Task 3: Visual QA and iterative correction

**Files:**
- Modify as evidence requires: `macos/CodexNotchCompanion/NotchContourGeometry.swift`
- Modify as evidence requires: `macos/CodexNotchCompanion/NotchContourView.swift`
- Modify as evidence requires: `macos/CodexNotchCompanion/NotchRootView.swift`
- Create screenshots: `artifacts/native-qa/01-compact.png`, `02-hover.png`, `03-expanded.png`

**Interfaces:**
- Consumes: built `CodexNotchCompanion.app`
- Produces: accepted screenshots for all three states

- [ ] **Step 1: Build, restart, and capture compact state**

The screenshot must prove the panel is top-aligned, approximately physical-notch-sized, with full mirrored tracks, visible warm/mint gradients, continuous glow, and no clipped line caps.

- [ ] **Step 2: Hover and capture after animation stabilizes**

The screenshot must prove the line thickens slightly and a gradient-white highlight appears along the active line while the progress endpoints remain fixed.

- [ ] **Step 3: Expand and capture**

The screenshot must prove the enlarged panel is one continuous top-attached notch, not a detached card, and the header contour remains attached to the panel edge.

- [ ] **Step 4: Inspect every screenshot and iterate**

Reject blank, cropped, stale-build, or visually mismatched screenshots. Adjust one geometry or layer parameter per iteration and repeat the affected state until all acceptance checks hold.

- [ ] **Step 5: Run final verification**

```bash
xcodebuild -project macos/CodexNotchCompanion.xcodeproj \
  -scheme CodexNotchCompanion \
  -destination 'platform=macOS' test
git diff --check
```

Expected: all tests pass, diff check exits 0, and all three accepted screenshots show the requested state.

- [ ] **Step 6: Commit the focused change**

```bash
git add macos docs/superpowers/plans/2026-07-11-native-notch-contour-renderer.md artifacts/native-qa
git commit -m "fix: rebuild native notch contour renderer"
```
