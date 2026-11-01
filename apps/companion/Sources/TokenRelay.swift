import Darwin
import Foundation

/// Catches a fresh Battle.net launcher token for a headset login (as apps/client/grab-token.sh
/// does). Battle.net writes the token into the net.battle prefs and starts the Mac client, which is
/// killed at once, before it can spend it. Token values are never read, logged or shown: only sizes.
enum TokenRelay {
    static let timestampKey = "Launch Options/WoW/ACCOUNT_TS"

    /// What Battle.net launched.
    struct Launch {
        var flavor: Flavor
        var arguments: [String]
        /// Without -launcherlogin, Battle.net made no new token (its log: "SSO Token generation error:
        /// err=ERROR_API_NOT_READY"; restarting Battle.net fixes it).
        var hasToken: Bool { arguments.contains("-launcherlogin") }
    }

    /// The token's timestamp, which changes when Battle.net writes a new one.
    static func tokenTimestamp() async -> String? {
        guard let r = try? await Shell.run("/usr/bin/defaults", ["read", "net.battle", timestampKey], check: false),
              r.status == 0 else { return nil }
        return r.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A flavor's Mac client that's running now, if any.
    static func runningClient() -> (pid: pid_t, flavor: Flavor)? {
        let clients = Dictionary(uniqueKeysWithValues: Flavor.allCases.map { ($0.clientExecutable.path, $0) })
        for pid in allPIDs() {
            if let path = executablePath(pid), let flavor = clients[path] { return (pid, flavor) }
        }
        return nil
    }

    /// Waits for Battle.net to start a flavor's Mac client and kills it straight away.
    static func catchClientLaunch() async throws -> Launch {
        while true {
            if let (pid, flavor) = runningClient() {
                let args = arguments(pid) ?? []
                Darwin.kill(pid, SIGKILL)
                return Launch(flavor: flavor, arguments: args)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Waits up to 15 s for the token timestamp to move past `old`. The client can start before
    /// Battle.net writes the new token, and exporting then would relay the old, spent one.
    static func waitForNewToken(after old: String?) async throws -> Bool {
        for _ in 0..<150 {
            if let ts = await tokenTimestamp(), ts != old { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    /// Where export writes (and Diagnostics never reads from).
    static var exportDirectory: URL { FileManager.default.temporaryDirectory.appending(path: "sptoken") }

    /// Exports the net.battle prefs, token included, to a file only this user can read. On the device,
    /// the AppKit shim imports it from Library/spnetbattle.plist just before the client loads and deletes it.
    static func export() async throws -> URL {
        let dir = exportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = dir.appending(path: "spnetbattle.plist")
        try? FileManager.default.removeItem(at: url)
        try await Shell.run("/usr/bin/defaults", ["export", "net.battle", url.path])
        return url
    }

    // MARK: Processes

    private static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(got, 0))))
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    /// A process's arguments, without argv[0] (KERN_PROCARGS2: argc, the exec path, padding, argv).
    private static func arguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }
        while i < size && buf[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return Array(args.dropFirst())
    }
}
