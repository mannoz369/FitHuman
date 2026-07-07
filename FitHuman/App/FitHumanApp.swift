//
//  FitGeniusApp.swift
//  FitHuman
//
//  Created by mbodapud on 02/07/26.
//

import SwiftUI
#if canImport(UIKit) && canImport(UserNotifications)
import UIKit
import UserNotifications
#endif

@main
struct FitHumanApp: App {
    #if canImport(UIKit) && canImport(UserNotifications)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

#if canImport(UIKit) && canImport(UserNotifications)
private final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
#endif
