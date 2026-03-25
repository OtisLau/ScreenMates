# ScreenMates

ScreenMates is an iOS app that tracks daily screen time and shares totals with a friend group.

## What It Does

- Tracks usage in blocks throughout the day.
- Uploads your latest total to CloudKit.
- Shows group rankings in the app and widget.
- Works in the background through a DeviceActivity extension.

## How It Works

1. User grants Screen Time permission.
2. DeviceActivity extension receives threshold events.
3. Extension updates local counters in App Group storage.
4. App/extension sync totals to CloudKit (`UserProfile` records).
5. App and widget read cached group data and render leaderboard state.

## Current Tracking Mode

- All-activity monitoring is enabled.
- Test profile is currently configured for `1 min/block` and `96 events/batch`.

## Project Layout

- `screenmates/` main iOS app (SwiftUI UI, managers, models, utilities)
- `ScreenTimeMonitor/` DeviceActivity monitor extension
- `MyAppWidget/` home screen widget

## Requirements

- iOS 17+
- Screen Time enabled
- iCloud account (for group sync)

## Run

1. Open `screenmates.xcodeproj` in Xcode.
2. Build and run on a real device.
3. Complete onboarding and grant Screen Time permission.

See `QUICK_START.md` for setup details.
