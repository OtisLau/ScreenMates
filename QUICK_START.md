# ScreenMates - Quick Start Guide

## 🚀 Getting Started

### 1. Build & Run
```bash
# Open project in Xcode
open screenmates.xcodeproj

# Select your device
# Build and run (⌘R)
```

### 2. First Launch Flow

**Step 1: Onboarding**
- Tap "1. Grant Permissions" → Accept Screen Time permissions
- Tap "2. Select Distracting Apps" → Choose apps to track
- Tap "3. Save & Continue"

**Step 2: Choose Username**
- Enter your display name (1-20 characters)
- Tap "Continue"

**Step 3: Join/Create Group**
- Option A: Enter a friend's group code → "Join Group"
- Option B: Tap "Create New Group" → Share the code with friends

**Step 4: Dashboard**
- You're in! Start using the app

---

## 📱 Using the App

### Dashboard
- **Top Card:** Your stats (blocks used, streak, time until reset)
- **Leaderboard:** All group members ranked by usage
- **Pull down:** Refresh data manually
- **Gear icon:** Open settings

### What Gets Tracked
- Every minute you use selected apps = 1 block (test mode)
- Data syncs to CloudKit automatically
- Friends see your usage in real-time

### Notifications
You'll get notified when:
- You reach 75% of daily limit (9/12 blocks)
- You reach 90% of daily limit (11/12 blocks)
- You go over the limit
- New day starts (with streak update)

---

## ⚙️ Settings

### Profile
- **Edit Name:** Change your display name
- **View IDs:** See your user ID and group ID

### Notifications
- **Toggle:** Enable/disable notifications
- **Settings Link:** Open iOS Settings if permission needed

### Group Actions
- **Leave Group:** Exit current group (confirmation required)

### App Actions
- **Reset App:** Delete all data and start over (confirmation required)

### Debug Menu
- **View Data:** See UserDefaults and CloudKit values
- **Manual Sync:** Force upload/download now
- **Midnight Reset:** Simulate next day (reset blocks to 0)
- **Test Notification:** Send test notification
- **Clear Data:** Remove local cached data

---

## 🔧 Test Mode

### Current Settings
- **1 minute = 1 block** (for easy testing)
- **Daily goal:** 12 blocks (12 minutes)

### To Test:
1. Open tracked apps (Instagram, TikTok, etc.)
2. Use for 1 minute
3. Check dashboard → blocks should increment
4. Wait 60 seconds for auto-refresh, or pull-to-refresh

### To Switch to Production Mode:
Edit `AppConstants.swift`:
```swift
static let currentBlockSize = 15 // Change from 1 to 15
static let isTestMode = false // Change from true to false
```
This makes 15 minutes = 1 block (production setting)

---

## 🐛 Debugging

### Data Not Syncing?
1. Check internet connection
2. Open Settings → Debug Menu
3. Tap "Force Sync Now"
4. Check "Last Sync" time

### Blocks Not Incrementing?
1. Make sure Screen Time permissions granted
2. Check Debug Menu → "Daily Blocks Used"
3. Try "Simulate Midnight Reset" to start fresh
4. Re-select apps in Settings → Screen Time

### Notifications Not Working?
1. Settings → Notifications
2. Enable in iOS Settings if needed
3. Debug Menu → "Send Test Notification"

### Group Not Found?
- Double-check the group code (case-sensitive)
- Ask friend to reshare the code
- Make sure friend created the group successfully

---

## 📊 Understanding Your Stats

### Blocks Used
- Number of time blocks consumed today
- Resets at midnight automatically
- 1 block = 1 minute (test mode)

### Streak
- Consecutive days under the limit
- Increments if you're under limit at midnight
- Resets if you go over

### Status Colors
- **Green:** Under limit, doing great!
- **Orange:** Approaching limit (75-90%)
- **Red:** Over limit or almost over (90%+)

### Relative Time
- "Just now" - Updated within last minute
- "5m ago" - Updated 5 minutes ago
- "2h ago" - Updated 2 hours ago
- "Yesterday" - Updated yesterday

---

## 👥 Using with Friends

### Create a Group
1. Tap "Create New Group"
2. Note the 6-character code (e.g., "ABC123")
3. Tap "Share Group Code"
4. Send via Messages, WhatsApp, etc.

### Join a Friend's Group
1. Get the group code from your friend
2. Enter it in the text field
3. Tap "Join Group"
4. Wait for validation
5. See your friend on the leaderboard!

### View Group Progress
- Leaderboard shows everyone in your group
- Members ranked by blocks used (highest first)
- See each person's streak
- See when they last updated

---

## 🎯 Tips & Best Practices

### For Accountability
- Share daily screenshots with friends
- Celebrate streaks together
- Set group goals
- Use as friendly competition

### For Accurate Tracking
- Select all distracting apps during setup
- Keep the app installed (don't delete)
- Grant all permissions
- Check in daily

### For Privacy
- App never tracks WHICH apps you use
- Only tracks TOTAL TIME spent
- No screenshots or activity logs
- You control what's tracked

---

## 🔄 Daily Reset

### What Happens at Midnight?
1. **Blocks reset** to 0 automatically
2. **Streak updates** (increments if under limit)
3. **Notification sent** with streak status
4. **New day starts** fresh

### The Extension Handles It
- DeviceActivityMonitorExtension checks date
- Resets `DailyBlocksUsed` if new day
- No user action needed
- Works even if app is closed

---

## 🆘 Troubleshooting

### "Group Not Found"
- Group code might be wrong
- Group might have been deleted
- Check with friend who created it

### "Permission Denied"
- Go to iOS Settings
- Screen Time → Always Allowed
- Enable ScreenMates
- Restart app

### "Network Error"
- Check WiFi/cellular connection
- Try again in a few seconds
- Data will sync when connection restored

### "Over Limit" but Blocks Look Wrong
- Check Debug Menu for actual count
- Try "Simulate Midnight Reset"
- May need to restart monitoring
- Contact support if persists

---

## 📱 System Requirements

- iOS 16.0 or later
- Screen Time enabled
- iCloud account (for CloudKit)
- Internet connection (for syncing)

---

## 🎓 Next Steps

### Learn More
- Read `IMPLEMENTATION_SUMMARY.md` for technical details
- Read `ARCHITECTURE_GUIDE.md` to understand the code
- Explore the codebase in Xcode

### Customize
- Edit daily goal in CloudKit
- Adjust notification thresholds
- Add more stats to dashboard
- Create your own features!

---

## 🎉 You're Ready!

Start tracking your screen time with friends and building better habits together!

Need help? Check the Debug Menu or review the architecture guide.
