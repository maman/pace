# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Pace

Pace is a macOS menu-bar app (SwiftUI, macOS 15+) that provides instant desktop space switching — no animation delay. It works via two mechanisms: global hotkeys (Carbon Event API) and trackpad gesture interception (CGEvent tap). It is a Swift rewrite inspired by [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), whose C-based touchpad logic lives in `ref/` as a reference implementation.

## Project generation (Tuist)

`Project.swift` at the repo root is the source of truth. The `Pace.xcodeproj` / `Pace.xcworkspace` are generated and git-ignored — never hand-edit them.

```bash
# Regenerate the Xcode project without opening it
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

# Run/restart the app locally (handles generate + build + launch)
./run-menubar.sh

# Stop a running instance
./stop-menubar.sh
```

Tuist is pinned via `mise.toml`.

## Build & Test Commands

```bash
# Build
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme Pace -configuration Debug -derivedDataPath build -destination 'platform=macOS'

# Run all tests
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme Pace -configuration Debug -derivedDataPath build -destination 'platform=macOS'

# Run a single test class
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme Pace -configuration Debug -derivedDataPath build -destination 'platform=macOS' \
  -only-testing:PaceTests/GestureEngineTests

# Run a single test method
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme Pace -configuration Debug -derivedDataPath build -destination 'platform=macOS' \
  -only-testing:PaceTests/GestureEngineTests/testBeganSetsTracking
```

Build output goes to `build/` (project-local derived data).

## Build Phase: Debug Accessibility Reset

A pre-build script phase (declared in `Project.swift`) runs `tccutil reset Accessibility ${PRODUCT_BUNDLE_IDENTIFIER}` on Debug builds. This revokes the app's Accessibility permission each build so you can test the permission prompt flow from scratch.

## Architecture

### Startup flow

`PaceApp` (@main) → `PaceAppDelegate` creates `AppState` + `PaceCoordinator` → `coordinator.start(appState:)` wires everything up.

### Key components

**PaceCoordinator** — the central orchestrator. Owns the lifecycle of hotkey registration, gesture engine, shortcut recording, and accessibility permission checks. It observes `AppState` changes via `withObservationTracking` and re-syncs subsystems. All dependencies are protocol-injected for testability.

**GestureEngine** — installs a `CGEvent.tapCreate` on event types 29/30 (private gesture events) to intercept horizontal dock swipes. The core logic is extracted into a pure function `processGestureEvent(...)` that takes event fields + mutable `SwipeState` and returns a `CallbackAction` enum (`.suppress`, `.passthrough`, `.fireSwitch`). To switch spaces, it posts synthetic dock swipe events with high velocity via `postSyntheticSwitch`. The `passthrough` counter lets its own synthetic events flow through the tap without re-interception.

**SpaceQuery** — queries current space index and count via private `CGS*` functions resolved through `dlsym`. `CGSFunctions` is an injectable struct so tests can supply fake implementations. `canSwitch(direction:)` prevents switching past the first/last space.

**HotKeyManager** — wraps the Carbon `RegisterEventHotKey` API. The `@convention(c)` callback hardcodes `HotKeyManager.shared` (can't capture context), so the protocol abstraction exists purely for test mocking.

**GlobalEventTapRecorder** — another CGEvent tap for recording keyboard shortcuts in the Settings UI. Intercepts key-down and mouse-click events; mouse clicks cancel recording, key presses are forwarded to the coordinator.

**AppState** — `@Observable` model persisting user preferences to `UserDefaults` (keys prefixed `pace.*`). Hotkey combinations are JSON-encoded. Duplicate shortcut validation prevents left/right from being the same combo.

**HotkeyCombination** — value type representing a keyboard shortcut. Stores Carbon-style `keyCode`/`modifiers` (UInt32) plus display and key-equivalent strings. `from(event:)` is the factory; `parse(...)` is the pure testable core.

### UI

Menu-bar only app (`LSUIElement = YES`). `MenuBarExtra` provides the dropdown; `Settings` scene holds `ShortcutSettingsView` for hotkey recording.

### Concurrency model

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide. GestureEngine's C callback and `switchSpace` are explicitly `nonisolated` since they run on the main CFRunLoop but outside Swift's actor isolation.

### Testing approach

Tests exercise pure logic: `processGestureEvent`, `extractSpaceInfo`, `HotkeyCombination.parse`, `AppState` persistence, and `PaceCoordinator`'s state machine. All system interactions are behind protocols (`GestureEngineProtocol`, `HotKeyManagerProtocol`, `PermissionChecking`, `EventRecorderProtocol`, `ActivationObserving`) with mocks in `PaceTests/Mocks.swift`.

### Reference code

`ref/instant-space-switcher/` and `ref/iss-touchpad/` contain the original C/Swift projects. GestureEngine's callback logic is a direct port of `iss.c:183-233`; comments in the code reference the original line numbers.
