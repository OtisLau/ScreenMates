import DeviceActivity
import ManagedSettings
import Foundation
import UserNotifications

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    // This MUST match the App Group ID you created in Signing & Capabilities
    let suiteName = "group.com.otishlau.screenmates"

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        
        print("⚠️ Extension: Threshold reached!")
        
        // 1. Save the "Limit Hit" flag to the shared mailbox
        let sharedDefaults = UserDefaults(suiteName: suiteName)
        sharedDefaults?.set(Date(), forKey: "LastLimitHitDate")
        
        // 2. Send a local notification (so you know it worked)
        let content = UNMutableNotificationContent()
        content.title = "⌛️ Time Limit Reached"
        content.body = "You have used your screen time allowance."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
