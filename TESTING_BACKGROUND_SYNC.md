# Testing Background Sync

## 🎯 Goal
Verify that your app uploads block data to CloudKit even when it's **closed**, not just when you open it.

---

## 🧪 Test Method 1: Simple Test (Recommended)

### Step 1: Setup
1. **Build and run the app**
2. **Complete onboarding** (permissions, username, group)
3. **Open Debug Menu** (Settings → Debug Menu)
4. **Note current values:**
   - Daily Blocks Used: `X`
   - Last Background Sync: `(none yet)`

### Step 2: Use Tracked Apps
1. **Close ScreenMates** completely (swipe up from app switcher)
2. **Open tracked apps** (Instagram, TikTok, etc.)
3. **Use them for 5+ minutes** (accumulate ~5 blocks in test mode)
4. **Wait 15-20 minutes** (for background task to run)

### Step 3: Check Results
1. **Don't open ScreenMates yet!**
2. **Check CloudKit Dashboard** or ask a friend to check their leaderboard
3. **Your blocks should have updated** even though app was closed
4. **Now open ScreenMates**
5. **Go to Debug Menu** → Check "Last Background Sync"
6. **Tap "Sync History"** → See the background sync events

### ✅ Success Criteria
- Last Background Sync shows a recent timestamp
- Sync History shows entries while app was closed
- Friend sees your updated blocks without you opening the app

---

## 🧪 Test Method 2: Simulator Test (Advanced)

### Setup Background Task Simulation
1. **Run app in Xcode Simulator**
2. **Complete onboarding**
3. **Use tracked apps to get some blocks**
4. **Close the app** (Home button)

### Trigger Background Task Manually
5. **In Xcode, open Debug menu** → Simulate Background Fetch
6. **Or use terminal command:**
   ```bash
   e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.otishlau.screenmates.refresh"]
   ```

### Verify
7. **Check Xcode console** for:
   - `🌙 Background task triggered at ...`
   - `✅ Background Sync: Uploaded X blocks`
8. **Open app** → Debug Menu → Check sync history

---

## 🧪 Test Method 3: Real Device Test (Most Reliable)

### Why Real Device?
- Simulators don't reliably test background tasks
- Real devices follow actual iOS scheduling
- More accurate real-world behavior

### Steps
1. **Install on physical iPhone/iPad**
2. **Complete setup**
3. **Use tracked apps for 2-3 minutes** (get 2-3 blocks)
4. **Force quit ScreenMates**
5. **Put device in your pocket** (don't touch it for 20+ minutes)
6. **OR: Lock device and charge it** (iOS prefers to run bg tasks while charging)
7. **After 20+ minutes, open app**
8. **Check Debug Menu** → "Last Background Sync"
9. **Should show sync happened while app was closed**

### 🔍 Debugging Tips
- Background tasks run more frequently when **device is charging**
- iOS may delay tasks if **battery is low**
- Tasks won't run if **Low Power Mode** is enabled
- **First bg task** might take 30+ mins after initial app close

---

## 📊 Reading the Sync History

### Green Checkmark ✅
- Sync succeeded
- Data uploaded to CloudKit
- Friends can see your updated blocks

### Red X ❌
- Sync failed
- Possible causes:
  - No internet connection
  - CloudKit unavailable
  - iCloud not signed in

### Timestamp
- Shows **exact time** background task ran
- Should be **while app was closed**
- Multiple entries = multiple successful syncs

### Blocks Count
- Shows how many blocks were uploaded
- Should match your usage at that time

---

## 🎓 Understanding Background Tasks

### How It Works
1. **App goes to background** → schedules task for 15 min later
2. **iOS decides when to run it** (might not be exactly 15 min)
3. **Task wakes up** → reads UserDefaults
4. **Uploads to CloudKit** → logs the sync
5. **Repeats** when app enters background again

### iOS Scheduling Rules
- ✅ **Runs more often** when device is charging
- ✅ **Runs more often** when on WiFi vs cellular
- ❌ **Delayed or skipped** if battery is low
- ❌ **Never runs** in Low Power Mode
- ❌ **Might delay** if you're actively using device

### Typical Behavior
- **Best case:** Task runs every 15-20 minutes
- **Typical case:** Task runs every 30-60 minutes
- **Worst case:** Task runs once per hour or less

---

## 🔧 Debug Menu Features

### View Background Sync Status
- **Last Background Sync** - When did it last run?
- **Sync History** - See all sync events with timestamps
- **Success/Failure** - Check if syncs are working

### Manual Testing
- **Force Sync Now** - Manually upload (tests network)
- **Clear Local Data** - Reset and test from scratch

---

## 🚨 Troubleshooting

### "No background syncs yet"
**Possible causes:**
- App hasn't been backgrounded long enough
- iOS hasn't scheduled the task yet
- Try closing app and waiting 30+ minutes

**Solutions:**
- Make sure device is charging
- Disable Low Power Mode
- Wait longer (first bg task can take time)
- Test on real device, not simulator

### "Syncs showing but blocks not updating"
**Possible causes:**
- CloudKit sync is working, but blocks not incrementing
- DeviceActivity extension not running

**Solutions:**
- Use tracked apps (Instagram, TikTok, etc.)
- Check "Daily Blocks Used" in Debug Menu
- Verify apps are selected in Screen Time settings

### "All syncs showing as failed (red X)"
**Possible causes:**
- No internet connection
- Not signed into iCloud
- CloudKit container issue

**Solutions:**
- Check internet connection
- Sign into iCloud (Settings → Your Name)
- Verify iCloud Drive is enabled

---

## ✅ Success Indicators

You know background sync is working when:
1. ✅ "Last Background Sync" shows recent time (while app was closed)
2. ✅ Sync History shows multiple entries over time
3. ✅ Friend sees your blocks update without you opening the app
4. ✅ Timestamps in history are spaced 15-60 minutes apart
5. ✅ Most syncs show green checkmarks (success)

---

## 📱 Pro Tips

### Best Conditions for Testing
- ✅ Device plugged in and charging
- ✅ Connected to WiFi
- ✅ Low Power Mode OFF
- ✅ App has been closed for 30+ minutes
- ✅ Device not in active use

### Quick Test
1. Use tracked apps for 3 minutes (get 3 blocks)
2. Close ScreenMates completely
3. Plug in device and lock it
4. Wait 30 minutes
5. Open app → Debug Menu → Check sync history
6. Should see a successful sync with 3 blocks

### Continuous Monitoring
- Ask a friend to watch your leaderboard position
- Use tracked apps while ScreenMates is closed
- Friend should see your blocks increase
- This proves background sync is working!

---

## 🎉 Summary

**To test background sync:**
1. Use tracked apps to get blocks
2. Close ScreenMates completely  
3. Wait 20-30 minutes (device charging helps)
4. Open app → Settings → Debug Menu
5. Check "Last Background Sync" and "Sync History"

**You'll know it's working when you see sync events that happened while the app was closed!** 🚀
