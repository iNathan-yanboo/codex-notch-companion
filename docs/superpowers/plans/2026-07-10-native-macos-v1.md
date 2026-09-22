# Native macOS V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, installable macOS notch companion using the approved visual language and read-only local usage sources.

**Architecture:** `NSPanel` owns placement, size, and non-activating window behavior. SwiftUI renders the notch and expanded panel. `UsageStore` periodically reads the local aiusage HTTP endpoint and Local usage files through deterministic parsers.

**Tech Stack:** Swift 6, SwiftUI, AppKit, XCTest, XcodeGen.

## Global Constraints

- Read local aiusage and Local usage sources only; never write files, upload data, or run collectors.
- Use a non-activating panel at the screen top, not a normal document window.
- Keep AIUsage/Codex quota and local usage as separate values.
- Preserve a usable stale state when aiusage is unavailable.

---

### Task 1: Create the native project and parser contract

**Files:**
- Create: `macos/project.yml`
- Create: `macos/CodexNotchCompanion/UsageModels.swift`
- Create: `macos/CodexNotchCompanionTests/UsageModelsTests.swift`

- [ ] Write failing XCTest cases for `QuotaSnapshot.decode(data:)` and `LocalDailyUsage.latest(csv:)`.
- [ ] Run `xcodegen generate` then `xcodebuild test`; confirm parser symbols are absent.
- [ ] Implement decoding with safe fallbacks and test fixture strings.
- [ ] Run `xcodebuild test`; commit parser contract.

### Task 2: Add the native notch host and view

**Files:**
- Create: `macos/CodexNotchCompanion/AppDelegate.swift`
- Create: `macos/CodexNotchCompanion/CodexNotchCompanionApp.swift`
- Create: `macos/CodexNotchCompanion/NotchRootView.swift`

- [ ] Create a borderless non-activating `NSPanel` that anchors its top edge to `visibleFrame.maxY`.
- [ ] Add SwiftUI fold/expand state with top-edge-preserving resize and Esc collapse.
- [ ] Render static quota contours plus masked glow sweep and distinct AIUsage/Local usage detail blocks.
- [ ] Build the app with `xcodebuild`.

### Task 3: Attach read-only refresh and package

**Files:**
- Create: `macos/CodexNotchCompanion/UsageStore.swift`
- Modify: `macos/CodexNotchCompanion/NotchRootView.swift`
- Modify: `README.md`

- [ ] Fetch aiusage quotas with a 3-second timeout and retain previous values on failure.
- [ ] Read Local usage CSV/state without mutations and present only its separate latest daily values.
- [ ] Generate the Xcode project, build Release configuration, and document launch instructions.
