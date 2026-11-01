import XCTest

/// When a scheduled update may show (UpdateGate): never while busy, once on the next idle edge after
/// it was held, and not again after the user has seen it.
final class UpdateGateTests: XCTestCase {
    func testShowsAtOnceWhenIdle() {
        XCTAssertTrue(UpdateGate.sparkleShouldShowScheduledUpdate(busy: false))
        var gate = UpdateGate()
        XCTAssertTrue(gate.updateDeferred(busy: false))
        XCTAssertFalse(gate.isHoldingUpdate)
    }

    func testHoldsWhileBusyAndReleasesOnceOnIdle() {
        XCTAssertFalse(UpdateGate.sparkleShouldShowScheduledUpdate(busy: true))
        var gate = UpdateGate()
        XCTAssertFalse(gate.updateDeferred(busy: true))
        XCTAssertTrue(gate.isHoldingUpdate)
        XCTAssertFalse(gate.busyChanged(true))
        XCTAssertTrue(gate.busyChanged(false))
        XCTAssertFalse(gate.busyChanged(true))
        XCTAssertFalse(gate.busyChanged(false))
    }

    func testNothingToReleaseAfterTheUserSawIt() {
        var gate = UpdateGate()
        _ = gate.updateDeferred(busy: true)
        gate.updateHandled()
        XCTAssertFalse(gate.busyChanged(false))
    }
}
