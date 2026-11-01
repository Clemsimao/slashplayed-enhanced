import Foundation

/// Decides when a *scheduled* Sparkle update may be put in front of the user.
///
/// An update alert landing while the companion is busy (above all while a game session runs: the device
/// client's console is attached to this Mac's devicectl) invites "Install and Relaunch", which quits the
/// companion and with it the session. So an update Sparkle finds on its own while busy is held back and
/// shown once the companion goes idle. A user's own "Check for Updates…" never comes through here: Sparkle
/// shows those at once, which is what the user asked for.
///
/// Foundation-only, so the decisions are unit-testable without Sparkle. `Updater` maps Sparkle's
/// gentle-reminder delegate calls onto it.
struct UpdateGate: Equatable {
    /// An update was found while busy and is waiting for idle.
    private(set) var isHoldingUpdate = false

    /// Answer for `standardUserDriverShouldHandleShowingScheduledUpdate`: `true` lets Sparkle show it now,
    /// `false` means we will. Sparkle requires this to be side-effect free, hence `static`; the hold is
    /// recorded in `updateDeferred` once Sparkle confirms it.
    static func sparkleShouldShowScheduledUpdate(busy: Bool) -> Bool { !busy }

    /// Sparkle has handed us a scheduled update to show. Returns `true` if it should be shown right away:
    /// the companion can have gone idle between Sparkle asking and handing it over, and no later idle edge
    /// would come to release it.
    mutating func updateDeferred(busy: Bool) -> Bool {
        isHoldingUpdate = busy
        return !busy
    }

    /// The busy state changed. Returns `true` exactly once, on the first idle edge after an update was
    /// held: the caller brings it forward.
    mutating func busyChanged(_ busy: Bool) -> Bool {
        guard isHoldingUpdate, !busy else { return false }
        isHoldingUpdate = false
        return true
    }

    /// The user has seen the update some other way (a manual check brings the held one forward) or the
    /// session ended. Nothing is left to release.
    mutating func updateHandled() { isHoldingUpdate = false }
}
