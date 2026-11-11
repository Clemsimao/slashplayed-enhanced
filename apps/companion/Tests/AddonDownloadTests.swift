import CryptoKit
import XCTest

/// Made-up addons exercise the device's installer without networking or committing third-party bytes.
final class AddonDownloadTests: XCTestCase {
    private var root: URL!
    private let names = ["Bagnon", "BagBrother"]
    private let url = URL(string: "https://example.invalid/addon.zip")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "sp-addon-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func package(stored: Bool = false) throws -> Data {
        for name in names {
            let dir = root.appending(path: "source/\(name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("## Interface: 16001\n## Title: \(name)\n".utf8).write(to: dir.appending(path: "\(name).toc"))
        }
        try Data(String(repeating: "-- test addon\n", count: 100).utf8)
            .write(to: root.appending(path: "source/Bagnon/safe.lua"))
        try TestShell.check("/usr/bin/zip", ["-q", "-r", stored ? "-0" : "-9", root.appending(path: "test.zip").path] + names,
                            in: root.appending(path: "source"))
        return try Data(contentsOf: root.appending(path: "test.zip"))
    }

    private func install(_ data: Data?, sha: String, requests: inout Int) -> (Bool, String) {
        var calls = 0, line: NSString?
        let ok = sp_addon_download(root.appending(path: "cache/package.zip").path,
                                  root.appending(path: "game").path, url, sha, names, { url, range, problem in
            calls += 1
            XCTAssertEqual(url, self.url)
            XCTAssertEqual(range, NSRange(location: 0, length: 0))
            if data == nil { problem.pointee = "offline" }
            return data
        }, &line)
        requests += calls
        return (ok, (line as String?) ?? "")
    }

    func testDownloadCacheOfflineRepairAndSavedSettings() throws {
        let bytes = try package(), sha = digest(bytes), fm = FileManager.default
        var requests = 0
        XCTAssertTrue(install(bytes, sha: sha, requests: &requests).0)
        XCTAssertEqual(requests, 1)
        let file = root.appending(path: "game/Interface/AddOns/Bagnon/safe.lua")
        let expected = try Data(contentsOf: file)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        let saved = root.appending(path: "game/WTF/Account/Test/SavedVariables/Bagnon.lua")
        try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings = Data("Bagnon_Sets = { scale = 1.5 }".utf8)
        try settings.write(to: saved)
        XCTAssertTrue(install(nil, sha: sha, requests: &requests).0)
        XCTAssertEqual(requests, 1, "a cached package makes no network requests")
        XCTAssertEqual(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       Date(timeIntervalSince1970: 1))
        try fm.removeItem(at: file)
        XCTAssertTrue(install(nil, sha: sha, requests: &requests).0)
        XCTAssertEqual(try Data(contentsOf: file), expected)
        XCTAssertEqual(try Data(contentsOf: saved), settings)
        XCTAssertEqual(requests, 1)
        // A corrupt cache is fetched again, rather than trusted because of its filename.
        try Data("broken cache".utf8).write(to: root.appending(path: "cache/package.zip"))
        XCTAssertTrue(install(bytes, sha: sha, requests: &requests).0)
        XCTAssertEqual(requests, 2)
    }

    func testStoredEntriesAndEmptyFiles() throws {
        let dir = root.appending(path: "source/Bagnon")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appending(path: "empty.lua"))
        let bytes = try package(stored: true)
        var requests = 0
        XCTAssertTrue(install(bytes, sha: digest(bytes), requests: &requests).0)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "game/Interface/AddOns/Bagnon/empty.lua")), Data())
    }

    func testOfflineAndChecksumFailuresLeaveTheGameAlone() throws {
        let bytes = try package()
        var requests = 0
        let offline = install(nil, sha: digest(bytes), requests: &requests)
        XCTAssertFalse(offline.0)
        XCTAssertTrue(offline.1.contains("offline"))
        XCTAssertFalse(install(Data("wrong package".utf8), sha: digest(bytes), requests: &requests).0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "game").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "cache/package.zip").path))
    }

    func testUnsafeAndIncompleteArchivesAreRejectedBeforeWriting() throws {
        let bytes = try package()
        // Same-length names in both ZIP headers: the checksum is correct for the unsafe test ZIP.
        var unsafe = bytes
        let from = Data("Bagnon/safe.lua".utf8), to = Data("Bagnon/../x.lua".utf8)
        while let range = unsafe.range(of: from) { unsafe.replaceSubrange(range, with: to) }
        var requests = 0
        XCTAssertFalse(install(unsafe, sha: digest(unsafe), requests: &requests).0)
        let truncated = Data(bytes.dropLast(10))
        XCTAssertFalse(install(truncated, sha: digest(truncated), requests: &requests).0)
        var missing = bytes
        let toc = Data("BagBrother/BagBrother.toc".utf8), txt = Data("BagBrother/BagBrother.txt".utf8)
        while let range = missing.range(of: toc) { missing.replaceSubrange(range, with: txt) }
        XCTAssertFalse(install(missing, sha: digest(missing), requests: &requests).0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "game").path))
    }

    func testDestinationSymlinksAreRejected() throws {
        let bytes = try package(), fm = FileManager.default
        let addons = root.appending(path: "game/Interface/AddOns")
        try fm.createDirectory(at: addons, withIntermediateDirectories: true)
        let outside = root.appending(path: "outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: addons.appending(path: "BagBrother"), withDestinationURL: outside)
        var requests = 0
        XCTAssertFalse(install(bytes, sha: digest(bytes), requests: &requests).0)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: outside.path), [])
    }
}
