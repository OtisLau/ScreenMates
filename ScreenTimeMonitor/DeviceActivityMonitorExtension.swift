import DeviceActivity
import ManagedSettings
import Foundation
import UserNotifications

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    // MAKE SURE THIS MATCHES YOUR APP GROUP EXACTLY
    let suiteName = "group.com.otishlau.screenmates"

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        print("⚠️ Extension: Threshold reached!")
        
        // 1. Save the "Limit Hit" flag to the shared mailbox so the main app finds it later
        let sharedDefaults = UserDefaults(suiteName: suiteName)
        sharedDefaults?.set(Date(), forKey: "LastLimitHitDate")
        
        // 2. Send a notification to wake the user up
        let content = UNMutableNotificationContent()
        content.title = "⌛️ Time Limit Reached"
        content.body = "Time's up! Tap here to sync your status with friends."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
