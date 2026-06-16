// EnerSyncApp.swift
// App entry point + notification quick-action handling. iOS 18+ and iOS 26.

import SwiftUI
import UserNotifications

@main
struct EnerSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Quick actions on the "Complete by" miss notification.
        let done = UNNotificationAction(identifier: "MARK_DONE", title: "Mark as done", options: [])
        let resched = UNNotificationAction(identifier: "RESCHEDULE", title: "Reschedule", options: [.foreground])
        let category = UNNotificationCategory(identifier: "TASK_MISSED",
                                              actions: [done, resched],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
        return true
    }

    // Show banners even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Handle the user's choice on the notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["taskID"] as? String
        switch response.actionIdentifier {
        case "MARK_DONE":
            await MainActor.run { TaskManager.shared.markDone(taskIDString: id) }
        case "RESCHEDULE", UNNotificationDefaultActionIdentifier:
            await MainActor.run { TaskManager.shared.beginReschedule(taskIDString: id) }
        default:
            break
        }
    }
}
