// A UIKit shell for the experiments that wait on a person (p2: the pairing code): an app with no scene is
// killed by the 20 s launch watchdog, so these run under UIApplicationMain with a window (Info.plist's
// scene manifest names SPJitScene), and the work runs off the main thread. When it ends, the result and
// the "done" line are logged and the app exits.
import UIKit

nonisolated(unsafe) private var uiWork: (@Sendable (HostLog) async -> Int32)?
nonisolated(unsafe) private var uiLog: HostLog?
nonisolated(unsafe) private var uiName = ""

@objc(SPJitAppDelegate)
final class SPJitAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        guard let work = uiWork, let log = uiLog else { return true }
        let name = uiName
        Task.detached {
            let code = await work(log)
            log.out("  \(code == 0 ? "PASS" : "FAIL")\n=== \(name) done\n")
            exit(code)
        }
        return true
    }
}

@objc(SPJitScene)
final class SPJitScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        let label = UILabel()
        label.text = "SPJitTest \(uiName): see Documents/spjit.log"
        label.textAlignment = .center
        label.frame = controller.view.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(label)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }
}

private func uiMain(_ name: String, _ out: SPLog, _ work: @escaping @Sendable (HostLog) async -> Int32) -> Never {
    uiName = name
    uiLog = HostLog(out)
    uiWork = work
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, "SPJitAppDelegate")
    exit(1)
}

// P2: never returns (main.c's "done" line comes from here).
@_cdecl("sp_pair_manual_ui")
func sp_pair_manual_ui(_ out: SPLog) -> Int32 {
    uiMain("p2", out) { await pairManual($0) }
}
