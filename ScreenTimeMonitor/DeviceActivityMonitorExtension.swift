import DeviceActivity
import ManagedSettings
import Foundation
import UserNotifications

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    let suiteName = "group.com.otishlau.screenmates"

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        let sharedDefaults = UserDefaults(suiteName: suiteName)
        
        // 1. Check for Midnight Reset
        // If the last block was added yesterday, reset the count to 0 first.
        let lastDate = sharedDefaults?.object(forKey: "LastBlockDate") as? Date ?? Date()
        if !Calendar.current.isDateInToday(lastDate) {
            sharedDefaults?.set(0, forKey: "DailyBlocksUsed")
        }
        
        // 2. Increment the Block Count
        var currentBlocks = sharedDefaults?.integer(forKey: "DailyBlocksUsed") ?? 0
        currentBlocks += 1
        
        // 3. Save Everything
        sharedDefaults?.set(currentBlocks, forKey: "DailyBlocksUsed")
        sharedDefaults?.set(Date(), forKey: "LastBlockDate")
        
        print("🧱 Block added! Daily Total: \(currentBlocks)")
        
        // 4. (Optional) Local Notification for testing
        // content.body = "You used another 15 minutes."
    }
}
