import Foundation
import Observation

/// What the companion knows of the Mac's game install (Flavor.installRoot): which games it has, its
/// .build.info rows, and each client's version, as last read. Nothing else in the app opens the install to
/// ask those: the window, Settings, and onboarding read the snapshot, and Play reads the install itself only
/// when it needs it now (GameInstall.reads), within `limit`.
///
/// Why: an external drive that's asleep or busy (a Time Machine backup of the T7, rc9's and rc17's runs)
/// stalls every open() on it for minutes, in the kernel, where no timeout reaches. Play read the install on
/// every run, copying or not (each game's region and tags, the size of its files), so it sat on "Asking
/// Blizzard for each game's current build" with nothing in the log. Now a read happens off the main thread
/// on one queue, so a stalled one holds one thread (and the reads after it wait on it, not on new
/// threads), and its caller is told after `limit` that it isn't answering.
@Observable
final class GameInstall: @unchecked Sendable {
    static let shared = GameInstall()

    /// How long a read may take before its caller is told the install isn't responding. A read of a
    /// healthy install (a few stats, .build.info, and each client's Info.plist) takes milliseconds; a
    /// sleeping external drive spins up in a few seconds.
    static let limit: TimeInterval = 5

    /// What one read found.
    struct Snapshot: Codable, Equatable {
        /// The install's path (Flavor.installRoot when read): a snapshot of another install isn't this one's.
        var root: String
        /// Each installed game's client (by Flavor.rawValue): its Info.plist's version and build.
        var games: [String: Client]
        /// .build.info's rows by product (GameStore.buildInfo); empty when it's missing or unreadable.
        var rows: [String: [String: String]]
        /// .build.info's size and date, if it's there: when the install last changed, for cached sizes.
        var buildInfoSize: Int64?
        var buildInfoDate: Date?

        struct Client: Codable, Equatable {
            /// CFBundleShortVersionString (12.1.5) and CFBundleVersion (the client's build, 1.15.9.70003).
            var version: String?
            var build: String?
        }

        /// The games installed, in Flavor's order.
        var flavors: [Flavor] { Flavor.allCases.filter { games[$0.rawValue] != nil } }

        var hasBuildInfo: Bool { buildInfoDate != nil }

        /// Reads `root` now, on the calling thread (which a stalled drive holds until it answers).
        static func read(_ root: URL) -> Snapshot {
            var games: [String: Client] = [:]
            for flavor in Flavor.installed(in: root) {
                let plist = flavor.clientExecutable(in: root).deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "Info.plist")
                let info = NSDictionary(contentsOf: plist)
                games[flavor.rawValue] = Client(version: info?["CFBundleShortVersionString"] as? String,
                                                build: info?["CFBundleVersion"] as? String)
            }
            let buildInfo = root.appending(path: ".build.info")
            let values = try? buildInfo.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            let regular = values?.isRegularFile == true
            return Snapshot(root: root.path, games: games, rows: (try? GameStore.buildInfo(root)) ?? [:],
                            buildInfoSize: regular ? values?.fileSize.map(Int64.init) : nil,
                            buildInfoDate: regular ? values?.contentModificationDate : nil)
        }
    }

    /// The install didn't answer a read within `limit`.
    struct NotResponding: LocalizedError, Equatable {
        var root: String
        var seconds: TimeInterval

        /// "the T7-A drive" for an install on /Volumes/T7-A, else its folder: from the path alone, as asking
        /// the volume its name would wait on it too.
        var place: String { Self.place(root) }

        static func place(_ root: String) -> String {
            let parts = root.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == "Volumes" { return "the \(parts[1]) drive" }
            return root
        }

        var errorDescription: String? {
            "The game install on \(place) isn't responding (nothing in \(Int(seconds)) s). A drive that's asleep, busy with a backup, or disconnected holds every read."
        }

        /// The log's line: the path and the wait.
        var logLine: String { "the game install (\(root)) didn't answer a read in \(Int(seconds)) s; it may be asleep, busy (a backup), or disconnected" }
    }

    // MARK: The snapshot

    /// Locked: background tasks (the build's check, the files step) read it as well as SwiftUI.
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var stored: Snapshot?
    /// The read running now and who's waiting on it (at most one at a time; GameInstall.read).
    @ObservationIgnored private var running: (root: String, waiters: [(Snapshot) -> Void])?

    /// The last snapshot (this run's, or the last run's, kept in UserDefaults). Observed by SwiftUI.
    var snapshot: Snapshot? {
        access(keyPath: \.snapshot)
        return lock.withLock { stored }
    }

    static let snapshotKey = "gameInstallSnapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }

    /// The snapshot of the install chosen now (Flavor.installRoot), if one was read: nil until a read of a
    /// newly chosen install comes back.
    static var known: Snapshot? { shared.known(root: Flavor.installRoot) }

    func known(root: URL) -> Snapshot? {
        snapshot.flatMap { $0.root == root.path ? $0 : nil }
    }

    // MARK: Reading

    /// What reads the install, for tests (a reader that never returns stands for a stalled drive).
    @ObservationIgnored var reader: (URL) -> Snapshot = Snapshot.read
    /// Where the snapshot is kept between runs.
    @ObservationIgnored private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "com.strawdynamics.slashplayed.companion.game-install", qos: .userInitiated)

    /// Reads the install chosen now, within `limit` seconds, and keeps the result as the snapshot.
    static func read(limit: TimeInterval = limit) async throws -> Snapshot {
        try await shared.read(Flavor.installRoot, limit: limit)
    }

    /// Reads `root` within `limit` seconds, or throws NotResponding (the read goes on, and its result is
    /// still kept when it comes). A read of `root` already running is waited on rather than started again,
    /// so a stalled drive holds one thread however often it's asked.
    func read(_ root: URL, limit: TimeInterval = GameInstall.limit) async throws -> Snapshot {
        let result: Snapshot? = await withCheckedContinuation { continuation in
            let once = Once { continuation.resume(returning: $0) }
            whenRead(root) { once.fire($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + limit) { once.fire(nil) }
        }
        guard let result else { throw NotResponding(root: root.path, seconds: limit) }
        return result
    }

    /// Starts a read of the install chosen now in the background, unless one is running, for the window
    /// (which shows the snapshot as it is meanwhile). Never waits.
    static func refresh() {
        shared.whenRead(Flavor.installRoot) { _ in }
    }

    private func whenRead(_ root: URL, _ done: @escaping (Snapshot) -> Void) {
        let start: Bool = lock.withLock {
            if running?.root == root.path {
                running!.waiters.append(done)
                return false
            }
            // Another install's read is still running (the choice changed while its drive stalled): this
            // one queues behind it on the one queue, and the earlier one's waiters time out as for a stall.
            running = (root.path, [done])
            return true
        }
        guard start else { return }
        queue.async { [self] in
            let snapshot = reader(root)
            let waiters: [(Snapshot) -> Void] = lock.withLock {
                guard running?.root == root.path else { return [] }
                defer { running = nil }
                return running!.waiters
            }
            // Kept before the waiters hear, so what they read next is this; the waiters aren't sent to
            // the main thread, so a read's answer never waits on it.
            remember(snapshot)
            waiters.forEach { $0(snapshot) }
        }
    }

    /// Called on the main thread when a read finds the install changed (Pipeline: the steps' titles and
    /// the games' size follow it).
    @ObservationIgnored var onChange: (() -> Void)?

    /// Keeps `snapshot`, for this run and the next, from any thread. SwiftUI and onChange hear of a change
    /// on the main thread.
    func remember(_ snapshot: Snapshot) {
        let changed: Bool = lock.withLock {
            guard stored != snapshot else { return false }
            stored = snapshot
            return true
        }
        guard changed else { return }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: Self.snapshotKey) }
        DispatchQueue.main.async { [self] in
            withMutation(keyPath: \.snapshot) {}
            onChange?()
        }
    }

    // MARK: When the install is read

    /// Whether Play reads the install now: when the files step copies from it (Copy Game Files from This
    /// Mac is on for the device), finishes a copy the device's copy marker says stopped (GameFiles.plan), or
    /// Play with My Mac's Battle.net runs (Battle.net launches the client from it). Otherwise Play goes by
    /// the snapshot: a region and tags for the build's check and .build.info rows, or none at all, and
    /// never waits on the drive.
    static func reads(copies: Bool, finishingCopy: Bool, battleNet: Bool) -> Bool {
        copies || finishingCopy || battleNet
    }
}

/// Resumes once: the first of a read and its time limit.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var action: ((T) -> Void)?
    init(_ action: @escaping (T) -> Void) { self.action = action }
    func fire(_ value: T) {
        let action: ((T) -> Void)? = lock.withLock {
            defer { self.action = nil }
            return self.action
        }
        action?(value)
    }
}
