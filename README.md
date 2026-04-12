# Pace

Instant desktop space switching on macOS. No animation delay.

Pace sits in your menu bar and lets you switch spaces instantly via **global hotkeys** or **trackpad swipes** — bypassing the default macOS transition animation.

## Requirements

- macOS 15+
- Accessibility permission (for trackpad gesture interception and shortcut recording)

## How it works

Pace intercepts horizontal dock swipe gestures via a CGEvent tap and replaces them with synthetic high-velocity swipe events, effectively skipping the animation. Global hotkeys are registered through the Carbon Event API and trigger the same synthetic switch.

This project merges logic from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (hotkey-based switching) and [iss](https://github.com/joshuarli/iss) (gesture interception) into a single Swift menu bar app.

## Build

```bash
xcodebuild -project Pace.xcodeproj -scheme Pace -configuration Debug -derivedDataPath build
```

## Test

```bash
xcodebuild test -project Pace.xcodeproj -scheme Pace -derivedDataPath build
```
