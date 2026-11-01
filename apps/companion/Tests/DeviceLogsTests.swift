import XCTest

/// DeviceLogs.summarize on a made-up console log in the shims' format (spstats.m's stats lines).
final class DeviceLogsTests: XCTestCase {
    func testSummarizesStatsAndEvents() {
        let log = """
            22:12:26 [sp:system] lifecycle: launched
            22:12:56 [sp:AppKit] stats: 56.8 fps, worst 76 ms, 2 over 50 ms | gpu 49% (8.6 ms/frame, 5127 buffers) | cpu 25% (57 threads: ? 14%) | footprint 873 MB (peak 899), 7318 MB left | thermal fair
            22:13:26 [sp:AppKit] stub hit: stats: 81.4 fps, worst 252 ms, 18 over 50 ms | gpu 88% (10.8 ms/frame, 36779 buffers) | cpu 65% (57 threads: ? 26%) | footprint 1563 MB (peak 1577), 6628 MB left | thermal serious
            22:13:40 [sp:system] MEMORY warning
            22:13:41 [sp:AppKit] quit

            """
        let summary = DeviceLogs.summarize(log, name: "spconsole.log")
        // Lines are cut at 160 characters, as pull-logs.sh's cut -c1-160.
        let stats = log.split(separator: "\n").filter { $0.contains("stats: ") }.map { $0.prefix(160) }
        XCTAssertEqual(summary, """
            == spconsole.log: 22:12:26 to 22:13:41
              2 stats lines: 69.1 fps average, 56.8 lowest 30 s, worst frame 252 ms, 20 frames over 50 ms
              footprint peak 1577 MB, least left 6628 MB, thermal fair/serious
              events:
                22:12:26 [sp:system] lifecycle: launched
                22:13:40 [sp:system] MEMORY warning
              last lines:
                22:12:26 [sp:system] lifecycle: launched
                \(stats[0])
                \(stats[1])
                22:13:40 [sp:system] MEMORY warning
                22:13:41 [sp:AppKit] quit
            """)
    }

    func testNoStatsLines() {
        let summary = DeviceLogs.summarize("10:00:00 started\n", name: "spconsole.1.log")
        XCTAssertTrue(summary.hasPrefix("== spconsole.1.log: 10:00:00 to 10:00:00\n  no stats lines\n"), summary)
    }
}
