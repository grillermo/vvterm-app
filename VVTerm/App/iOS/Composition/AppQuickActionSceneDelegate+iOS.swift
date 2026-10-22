import UIKit

/// Receives quick actions for SwiftUI's window scenes. SwiftUI still owns the
/// window; this delegate only handles the shortcut item.
final class AppQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    // A cold launch delivers the item before the scene is active, and opening a
    // URL then is unreliable, so it waits for the first activation.
    private var pendingAction: AppQuickAction?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        pendingAction = connectionOptions.shortcutItem.flatMap { AppQuickAction(shortcutType: $0.type) }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let action = pendingAction else { return }
        pendingAction = nil
        perform(action)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = AppQuickAction(shortcutType: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        perform(action)
        completionHandler(true)
    }

    private func perform(_ action: AppQuickAction) {
        guard let url = action.url(infoDictionary: Bundle.main.infoDictionary) else { return }
        UIApplication.shared.open(url)
    }
}
