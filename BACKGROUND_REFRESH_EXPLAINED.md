# Background Refresh - How It Works

##  What We Have

Your app uses **iOS Background App Refresh** to upload screen time data to CloudKit even when the app is closed.

---

##  Current Setup

### 1. **Info.plist Configuration**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>        <!-- Background fetch capability -->
    <string>processing</string>   <!-- Background processing -->
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.otishlau.screenmates.refresh</string>  <!-- Your task ID -->
</array>
```

### 2. **Task Scheduling** (`screenmatesApp.swift`)
```swift
init() {
    // Schedule on app launch
    scheduleBackgroundRefresh()
}

.backgroundTask(.appRefresh("com.otishlau.screenmates.refresh")) {
    // Task runs here
    await cloudManager.performBackgroundCheck()
    
    // Re-schedule for next time
    scheduleBackgroundRefresh()
}
```

### 3. **What Happens**
1. **App launches** → Task scheduled for ~15 min
2. **App closes** → iOS keeps the schedule
3. **~15 min later** → iOS wakes up your app
4. **Background task runs** → Uploads blocks to CloudKit
5. **Task completes** → Re-schedules for another ~15 min
6. **Repeat** indefinitely

---

##  How iOS Background Refresh Works

### iOS Decides When to Run
Apple's iOS is in charge, not your app. The system considers:

 **More Likely to Run:**
- Device is charging
- Connected to WiFi
- Good battery level
- User frequently uses your app
- App has been backgrounded for a while

 **Less Likely to Run:**
- Battery is low
- Low Power Mode is ON
- Device is busy with other tasks
- Cellular data only (vs WiFi)
- App was just opened/closed

### Typical Behavior
- **You request:** Run every 15 minutes
- **iOS actually runs:** Every 20-60 minutes
- **First run:** Might take 30+ minutes after initial install
- **Charging + WiFi:** More frequent (closer to 15 min)
- **Battery only:** Less frequent (1+ hours)

---

##  How to Verify It's Working

### Method 1: Check Debug Menu (Easiest)
1. Use tracked apps with ScreenMates closed
2. Wait 30+ minutes
3. Open app → Settings → Debug Menu
4. Look at **"Last Background Sync"**
5. Tap **"Sync History"** to see all events

### Method 2: Ask a Friend
1. Have a friend in your group
2. Use tracked apps for 5 minutes
3. Close ScreenMates completely
4. Wait 30 minutes
5. Friend checks leaderboard → Should see your blocks update!

### Method 3: Watch Xcode Console
1. Run on device from Xcode
2. Use tracked apps
3. Close app
4. Leave device connected
5. Watch console for:
   ```
    Background task triggered at ...
    Background Sync: Uploaded X blocks
    Background check succeeded
   ```

---

##  Testing Tips

### Best Testing Conditions
```
 Device plugged in and charging
 Connected to WiFi
 Low Power Mode OFF
 Background App Refresh ON (Settings → General)
 App closed for 30+ minutes
 Device not actively in use
```

### Quick Test
```bash
1. Use tracked apps for 3 minutes (get 3 blocks)
2. Close ScreenMates completely
3. Plug device in, lock it
4. Wait 30 minutes
5. Open app → Debug Menu → Check "Last Background Sync"
   Should show recent timestamp!
```

### Force Test in Simulator (Advanced)
In Xcode, with app closed:
```
Debug → Simulate Background Fetch
```
Or terminal:
```bash
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.otishlau.screenmates.refresh"]
```

---

##  Troubleshooting

### "No background syncs happening"

**Check iOS Settings:**
1. Settings → General → Background App Refresh
2. Make sure it's ON globally
3. Make sure ScreenMates is enabled

**Check App Settings:**
1. Open ScreenMates
2. Settings → Notifications → Should be enabled
3. Debug Menu → Check if any errors

**Common Issues:**
-  Low Power Mode enabled → Disables background refresh
-  Not enough time passed → First run takes 30+ min
-  Device battery very low → iOS delays tasks
-  App just installed → iOS learning usage patterns

### "Syncs happening but not frequently"

This is **normal iOS behavior**. iOS decides when to run based on:
- Battery level
- Network conditions
- Device usage patterns
- Your app usage history

**To get more frequent syncs:**
- Keep device charging
- Stay on WiFi
- Use app regularly (iOS learns your patterns)
- Avoid Low Power Mode

### "All syncs showing as failed"

**Possible Causes:**
- No internet connection
- Not signed into iCloud
- CloudKit quota exceeded
- iCloud Drive disabled

**Solutions:**
- Check internet connection
- Sign into iCloud (Settings → [Your Name])
- Enable iCloud Drive
- Restart device

---

##  What Gets Synced

Every background refresh:
1.  Reads `DailyBlocksUsed` from shared UserDefaults
2.  Uploads to your CloudKit UserProfile
3.  Updates `last_updated` timestamp
4.  Syncs `streak` data
5.  Logs the sync event (visible in Debug Menu)

**Does NOT sync:**
-  Which apps you used (privacy)
-  Screen content
-  App activity logs

---

##  Technical Details

### Task Type: BGAppRefreshTask
- **Purpose:** Quick, lightweight syncs
- **Duration:** ~30 seconds max
- **Frequency:** iOS decides (you suggest 15 min)
- **Network:** Allowed
- **When:** Device can be in any state

### Why Not BGProcessingTask?
- Processing tasks run less frequently
- Better for large uploads, data processing
- App refresh is perfect for quick syncs

### Energy Impact
-  Very low (just uploads a few numbers)
-  Only runs when iOS determines it's OK
-  Doesn't drain battery significantly
-  iOS will throttle if battery is low

---

##  Understanding the Flow

### Full Lifecycle

```
1. User opens app
   └─> Schedule task for 15 min

2. User closes app
   └─> iOS keeps the schedule

3. 15-60 min later (iOS decides)
   └─> iOS wakes up app (invisible to user)
   └─> Background task runs
   └─> Reads UserDefaults
   └─> Uploads to CloudKit
   └─> Logs the sync
   └─> Re-schedules for next time
   └─> App goes back to sleep

4. Repeat step 3 continuously
```

### When Task Runs
```
App Closed → Wait → Background Wake → Sync → Sleep → Repeat
            ↑                                          ↓
            └──────── Re-schedule ─────────────────────┘
```

### Data Flow
```
DeviceActivity Extension
         ↓
    UserDefaults (App Group)
         ↓
    Background Task Reads
         ↓
    Upload to CloudKit
         ↓
    Friends See Your Data
```

---

##  Pro Tips

### Maximize Reliability
1. **Enable all settings:** Background App Refresh, Notifications
2. **Keep device charged:** More syncs when plugged in
3. **Use WiFi:** Cellular might be throttled
4. **Use app regularly:** iOS learns your patterns
5. **Check Debug Menu:** Verify syncs are happening

### For Testing
1. **Simulator:** Use "Simulate Background Fetch"
2. **Real Device:** Best for accurate testing
3. **Xcode Console:** See real-time logs
4. **Debug Menu:** See sync history
5. **Friend's Leaderboard:** Proof it's working

### Production Use
- Background refresh is **reliable enough** for this use case
- 15-60 minute delays are **acceptable** for screen time tracking
- Users will mostly see real-time data when opening the app
- Background sync is a **safety net** for when they don't open it

---

##  Success Indicators

Your background refresh is working if:
1.  Debug Menu shows "Last Background Sync" with recent time
2.  Sync History shows multiple entries over time
3.  Timestamps are 15-60 minutes apart
4.  Friend sees your blocks update without you opening app
5.  Syncs show green checkmarks (success)

---

##  Summary

**You have background refresh working!** 

-  Configured in Info.plist
-  Scheduled on app launch
-  Re-scheduled after each run
-  Uploads blocks to CloudKit
-  Logs every sync attempt
-  Visible in Debug Menu

**iOS will run it every 15-60 minutes** (closer to 15 when charging on WiFi).

Check the Debug Menu to see your sync history! 
