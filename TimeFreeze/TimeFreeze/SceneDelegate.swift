import UIKit
import AppTrackingTransparency

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        window.tintColor = GameTheme.freezeBlue
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
//        GameCoordinator.shared.applicationBecameActive()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            ATTrackingManager.requestTrackingAuthorization { statue in }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
//        GameCoordinator.shared.applicationResignedActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
//        SaveStore.shared.flush()
    }
}
