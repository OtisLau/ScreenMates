# ScreenMates 📱

A social accountability app for iOS that tracks daily screen time and syncs it with friends in real-time. Stay accountable, build streaks, and compete on a live leaderboard!

## ✨ Features

- **🎯 Track Screen Time:** Monitor time spent on distracting apps
- **👥 Social Groups:** Join friends and see everyone's usage
- **🔥 Streak Counter:** Build momentum by staying under your limit
- **📊 Live Leaderboard:** Real-time rankings of all group members
- **🔔 Smart Notifications:** Warnings at 75%, 90%, and when over limit
- **☁️ CloudKit Sync:** Automatic syncing across the group
- **💪 Offline Support:** Works offline with local caching
- **🛠️ Debug Tools:** Comprehensive testing and troubleshooting

## 🏗️ Architecture

Built with a clean, modular architecture:

- **Views/** - 9 SwiftUI view files (40-150 lines each)
- **Managers/** - 3 business logic managers (CloudKit, Notifications, Streaks)
- **Models/** - 3 data models (UserProfile, SocialGroup, MemberData)
- **Utilities/** - 3 helper files (Constants, Date formatting, Error handling)

Total: **20 focused files**, each under 200 lines for easy maintenance.

## 🚀 Quick Start

1. Open `screenmates.xcodeproj` in Xcode
2. Build and run on your device (iOS 16.0+)
3. Follow the onboarding flow:
   - Grant Screen Time permissions
   - Select apps to track
   - Choose a username
   - Create or join a group
4. Start tracking!

See **[QUICK_START.md](QUICK_START.md)** for detailed instructions.

## 📚 Documentation

- **[QUICK_START.md](QUICK_START.md)** - How to use the app
- **[ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)** - How the code works
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - What was built

## 🔧 Tech Stack

- **Language:** Swift / SwiftUI
- **Backend:** CloudKit (Public Database)
- **Frameworks:** 
  - DeviceActivity (screen time tracking)
  - FamilyControls (permission management)
  - UserNotifications (local notifications)
  - BackgroundTasks (background syncing)
- **Storage:** UserDefaults (App Group for data sharing)

## 🧪 Test Mode

Currently configured for easy testing:
- **1 minute = 1 block** (production: 15 minutes)
- **Daily goal: 12 blocks** (12 minutes in test mode)

Change in `AppConstants.swift` to switch to production mode.

## 📊 Project Stats

| Metric | Value |
|--------|-------|
| Total Files | 20 Swift files |
| Total Lines | ~1,630 |
| Avg Lines/File | ~82 |
| Views | 9 files |
| Managers | 3 files |
| Models | 3 files |
| Utilities | 3 files |

## 🎯 Design Philosophy

**Functionality over visual polish.**

This app prioritizes:
- ✅ Robust error handling
- ✅ Reliable data syncing
- ✅ Clean code organization
- ✅ Comprehensive debug tools
- ✅ Offline support

Not focused on:
- ❌ Fancy animations
- ❌ Complex visual designs
- ❌ Unnecessary features

## 🤝 How It Works

### The Flow

1. **DeviceActivity Extension** monitors app usage
2. Increments blocks in **App Group UserDefaults**
3. **CloudKitManager** syncs to CloudKit
4. **Dashboard** displays live leaderboard
5. **NotificationManager** alerts at thresholds
6. **StreakManager** tracks consecutive days under limit

### The Components

- **Extension:** Lightweight, increments counters only
- **Main App:** Handles all networking and UI
- **Background Tasks:** Syncs even when app is closed
- **Local Cache:** Shows data immediately, fetches in background

## 🐛 Debugging

Built-in debug menu accessible via Settings:
- View all UserDefaults values
- Force manual sync
- Simulate midnight reset
- Send test notifications
- Clear local data
- View CloudKit status

## 📱 Requirements

- iOS 16.0 or later
- Screen Time enabled
- iCloud account
- Internet connection (for syncing)

## 🔐 Privacy

- **No activity logs:** Only tracks total time, not which apps
- **No screenshots:** Never captures screen content
- **User controlled:** You choose what gets tracked
- **Group only:** Data only shared with your group

## 🎓 Learning Resources

The codebase is designed for learning:
- Small, focused files (avg 82 lines)
- Clear separation of concerns
- Self-documenting code
- Comprehensive comments
- Example patterns throughout

Start with:
1. `ContentView.swift` - See the routing logic
2. `CloudKitManager.swift` - Understand data flow
3. `DashboardView.swift` - See reactive UI
4. `AppConstants.swift` - View configuration

## 🚧 Future Enhancements (Optional)

- Historical data tracking
- Weekly/monthly summaries
- Adjustable group goals
- Custom notification schedules
- Export data
- User avatars

## 📄 License

Private project. All rights reserved.

## 🙏 Acknowledgments

Built with modern Swift best practices:
- Async/await for concurrency
- Published properties for reactivity
- Singleton managers for state
- App Groups for data sharing

---

**Ready to start?** Check out [QUICK_START.md](QUICK_START.md)!

**Want to understand the code?** Read [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)!

**Curious what was built?** See [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)!
