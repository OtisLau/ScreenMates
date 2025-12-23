# ScreenMates - Architecture Guide

## 🏗️ How It All Works Together

### Data Flow

```
DeviceActivityMonitor (Extension)
         ↓
    App Group UserDefaults
         ↓
    CloudKitManager ←→ CloudKit (Public Database)
         ↓
    Published Properties
         ↓
    SwiftUI Views (Auto-update)
```

---

## 🔄 User Journey

### 1. First Launch → Onboarding
- **OnboardingView** shows
- User grants FamilyControls permission
- User selects distracting apps
- DeviceActivity monitoring starts
- → **UsernameSetupView** shows

### 2. Username Setup
- User enters display name
- Saved to `CloudKitManager.myDisplayName`
- → **GroupSelectionView** shows

### 3. Group Selection
- User either:
  - **Joins group** (validates code with CloudKit)
  - **Creates group** (generates 6-char code)
- **GroupShareSheet** shown after creation
- → **DashboardView** shows

### 4. Main App → Dashboard
- Shows **UserStatsCard** at top
- Shows **Leaderboard** below
- Auto-refreshes every 60 seconds
- Pull-to-refresh available
- Settings button in toolbar

---

## 📦 Manager Responsibilities

### CloudKitManager
**Purpose:** All CloudKit operations + local caching

**Key Methods:**
- `createGroup()` - Generate new group
- `validateGroup()` - Check if group exists
- `joinGroup()` - Set current group
- `updateMyProfile()` - Upload current stats
- `fetchGroupData()` - Download leaderboard
- `performBackgroundCheck()` - Background sync

**Published Properties:**
- `@Published var groupMembers: [MemberData]`
- `@Published var isLoading: Bool`
- `@Published var lastError: ErrorHandler.AppError?`

### StreakManager
**Purpose:** Track consecutive days under limit

**Key Methods:**
- `updateStreak()` - Check and increment/reset
- `isUnderLimit()` - Check current status
- `resetStreak()` - Manual reset (debug)

**Storage:**
- `currentStreak` → UserDefaults
- `lastCheckDate` → UserDefaults
- Synced to CloudKit via `CloudKitManager`

### NotificationManager
**Purpose:** Local notification scheduling

**Key Methods:**
- `requestPermission()` - Ask for permission
- `updateNotifications()` - Schedule based on usage
- `scheduleDailyResetNotification()` - Midnight message
- `sendTestNotification()` - Debug testing

**Triggers:**
- 75% threshold
- 90% threshold
- Over limit
- Daily reset (midnight)

---

## 💾 Data Storage

### UserDefaults (App Group)
**Suite:** `group.com.otishlau.screenmates`

**Keys (from AppConstants):**
- `DailyBlocksUsed` (Int) - Current blocks today
- `LastBlockDate` (Date) - Last increment time
- `CurrentStreak` (Int) - Days under limit
- `LastCheckDate` (Date) - Last streak check
- `CachedLeaderboardData` (JSON) - Cached members
- `NotificationsEnabled` (Bool) - User preference

### AppStorage (Main App)
**Keys:**
- `my_user_id` (String) - 8-char UUID
- `my_display_name` (String) - Username
- `my_group_id` (String) - Current group
- `is_setup_done` (Bool) - Onboarding complete
- `username_set` (Bool) - Username entered

### CloudKit (Public Database)

**UserProfile Record:**
```swift
{
  user_id: String
  display_name: String
  group_id: String
  blocks_used: Int
  streak: Int
  last_active_date: Date
  last_updated: Date
}
```

**SocialGroup Record:**
```swift
{
  group_id: String
  daily_goal_blocks: Int
  member_count: Int
  created_date: Date
}
```

---

## 🎨 View Architecture

### ContentView (Traffic Controller)
**Role:** Route to correct screen based on state

**Logic:**
```swift
if !isSetupDone → OnboardingView
else if !usernameSet → UsernameSetupView
else if myGroupID.isEmpty → GroupSelectionView
else → DashboardView
```

### Component Hierarchy
```
DashboardView
├── UserStatsCard
│   ├── Time used display
│   ├── Status indicator
│   └── Stats (streak, countdown, percentage)
└── Leaderboard
    └── LeaderboardRow (for each member)
        ├── Display name
        ├── Relative time
        ├── Streak indicator
        └── Block count
```

---

## ⚡ Real-Time Updates

### Timer-Based (Dashboard)
```swift
Timer.publish(every: 60, on: .main, in: .common)
  → fetchGroupData()
```

### Published Properties (Reactive)
```swift
@StateObject var cloudManager = CloudKitManager.shared
// Auto-updates when cloudManager.groupMembers changes
ForEach(cloudManager.groupMembers) { ... }
```

### Pull-to-Refresh
```swift
.refreshable {
  await refreshData()
}
```

---

## 🛠️ Error Handling Flow

### 1. Error Occurs
CloudKit operation fails → Error caught

### 2. Error Mapped
```swift
func handleCloudKitError(_ error: Error) -> ErrorHandler.AppError {
  // Maps CKError to AppError
}
```

### 3. Error Stored
```swift
cloudManager.lastError = appError
```

### 4. Alert Shown
```swift
.alert("Error", isPresented: $showError) {
  Button("OK") { }
} message: {
  Text(errorMessage)
}
```

---

## 🔧 Debug Workflow

### 1. Access Debug Menu
Dashboard → Settings → Debug Menu

### 2. View Current State
- UserDefaults values
- CloudKit IDs
- Last sync time
- Notification status

### 3. Test Actions
- Manual sync
- Simulate midnight
- Send test notification
- Clear local data

---

## 📱 Background Task Flow

### 1. App Goes to Background
```swift
.onChange(of: scenePhase) { _, newPhase in
  if newPhase == .background {
    scheduleAppRefresh()
  }
}
```

### 2. Task Scheduled
```swift
BGAppRefreshTaskRequest
  earliestBeginDate: 15 minutes from now
```

### 3. System Wakes App
```swift
.backgroundTask(.appRefresh("...")) {
  await cloudManager.performBackgroundCheck()
}
```

### 4. Sync Performed
- Read `DailyBlocksUsed` from UserDefaults
- Upload to CloudKit UserProfile
- Return success/failure

---

## 🎯 Key Design Decisions

### Why App Group?
- DeviceActivity extension runs in separate process
- Needs to share data with main app
- App Groups enable shared UserDefaults

### Why No Networking in Extension?
- Extensions should be lightweight
- Networking drains battery
- Main app handles all CloudKit operations

### Why Published Properties?
- SwiftUI observes changes automatically
- Views update when data changes
- No manual UI updates needed

### Why Singleton Managers?
- Single source of truth
- Easy to access from any view
- Consistent state across app

### Why Local Caching?
- Show data immediately on app open
- Work offline
- Reduce network calls
- Better user experience

---

## 📊 Performance Considerations

### Optimizations
- ✅ Cache leaderboard data locally
- ✅ Debounce frequent updates
- ✅ Use async/await for concurrency
- ✅ Retry logic prevents repeated failures
- ✅ Optimistic updates (update UI first)

### Trade-offs
- Leaderboard may be slightly stale (up to 60s)
- Background tasks may not run exactly on time
- Notifications are local (not push)
- Public database has quotas

---

## 🚀 Extending the App

### To Add a New Feature:

1. **Choose location:**
   - UI component? → Create new View file
   - Business logic? → Add to Manager or create new Manager
   - Data model? → Add to Models
   - Helper function? → Add to Utilities

2. **Keep files focused:**
   - Each file should have ONE responsibility
   - Max ~200 lines per file
   - Extract components when views get large

3. **Follow patterns:**
   - Use `@StateObject` for managers
   - Use `@Published` for reactive properties
   - Use AppConstants for constants
   - Use ErrorHandler for errors

---

## 🎓 Learning the Codebase

### Start here:
1. **ContentView.swift** - Understand the routing
2. **CloudKitManager.swift** - See how data flows
3. **DashboardView.swift** - See how UI updates
4. **AppConstants.swift** - See configuration

### Then explore:
- Views/ - All UI screens
- Managers/ - Business logic
- Models/ - Data structures
- Utilities/ - Helper functions

---

## 🏁 Summary

The architecture is designed to be:
- **Modular** - Small, focused files
- **Maintainable** - Clear separation of concerns
- **Scalable** - Easy to add new features
- **Testable** - Isolated business logic
- **Understandable** - Self-documenting code

Each piece has a clear role and works together seamlessly! 🎉
