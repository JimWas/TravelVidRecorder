import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let unsavedVideosNotificationID = "unsaved-videos-reminder"

    private init() {}

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    func scheduleUnsavedVideosNotification(count: Int) {
        guard count > 0 else {
            clearUnsavedVideosNotification()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Unsaved Videos"
        content.body = "You have \(count) video(s) saved in the app. Open TravelVid Recorder to save them to Photos."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: unsavedVideosNotificationID,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [unsavedVideosNotificationID])
        center.add(request)
    }

    func clearUnsavedVideosNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [unsavedVideosNotificationID])
        center.removeDeliveredNotifications(withIdentifiers: [unsavedVideosNotificationID])
    }
}
