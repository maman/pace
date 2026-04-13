# Pace

Instant desktop space switching on macOS. No animation delay.

Pace sits in your menu bar and lets you switch spaces instantly via **global hotkeys** or **trackpad swipes** — bypassing the default macOS transition animation.

## Requirements

- macOS 14+
- Accessibility permission (for trackpad gesture interception and shortcut recording)

## How it works

Pace intercepts horizontal dock swipe gestures via a CGEvent tap and replaces them with synthetic high-velocity swipe events, effectively skipping the animation. Global hotkeys are registered through the Carbon Event API and trigger the same synthetic switch.

This project merges logic from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (hotkey-based switching) and [iss](https://github.com/joshuarli/iss) (gesture interception) into a single Swift menu bar app.

## Build

Pace uses [Tuist](https://tuist.io) to generate the Xcode project from `Project.swift` and `Tuist/Package.swift`. Tuist is pinned via `mise.toml`.

```bash
# Resolve SPM dependencies (required once per checkout / after pulling changes
# to Tuist/Package.swift or Tuist/Package.resolved)
tuist install

# Generate the Xcode project (no Xcode window)
tuist generate --no-open

# Build
tuist xcodebuild build -scheme Pace -configuration Debug \
  -derivedDataPath build -clonedSourcePackagesDirPath build/SourcePackages \
  -destination 'platform=macOS'

# Run locally (handles tuist install + generate + build + launch internally)
./run-menubar.sh
```

## Test

```bash
tuist install
tuist xcodebuild test -scheme Pace -configuration Debug \
  -derivedDataPath build -clonedSourcePackagesDirPath build/SourcePackages \
  -destination 'platform=macOS'
```

## License

MIT. See [LICENSE](LICENSE) for details and upstream attributions.
