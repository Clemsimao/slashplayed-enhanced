import XCTest

/// Team discovery and choice (Signing) on made-up Xcode preferences, and xcodebuild's provisioning errors
/// said as what to do. Nothing here reads this Mac's Xcode accounts or keychain.
final class SigningTests: XCTestCase {
    static let paid = Signing.Team(id: "AAAAAAAAAA", name: "Acme Games LLC", isFree: false)
    static let paid2 = Signing.Team(id: "BBBBBBBBBB", name: "Other Co", isFree: false)
    static let free = Signing.Team(id: "CCCCCCCCCC", name: "Some One (Personal Team)", isFree: true)

    /// IDEProvisioningTeamByIdentifier's shape: account UUID → teams. The same team under two accounts
    /// shows once; free teams sort last.
    func testTeamsFromXcodePreferences() {
        let prefs: [String: Any] = [
            "11111111-0000-0000-0000-000000000000": [
                ["isFreeProvisioningTeam": 1, "teamID": Self.free.id, "teamName": Self.free.name, "teamType": "Personal Team"],
                ["isFreeProvisioningTeam": 0, "teamID": Self.paid.id, "teamName": Self.paid.name, "teamType": "Company"],
            ],
            "22222222-0000-0000-0000-000000000000": [
                ["isFreeProvisioningTeam": 0, "teamID": Self.paid.id, "teamName": Self.paid.name, "teamType": "Company"],
            ],
        ]
        XCTAssertEqual(Signing.teams(byAccount: prefs), [Self.paid, Self.free])
        XCTAssertEqual(Signing.teams(byAccount: nil), [])
    }

    /// Without isFreeProvisioningTeam, the team type says.
    func testFreeFromTeamType() {
        let prefs: [String: Any] = ["me@example.com": [["teamID": "DDDDDDDDDD", "teamName": "Me", "teamType": "Personal Team"]]]
        XCTAssertEqual(Signing.teams(byAccount: prefs).first?.isFree, true)
    }

    func testPicksTheStoredTeam() throws {
        let team = try Signing.pick([Self.paid, Self.paid2], stored: Self.paid2.id, xcodeLast: Self.paid.id)
        XCTAssertEqual(team, Self.paid2)
    }

    func testPicksXcodesLastTeamThenTheOnlyPaidOne() throws {
        XCTAssertEqual(try Signing.pick([Self.paid, Self.paid2], stored: nil, xcodeLast: Self.paid2.id), Self.paid2)
        XCTAssertEqual(try Signing.pick([Self.paid, Self.free], stored: nil, xcodeLast: Self.free.id), Self.paid)
    }

    func testSeveralPaidTeamsNeedAChoice() {
        XCTAssertThrowsError(try Signing.pick([Self.paid, Self.paid2], stored: nil, xcodeLast: nil)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Pick a team")
        }
    }

    func testNoAccount() {
        XCTAssertThrowsError(try Signing.pick([], stored: nil, xcodeLast: nil)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "No Apple account in Xcode")
        }
    }

    /// Signed in to Xcode but no team listed (a Mac where Xcode never signed anything): the user is asked
    /// for the Team ID, not told to sign in.
    func testSignedInWithNoTeamsListed() {
        XCTAssertThrowsError(try Signing.pick([], stored: nil, xcodeLast: nil, signedIn: true)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Xcode hasn't listed your teams yet")
        }
        // Also with a team already chosen (e.g. after reinstalling Xcode): the list is missing, not the account.
        XCTAssertThrowsError(try Signing.pick([], stored: Self.paid.id, xcodeLast: nil, signedIn: true)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Xcode hasn't listed your teams yet")
        }
        XCTAssertFalse(Signing.hasAccount(appleIDLists: ["IDE.Prod": [Any]()]))
        XCTAssertFalse(Signing.hasAccount(appleIDLists: nil))
    }

    /// Which of Xcode's two Apple ID lists counts. Xcode 27.1 keeps both and empties only the identifiers
    /// at sign-out (the rc9 run: IDE.Identifiers.Prod 0, IDE.Prod 1), so the identifiers decide wherever
    /// they're kept; IDE.Prod alone is an older shape and counts then.
    func testAppleIDListShapes() {
        let user: [String: Any] = ["username": "me@example.com"]
        func id(_ n: Int) -> [String: Any] { ["identifier": "\(n)1111111-0000-0000-0000-000000000000"] }
        // Xcode 27.1 signed in, and signed out with IDE.Prod left behind.
        XCTAssertEqual(Signing.appleIDs(appleIDLists: ["IDE.Prod": [user], "IDE.Identifiers.Prod": [id(1)]]), 1)
        XCTAssertEqual(Signing.appleIDs(appleIDLists: ["IDE.Prod": [user], "IDE.Identifiers.Prod": [Any]()]), 0)
        XCTAssertFalse(Signing.hasAccount(appleIDLists: ["IDE.Prod": [user], "IDE.Identifiers.Prod": [Any]()]))
        // The lists out of step the other way (this Mac): the identifiers still count.
        XCTAssertEqual(Signing.appleIDs(appleIDLists: ["IDE.Prod": [user], "IDE.Identifiers.Prod": [id(1), id(2)]]), 2)
        // The older shape, Apple IDs by username only.
        XCTAssertEqual(Signing.appleIDs(appleIDLists: ["IDE.Prod": [user]]), 1)
        XCTAssertEqual(Signing.appleIDs(appleIDLists: ["IDE.Prod": [Any]()]), 0)
    }

    /// Xcode's preferences as the account step and Play read them (Signing.XcodeAccounts), in the three
    /// states the rc6 run went through on Xcode 27.1. Signed out, Xcode empties its Apple ID lists but the
    /// team can still be listed or typed in, and the stub build passes from Xcode's cache, so the empty
    /// lists alone have to fail the step.
    func testXcodeAccountStates() throws {
        let appleIDs: [String: Any] = ["IDE.Prod": [["username": "me@example.com"]],
                                       "IDE.Identifiers.Prod": [["identifier": "11111111-0000-0000-0000-000000000000"]]]
        let teamList: [String: Any] = ["11111111-0000-0000-0000-000000000000": [
            ["isFreeProvisioningTeam": 0, "teamID": Self.paid.id, "teamName": Self.paid.name, "teamType": "Company"],
        ]]
        let entered = Signing.Team(id: Self.paid.id, name: Self.paid.id, isFree: false)

        // Signed in, the team listed: it's picked, stored or not.
        let signedIn = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": appleIDs,
                                                     "IDEProvisioningTeamByIdentifier": teamList], entered: nil)
        XCTAssertEqual(signedIn.appleIDs, 1)
        XCTAssertEqual(try Signing.pick(signedIn, stored: nil), Self.paid)
        XCTAssertEqual(try Signing.pick(signedIn, stored: Self.paid.id), Self.paid)
        // Signed in on a Mac whose Xcode listed no team (the rc6 Mac): the typed Team ID is used.
        let typed = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": appleIDs], entered: entered)
        XCTAssertEqual(try Signing.pick(typed, stored: entered.id), entered)
        XCTAssertThrowsError(try Signing.pick(Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": appleIDs],
                                                                    entered: nil), stored: nil)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Xcode hasn't listed your teams yet")
        }

        // Signed out with the team cached: listed by Xcode, or typed in, and chosen. Both lists emptied, or
        // only the identifiers, as Xcode 27.1 does (the rc9 run).
        let emptied: [String: Any] = ["IDE.Prod": [Any](), "IDE.Identifiers.Prod": [Any]()]
        let staleName: [String: Any] = ["IDE.Prod": [["username": "me@example.com"]], "IDE.Identifiers.Prod": [Any]()]
        for prefs: [String: Any] in [["DVTDeveloperAccountManagerAppleIDLists": emptied, "IDEProvisioningTeamByIdentifier": teamList],
                                     ["DVTDeveloperAccountManagerAppleIDLists": emptied],
                                     ["DVTDeveloperAccountManagerAppleIDLists": staleName, "IDEProvisioningTeamByIdentifier": teamList],
                                     ["DVTDeveloperAccountManagerAppleIDLists": staleName,
                                      "IDEProvisioningTeams": ["me@example.com": teamList.values.first!]]] {
            let out = Signing.XcodeAccounts(prefs: prefs, entered: entered)
            XCTAssertFalse(out.signedIn)
            XCTAssertEqual(out.teams, [entered], "only the typed team: no account is signed in")
            XCTAssertFalse(out.known.isEmpty, "the team is still known")
            XCTAssertThrowsError(try Signing.pick(out, stored: Self.paid.id)) {
                XCTAssertTrue(($0 as? Signing.Problem)?.title.hasPrefix("No Apple account in Xcode for ") == true, "\($0)")
            }
            XCTAssertThrowsError(try Signing.pick(out, stored: nil)) {
                XCTAssertEqual(($0 as? Signing.Problem)?.title, "No Apple account in Xcode")
            }
        }
        // Xcode's own name for the team when it lists it.
        XCTAssertThrowsError(try Signing.pick(Signing.XcodeAccounts(prefs: ["IDEProvisioningTeamByIdentifier": teamList], entered: nil),
                                              stored: Self.paid.id)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "No Apple account in Xcode for Acme Games LLC")
        }

        // No account ever: nothing in Xcode's preferences.
        let none = Signing.XcodeAccounts(prefs: [:], entered: nil)
        XCTAssertEqual(none.appleIDs, 0)
        XCTAssertThrowsError(try Signing.pick(none, stored: nil)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "No Apple account in Xcode")
        }
    }

    /// Xcode 27.1 saves no team list of its own until a project's Team menu asks (the rc6 Mac), so the
    /// teams come from xcodebuild's list (Signing.fetchTeams), Personal Team included. Every list keeps
    /// accounts signed out long ago, so only the signed-in accounts' teams are offered.
    func testTeamsFromXcodebuildsList() throws {
        let me = "11111111-0000-0000-0000-000000000000", gone = "22222222-0000-0000-0000-000000000000"
        let appleIDs: [String: Any] = ["IDE.Prod": [["username": "me@example.com"]], "IDE.Identifiers.Prod": [["identifier": me]]]
        func entry(_ t: Signing.Team) -> [String: Any] {
            ["isFreeProvisioningTeam": t.isFree, "teamID": t.id, "teamName": t.name, "teamType": t.isFree ? "Personal Team" : "Company"]
        }
        let xcodebuild: [String: Any] = ["IDEProvisioningTeamByIdentifier": [me: [entry(Self.free), entry(Self.paid)]]]

        // The rc6 Mac: Xcode lists the Apple ID and no team; xcodebuild's list has both.
        let neo = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": appleIDs], xcodebuild: xcodebuild, entered: nil)
        XCTAssertEqual(neo.teams, [Self.paid, Self.free])
        XCTAssertEqual(try Signing.pick(neo, stored: Self.free.id), Self.free)

        // Xcode's own lists name an account signed out long ago (this Mac): its team isn't offered, and
        // xcodebuild's name wins for a team both list.
        let renamed = Signing.Team(id: Self.paid.id, name: "Old Name", isFree: false)
        let prefs: [String: Any] = ["DVTDeveloperAccountManagerAppleIDLists": appleIDs,
                                    "IDEProvisioningTeamByIdentifier": [gone: [entry(Self.paid2)], me: [entry(renamed)]],
                                    "IDEProvisioningTeams": ["old@example.com": [entry(Self.paid2)]]]
        let stale = Signing.XcodeAccounts(prefs: prefs, xcodebuild: xcodebuild, entered: nil)
        XCTAssertEqual(stale.teams, [Self.paid, Self.free])
        XCTAssertEqual(Set(stale.known), [Self.paid, Self.paid2, Self.free])
        XCTAssertThrowsError(try Signing.pick(stale, stored: Self.paid2.id)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Team \(Self.paid2.id) isn't signed in")
        }
        // The older list, by Apple ID, for the signed-in one.
        let byName = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": appleIDs,
                                                   "IDEProvisioningTeams": ["me@example.com": [entry(Self.paid2)]]], entered: nil)
        XCTAssertEqual(byName.teams, [Self.paid2])
        // Apple IDs without identifiers (an older shape): the lists by identifier are taken whole.
        let noIDs = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": ["IDE.Prod": [["username": "me@example.com"]]]],
                                          xcodebuild: xcodebuild, entered: nil)
        XCTAssertEqual(noIDs.teams, [Self.paid, Self.free])

        // Signed out: nothing offered, the names still known.
        let out = Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": ["IDE.Prod": [Any](), "IDE.Identifiers.Prod": [Any]()]],
                                        xcodebuild: xcodebuild, entered: nil)
        XCTAssertEqual(out.teams, [])
        XCTAssertEqual(out.known, [Self.paid, Self.free])

        // An account added in Xcode changes the key the account step fetches again on.
        var two = appleIDs
        two["IDE.Identifiers.Prod"] = [["identifier": me], ["identifier": gone]]
        two["IDE.Prod"] = [["username": "me@example.com"], ["username": "scratch@example.com"]]
        XCTAssertNotEqual(Signing.XcodeAccounts(prefs: ["DVTDeveloperAccountManagerAppleIDLists": two], entered: nil).accountsKey,
                          neo.accountsKey)
        XCTAssertTrue(Signing.isValidTeamID(Signing.unknownTeam))
    }

    /// Opt-in, local only (asks Apple for this Mac's Xcode accounts' teams, rewriting xcodebuild's list):
    /// the fetch lists at least one team for a signed-in Xcode. Run with
    /// TEST_RUNNER_SP_FETCH_TEAMS_STUB=<companion app>/Contents/Resources/signing.
    func testFetchTeamsWithXcode() async throws {
        guard let stub = ProcessInfo.processInfo.environment["SP_FETCH_TEAMS_STUB"].map(URL.init(fileURLWithPath:)) else {
            throw XCTSkip("set SP_FETCH_TEAMS_STUB to ask Xcode for the teams")
        }
        guard Signing.xcodeListsAccount else { throw XCTSkip("Xcode lists no Apple ID") }
        let work = FileManager.default.temporaryDirectory.appending(path: "sp-fetch-teams-\(UUID().uuidString)")
        let started = Date()
        await Signing.fetchTeams(stub: stub, work: work) { print("fetch: \($0)") }
        print("fetched in \(Date().timeIntervalSince(started)) s")
        let fresh = Signing.XcodeAccounts(prefs: [:], xcodebuild: Signing.preferences(Signing.xcodebuildDomain), entered: nil)
        XCTAssertFalse(fresh.known.isEmpty, "xcodebuild's list has the teams")
        XCTAssertFalse(Signing.teams().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
    }

    /// Xcode's preferences are read in a new process each time, so a plist file rewritten under a running
    /// companion (as Xcode's sign-in does) is seen at once. A scratch plist in $TMPDIR stands in.
    func testPreferencesFollowAFileRewrite() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "SPPrefsTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "com.strawdynamics.slashplayed.prefs-test.plist")
        func write(_ n: Int) throws {
            try PropertyListSerialization.data(fromPropertyList: ["DVTDeveloperAccountManagerAppleIDLists":
                ["IDE.Prod": Array(repeating: ["username": "me@example.com"], count: n)]], format: .binary, options: 0)
                .write(to: file, options: .atomic)
        }
        try write(0)
        XCTAssertEqual(Signing.appleIDs(appleIDLists: Signing.preferences(file.path)["DVTDeveloperAccountManagerAppleIDLists"]), 0)
        try write(1)
        XCTAssertEqual(Signing.appleIDs(appleIDLists: Signing.preferences(file.path)["DVTDeveloperAccountManagerAppleIDLists"]), 1)
        XCTAssertTrue(Signing.preferences(dir.appending(path: "missing.plist").path).isEmpty)
    }

    /// A typed-in team joins Xcode's list unless Xcode has it (Xcode's entry wins), and is then picked
    /// like any other.
    func testEnteredTeam() throws {
        let entered = Signing.Team(id: Self.paid.id, name: Self.paid.id, isFree: false)
        XCTAssertEqual(Signing.merged([], entered: entered), [entered])
        XCTAssertEqual(Signing.merged([Self.paid, Self.free], entered: entered), [Self.paid, Self.free])
        XCTAssertEqual(Signing.merged([Self.free], entered: entered), [Self.free, entered])
        XCTAssertEqual(Signing.merged([Self.free], entered: nil), [Self.free])
        XCTAssertEqual(try Signing.pick(Signing.merged([], entered: entered), stored: nil, xcodeLast: nil, signedIn: true), entered)
        XCTAssertTrue(Signing.isValidTeamID("A1B2C3D4E5"))
        for bad in ["a1b2c3d4e5", "A1B2C3D4E", "A1B2C3D4E5F", "A1B2-3D4E5", ""] { XCTAssertFalse(Signing.isValidTeamID(bad), bad) }
    }

    /// Opt-in, local only (signs in with this Mac's Xcode account and asks Apple for a profile): checks a
    /// Team ID as onboarding does, with the bundled stub. Run with TEST_RUNNER_SP_VERIFY_TEAM=<team ID>
    /// TEST_RUNNER_SP_VERIFY_STUB=<companion app>/Contents/Resources/signing.
    func testVerifyTeamWithXcode() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["SP_VERIFY_TEAM"], let stub = env["SP_VERIFY_STUB"].map(URL.init(fileURLWithPath:)) else {
            throw XCTSkip("set SP_VERIFY_TEAM and SP_VERIFY_STUB to check a team with Xcode")
        }
        let work = FileManager.default.temporaryDirectory.appending(path: "sp-verify-team-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let team = try await Signing.verifyTeam(id, stub: stub, work: work) { print("verify: \($0)") }
        print("verified: \(team)")
        XCTAssertEqual(team.id, id)
        XCTAssertNotEqual(team.name, id, "the profile names the team")
    }

    /// A free team's profile lasts 7 days, a paid team's a year.
    func testFreeFromProfileLifetime() {
        XCTAssertTrue(Signing.isFreeProfile(lifetime: 7 * 24 * 3600))
        XCTAssertFalse(Signing.isFreeProfile(lifetime: 365 * 24 * 3600))
        XCTAssertFalse(Signing.isFreeProfile(lifetime: nil))
    }

    /// Free teams sign too (with a 7-day profile and without extended-virtual-addressing), but a paid
    /// team wins the automatic choice.
    func testFreeTeams() throws {
        for stored in [nil, Self.free.id] {
            XCTAssertEqual(try Signing.pick([Self.free], stored: stored, xcodeLast: nil), Self.free)
        }
        XCTAssertEqual(try Signing.pick([Self.paid, Self.free], stored: nil, xcodeLast: nil), Self.paid)
        XCTAssertEqual(try Signing.pick([Self.paid, Self.free], stored: Self.free.id, xcodeLast: Self.paid.id), Self.free)
        XCTAssertThrowsError(try Signing.pick([Self.paid, Self.paid2, Self.free], stored: nil, xcodeLast: Self.free.id)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Pick a team")
        }
        XCTAssertEqual(Signing.dropped(for: Self.free), ["com.apple.developer.kernel.extended-virtual-addressing"])
        XCTAssertEqual(Signing.dropped(for: Self.paid), [])
    }

    /// A profile's UUID and expiry, from the plist inside its CMS envelope (made-up bytes around one here).
    func testProfileInfo() throws {
        let expires = Date(timeIntervalSince1970: 1_800_000_000)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "UUID": "31035C83-0000-0000-0000-000000000000", "ExpirationDate": expires, "Name": "Test",
        ], format: .xml, options: 0)
        let envelope = Data([0x30, 0x80, 0x06, 0x09]) + plist + Data([0xA0, 0x80, 0x30, 0x80, 0x00, 0x00])
        XCTAssertEqual(Signing.profileInfo(envelope), Signing.ProfileInfo(uuid: "31035C83-0000-0000-0000-000000000000", expires: expires))
        XCTAssertNil(Signing.profileInfo(Data("not a profile".utf8)))
    }

    /// devicectl lists a profile's UUID in upper case and its plist has it in lower case: the same profile.
    func testDeviceListsAProfileWhateverTheCase() {
        let result: [String: Any] = ["provisioningProfiles": [
            ["uuid": "47619D43-0000-0000-0000-000000000000", "name": "iOS Team Provisioning Profile: X.slashplayed"],
            ["uuid": "AC1E1390-0000-0000-0000-00000000000A", "name": "iOS Team Provisioning Profile: X.slashplayed"],
        ]]
        XCTAssertTrue(Device.listsProfile(result, uuid: "ac1e1390-0000-0000-0000-00000000000a"))
        XCTAssertTrue(Device.listsProfile(result, uuid: "AC1E1390-0000-0000-0000-00000000000A"))
        XCTAssertFalse(Device.listsProfile(result, uuid: "16b16f6d-0000-0000-0000-000000000000"))
        XCTAssertFalse(Device.listsProfile([:], uuid: "ac1e1390-0000-0000-0000-00000000000a"))
    }

    func testStoredTeamSignedOut() {
        XCTAssertThrowsError(try Signing.pick([Self.paid], stored: Self.paid2.id, xcodeLast: nil)) {
            XCTAssertEqual(($0 as? Signing.Problem)?.title, "Team \(Self.paid2.id) isn't signed in")
        }
    }

    func testProvisioningErrors() {
        let cases = [
            "error: Developer Mode disabled: To use Paul's iPad for development, enable Developer Mode in Settings → Privacy & Security.":
                "Developer Mode is off",
            "error: No Accounts: Add a new account in Accounts settings. (in target 'SPProfiles' from project 'SPProfiles')":
                "No Apple account in Xcode for Acme Games LLC",
            "xcodebuild: error: Unable to find a destination matching the provided destination specifier:":
                "Xcode can't see the device",
            // Provisioning for an unworn headset (rc8's run; the UDID left out).
            "xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier:\n\t\t{ id:<udid> }\n\n\tIneligible destinations for the \"SPProfiles\" scheme:\n\t\t{ platform:visionOS, id:<udid>, name:Vision Pro, error:The device needs to be unlocked to continue Unlock the device, then ensure it is discoverable via Bluetooth/WiFi or attached with a cable. }":
                "The device is locked",
            "xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier:":
                "Xcode can't see the device",
            "You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license'":
                "Xcode's license isn't accepted",
            "error: Personal development teams, including \"Some One\", do not support the Extended Virtual Address Space capability.":
                "Acme Games LLC is a free team and Apple refused this",
            "error: Revoke certificate: Your account already has an Apple Development signing certificate for this machine, but its private key is not installed in your keychain.":
                "This Mac's signing certificate is in another keychain",
            "error: Something new went wrong.": "Couldn't make a provisioning profile",
        ]
        for (output, title) in cases {
            let errors = output.split(separator: "\n").filter { $0.contains("error:") }.map(String.init)
            XCTAssertEqual(Signing.provisioningProblem(output, errors: errors, team: Self.paid).title, title, output)
        }
        XCTAssertTrue(Signing.provisioningProblem("error: Something new went wrong.", errors: ["error: Something new went wrong."],
                                                  team: Self.paid).message.contains("Something new went wrong"))
    }

    /// Xcode's preferences list an Apple ID that is no longer signed in (a login-keychain reset takes the
    /// token and leaves the list, as in the rc4 acceptance run), so the account step builds the stub and
    /// goes by what xcodebuild says. Play's failure there, as captured (UDIDs left out): "No Accounts" wins
    /// over the missing identity it also reports, since signing in is the fix for both.
    func testBuildWithNoAccount() {
        let output = """
            error: No Accounts: Add a new account in Accounts settings. (in target 'SPProfiles' from project 'SPProfiles')
            error: Revoke certificate: Your account already has an Apple Development signing certificate for this machine, but its private key is not installed in your keychain. Xcode can create a new one after revoking your existing certificate. (in target 'SPProfiles' from project 'SPProfiles')
            error: No signing certificate "iOS Development" found: No "iOS Development" signing certificate matching team ID "AAAAAAAAAA" with a private key was found. (in target 'SPProfiles' from project 'SPProfiles')
            ** BUILD FAILED **
            """
        let errors = output.split(separator: "\n").filter { $0.contains("error:") }.map(String.init)
        XCTAssertEqual(Signing.buildProblem(status: 65, output: output, errors: errors, team: Self.paid)?.title,
                       "No Apple account in Xcode for Acme Games LLC")
        // A build that passed from what Xcode cached but says it has no account still fails the check.
        let cached = "error: No Account for Team \"AAAAAAAAAA\": Add a new account in Accounts settings or verify that your accounts have valid credentials.\n** BUILD SUCCEEDED **"
        XCTAssertEqual(Signing.buildProblem(status: 0, output: cached, errors: [String(cached.split(separator: "\n")[0])],
                                            team: Self.paid)?.title, "No Apple account in Xcode for Acme Games LLC")
        // A clean build passes, whatever its log mentions outside error lines.
        let clean = "Signing Identity:     \"Apple Development: Some One (\(Self.free.id))\"\nNo Accounts.txt\n** BUILD SUCCEEDED **"
        XCTAssertNil(Signing.buildProblem(status: 0, output: clean, errors: [], team: Self.paid))
        XCTAssertTrue(Signing.hasAccount(appleIDLists: ["IDE.Prod": [["username": "me@example.com"]]]),
                      "the listing alone still reads as an account: only the build can tell")
    }

    /// The identity the stub was signed with has to be in find-identity -v's list (valid, with its private
    /// key); after a keychain reset it isn't, and "0 valid identities found" names no hash at all.
    func testSigningKeyInKeychain() {
        let hash = String(repeating: "AB12", count: 10)
        let listed = """
              1) \(hash) "Apple Development: Some One (\(Self.free.id))"
              2) \(String(repeating: "CD34", count: 10)) "Developer ID Application: Acme Games LLC (\(Self.paid.id))"
                 2 valid identities found
            """
        XCTAssertNil(Signing.keyProblem(hash: hash, name: "Apple Development: Some One", identities: listed, team: Self.paid))
        XCTAssertNil(Signing.keyProblem(hash: hash.lowercased(), name: "x", identities: listed, team: Self.paid))
        for identities in ["     0 valid identities found\n",
                           "  1) \(String(repeating: "CD34", count: 10)) \"Apple Development: Other (\(Self.paid2.id))\"\n     1 valid identities found\n",
                           // The hash in a name, not as a listed identity, doesn't count.
                           "  1) \(String(repeating: "CD34", count: 10)) \"\(hash)\"\n"] {
            XCTAssertEqual(Signing.keyProblem(hash: hash, name: "Apple Development: Some One", identities: identities, team: Self.paid)?.title,
                           "No signing key for Apple Development: Some One", identities)
        }
    }
}
