import Foundation

// Notifications are not used in the core-func build.
// Kept as an empty stub so the file doesn't need to be removed from the Xcode project.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {}
}
