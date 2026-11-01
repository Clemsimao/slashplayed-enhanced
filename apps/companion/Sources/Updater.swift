import AppKit
import Sparkle
import os.log

/// The app's one Sparkle updater, plus the bit of its state the menu binds to.
///
/// `SPUStandardUpdaterController` starts the updater as soon as it's created, so this lives for the whole
/// app (`CompanionApp` touches `shared` at launch) and Sparkle's scheduled checks run whatever window is
/// open. Feed URL, public key and the automatic-check defaults all come from Info.plist (project.yml).
/// Not sandboxed, so Sparkle installs in-process through its own Autoupdate helper: no XPC services or
/// entitlements to set up.
///
/// Scheduled update prompts are held back while the companion is busy (an action or a game session;
/// see `UpdateGate`); a manual check always shows at once.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    /// False while a check or install is already in flight. Sparkle exposes it over KVO only, so it's
    /// mirrored here for SwiftUI.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    /// Sparkle holds its delegates weakly, so this keeps it alive.
    @ObservationIgnored private let gentleReminders = GentleReminders()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: gentleReminders)
        canCheckForUpdates = controller.updater.canCheckForUpdates
        gentleReminders.showHeldUpdate = { [weak self] in
            // Async: one path here is from inside Sparkle's own "about to show" callback, which must
            // return before the update is brought forward.
            DispatchQueue.main.async { self?.checkForUpdates() }
        }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheckForUpdates = can }
        }
    }

    /// User-initiated, so Sparkle always shows the result, including "you're up to date" and errors (a
    /// feed that's missing or unreachable), which a scheduled check keeps quiet about.
    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// Settings' toggle writes Sparkle's `SUEnableAutomaticChecks` default itself; this tells the running
    /// updater too, so it reschedules (or stops) its checks now rather than at its next cycle.
    func setAutomaticChecks(_ on: Bool) {
        if controller.updater.automaticallyChecksForUpdates != on { controller.updater.automaticallyChecksForUpdates = on }
    }

    /// Pipeline calls this on every change of `isBusy`.
    func busyChanged(_ busy: Bool) { gentleReminders.busyChanged(busy) }
}

/// Sparkle's gentle-reminder hooks, driving an `UpdateGate`.
///
/// Holding an update means telling Sparkle we'll show it ourselves and then not doing so until the
/// companion goes idle. Sparkle keeps the update session open meanwhile, so `checkForUpdates` later brings
/// that same update forward rather than starting a new check.
private final class GentleReminders: NSObject, SPUStandardUserDriverDelegate {
    var showHeldUpdate: () -> Void = {}
    private var busy = false
    private var gate = UpdateGate()
    private let log = Logger(subsystem: "com.strawdynamics.slashplayed.companion", category: "Updater")

    func busyChanged(_ busy: Bool) {
        self.busy = busy
        if gate.busyChanged(busy) {
            log.info("companion idle: showing the held update")
            showHeldUpdate()
        }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        UpdateGate.sparkleShouldShowScheduledUpdate(busy: busy)
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Sparkle showing it itself (idle, or a manual check) needs nothing.
        guard !handleShowingUpdate else { return }
        if gate.updateDeferred(busy: busy) {
            showHeldUpdate()
        } else {
            log.info("update \(update.displayVersionString, privacy: .public) found while busy: holding it until idle")
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { gate.updateHandled() }

    func standardUserDriverWillFinishUpdateSession() { gate.updateHandled() }
}
