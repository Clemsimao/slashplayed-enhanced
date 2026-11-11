import XCTest

/// The launcher's install of a game on the device, for an app built with no client images (build.sh's
/// SP_NO_IMAGES=1): which games the start screen offers and which it installs (sp_games), and the game
/// folder's .flavor.info the launcher writes at every start (sp_flavor_info, against the companion's GameFiles.flavorInfo). The install
/// itself is the update's chain (spcdn.m, spbind.m, spassemble.m, spsign.m), which their own tests cover, and
/// its region is DeviceRegionTests'. Made-up rows, no Blizzard file.
final class DeviceInstallTests: XCTestCase {
    private let order = Flavor.allCases.map(\.rawValue)

    private func games(_ bundled: [String], _ made: [String]) -> (games: [String], installable: Set<String>) {
        var installable: NSSet?
        let games = sp_games(order, bundled, made, &installable)
        return (games, (installable as? Set<String>) ?? [])
    }

    /// An app with images offers what it bundles, in flavors.plist's order, and installs nothing, even with
    /// an update the device made of a game it no longer bundles: as before images could be left out.
    func testAnAppWithImagesOffersItsOwn() {
        let r = games(["retail", "classic_era"], ["anniversary", "retail"])
        XCTAssertEqual(r.games, ["classic_era", "retail"])
        XCTAssertEqual(r.installable, [])
        // One flavors.plist doesn't list goes last, as the launcher always sorted them.
        XCTAssertEqual(games(["zz_test", "retail"], []).games, ["retail", "zz_test"])
    }

    /// An app without images offers every game, and installs the ones the device hasn't made.
    func testAnAppWithoutImagesOffersEveryGame() {
        let none = games([], [])
        XCTAssertEqual(none.games, order)
        XCTAssertEqual(none.installable, Set(order))
        let some = games([], ["retail"])
        XCTAssertEqual(some.games, order)
        XCTAssertEqual(some.installable, Set(order).subtracting(["retail"]))
    }

    /// The addons the launcher puts in a game's folder (sp_addons_place): SPMovie everywhere, SPHover only on
    /// the headset, as the companion copied them; a file written only when it's missing or its bytes differ.
    func testAddonsArePlaced() throws {
        let repo = ClientAssemblyTests.repo, addons = repo.appending(path: "addon")
        let game = FileManager.default.temporaryDirectory.appending(path: "sp-addons-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: game) }
        func place(hover: Bool) -> (ok: Bool, line: String) {
            var line: NSString?
            let ok = sp_addons_place(addons.path, game.path, Flavor.classicEra.rawValue, hover, &line)
            return (ok, (line as String?) ?? "")
        }
        let movie = game.appending(path: "Interface/AddOns/SPMovie/SPMovie.lua")
        var r = place(hover: false)
        XCTAssertTrue(r.ok, r.line)
        XCTAssertEqual(r.line, "addons: 0 up to date, wrote SPMovie/SPMovie.toc SPMovie/SPMovie.lua")
        XCTAssertEqual(try Data(contentsOf: movie), try Data(contentsOf: addons.appending(path: "SPMovie/SPMovie.lua")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: game.appending(path: "Interface/AddOns/SPHover").path))
        // The same bytes: nothing written (the date stays).
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: movie.path)
        XCTAssertEqual(place(hover: false).line, "addons: 2 up to date")
        XCTAssertEqual(try movie.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       Date(timeIntervalSince1970: 1))
        // Another copy (an older addon) is replaced; on the headset SPHover comes too.
        try Data("-- old".utf8).write(to: movie)
        r = place(hover: true)
        XCTAssertEqual(r.line, "addons: 1 up to date, wrote SPMovie/SPMovie.lua SPHover/SPHover.toc SPHover/SPHover.lua")
        XCTAssertEqual(try Data(contentsOf: movie), try Data(contentsOf: addons.appending(path: "SPMovie/SPMovie.lua")))
        // An app without them says so.
        var line: NSString?
        XCTAssertFalse(sp_addons_place(game.appending(path: "none").path, game.path, Flavor.classicEra.rawValue, false, &line))
        XCTAssertTrue((line as String?)?.contains("FAILED SPMovie/SPMovie.toc (not in the app)") == true, "\(String(describing: line))")
    }

    /// The bundle carries all three addons, but only Forever receives the touch bars. Both platform
    /// selections are checked, including devices that install a game themselves and have no Mac copy.
    func testTouchBarsAreInstalledOnlyForForever() throws {
        let fm = FileManager.default
        let addons = ClientAssemblyTests.repo.appending(path: "addon")
        let base = fm.temporaryDirectory.appending(path: "sp-touch-addons-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        for flavor in Flavor.allCases {
            for hover in [false, true] {
                let game = base.appending(path: "\(flavor.rawValue)-\(hover)")
                var line: NSString?
                XCTAssertTrue(sp_addons_place(addons.path, game.path, flavor.rawValue, hover, &line), "\(String(describing: line))")
                let installed = game.appending(path: "Interface/AddOns")
                var expected: Set<String> = ["SPMovie"]
                if hover { expected.insert("SPHover") }
                if flavor == .forever { expected.insert("SPTouchBars") }
                XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: installed.path)), expected)
                for name in expected {
                    for ext in (name == "SPTouchBars" ? ["toc", "lua", "tga"] : ["toc", "lua"]) {
                        let file = "\(name)/\(name).\(ext)"
                        XCTAssertEqual(try Data(contentsOf: installed.appending(path: file)),
                                       try Data(contentsOf: addons.appending(path: file)), file)
                    }
                }
            }
        }
    }

    /// Launches repair missing or outdated source files, leave identical copies alone, and don't
    /// overwrite the player's saved layout when a new app bundles a new version of the addon.
    func testTouchBarsUpdatesPreserveSavedLayout() throws {
        let fm = FileManager.default
        let addons = ClientAssemblyTests.repo.appending(path: "addon")
        let game = fm.temporaryDirectory.appending(path: "sp-touch-update-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: game) }
        func place() -> String {
            var line: NSString?
            XCTAssertTrue(sp_addons_place(addons.path, game.path, Flavor.forever.rawValue, false, &line))
            return (line as String?) ?? ""
        }
        XCTAssertTrue(place().contains("SPTouchBars/SPTouchBars.lua"))
        let lua = game.appending(path: "Interface/AddOns/SPTouchBars/SPTouchBars.lua")
        let toc = game.appending(path: "Interface/AddOns/SPTouchBars/SPTouchBars.toc")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: lua.path)
        XCTAssertEqual(place(), "addons: 5 up to date")
        XCTAssertEqual(try lua.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                       Date(timeIntervalSince1970: 1))
        let saved = game.appending(path: "WTF/Account/Test/SavedVariables/SPTouchBars.lua")
        try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        let layout = Data("SPTouchBarsDB = { count = 9 }".utf8)
        try layout.write(to: saved)
        try Data("-- old touch bars".utf8).write(to: lua)
        try fm.removeItem(at: toc)
        XCTAssertEqual(place(), "addons: 3 up to date, wrote SPTouchBars/SPTouchBars.toc SPTouchBars/SPTouchBars.lua")
        XCTAssertEqual(try Data(contentsOf: lua), try Data(contentsOf: addons.appending(path: "SPTouchBars/SPTouchBars.lua")))
        XCTAssertEqual(try Data(contentsOf: saved), layout)
        // Missing or damaged artwork is repaired just like addon source, without touching layout.
        let texture = game.appending(path: "Interface/AddOns/SPTouchBars/SPTouchBars.tga")
        try Data("damaged texture".utf8).write(to: texture)
        XCTAssertEqual(place(), "addons: 4 up to date, wrote SPTouchBars/SPTouchBars.tga")
        XCTAssertEqual(try Data(contentsOf: texture),
                       try Data(contentsOf: addons.appending(path: "SPTouchBars/SPTouchBars.tga")))
        XCTAssertEqual(try Data(contentsOf: saved), layout)
    }

    /// The .flavor.info the launcher writes for a game is the one the companion sends.
    func testFlavorInfoIsTheCompanions() {
        for flavor in Flavor.allCases {
            XCTAssertEqual(sp_flavor_info(flavor.product), GameFiles.flavorInfo(flavor), flavor.rawValue)
        }
    }
}
