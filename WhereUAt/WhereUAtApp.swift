import SwiftUI
import CloudKit
import UIKit
import os

private let log = Logger(subsystem: "com.oanarinaldi.WhereUAt", category: "App")

/// Bridges the UIKit scene delegate — the only place iOS hands over an accepted
/// CloudKit share — to SwiftUI.
@MainActor
final class ShareBroker: ObservableObject {
    static let shared = ShareBroker()
    @Published var incoming: CKShare.Metadata?
    /// Set when CloudKit tells us something changed while we were in the background.
    @Published var remoteChangeToken = UUID()

    func received(_ metadata: CKShare.Metadata) {
        incoming = metadata
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Tapping an invitation link lands here, before the app has any UI up.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        log.info("Received CloudKit share invitation")
        Task { @MainActor in ShareBroker.shared.received(metadata) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent CloudKit pushes are what move other people's pins in the background.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // The completion-handler form rather than the `async` one: the async
    // requirement is declared nonisolated, so the non-Sendable userInfo would
    // have to cross an actor boundary to reach this main-actor delegate.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        ShareBroker.shared.remoteChangeToken = UUID()
        completionHandler(.newData)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

@main
struct WhereUAtApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()
    @StateObject private var broker = ShareBroker.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .tint(Theme.sky)
                .task { await state.bootstrap() }
                .onChange(of: broker.incoming) { _, metadata in
                    state.pendingInvitation = metadata
                }
                .onChange(of: broker.remoteChangeToken) { _, _ in
                    Task { await state.sync() }
                }
        }
    }
}
