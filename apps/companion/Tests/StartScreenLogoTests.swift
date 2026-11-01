import XCTest

/// The start screen draws its logo from apps/client/splogo.h (spstartscreen.swift), a copy of the app icon's own
/// vectors: this checks the copy against the icon's two SVGs, so the icon can't change without the logo.
final class StartScreenLogoTests: XCTestCase {
    static let assets = ClientAssemblyTests.repo.appending(path: "apps/client/icons/AppIcon.icon/Assets")

    /// The value of `attribute` on the first `element` in the SVG `file`.
    func attribute(_ attribute: String, of element: String, in file: String) throws -> String {
        let svg = try String(contentsOf: Self.assets.appending(path: file), encoding: .utf8)
        let tag = try XCTUnwrap(svg.firstMatch(of: try Regex("<\(element)\\s[^>]*>")), "no <\(element)> in \(file)")
        let value = try XCTUnwrap(svg[tag.range].firstMatch(of: try Regex("\\s\(attribute)=\"([^\"]*)\"")), "no \(attribute) on \(file)'s <\(element)>")
        return String(try XCTUnwrap(value.output[1].substring))
    }

    func number(_ name: String, of element: String, in file: String) throws -> Double {
        try XCTUnwrap(Double(attribute(name, of: element, in: file)))
    }

    func testSPathIsTheIcons() throws {
        XCTAssertEqual(SP_LOGO_S_PATH, try attribute("d", of: "path", in: "S.svg"))
        XCTAssertEqual(SP_LOGO_GOLD, try attribute("fill", of: "path", in: "S.svg").lowercased())
    }

    func testMedallionIsTheIcons() throws {
        XCTAssertEqual(SP_LOGO_SQUARE_ORIGIN, try number("x", of: "rect", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_SQUARE_ORIGIN, try number("y", of: "rect", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_SQUARE_SIDE, try number("width", of: "rect", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_SQUARE_SIDE, try number("height", of: "rect", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_GOLD, try attribute("fill", of: "rect", in: "medallion.svg").lowercased())
        XCTAssertEqual(SP_LOGO_DISC_CENTER, try number("cx", of: "circle", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_DISC_CENTER, try number("cy", of: "circle", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_DISC_RADIUS, try number("r", of: "circle", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_RING_WIDTH, try number("stroke-width", of: "circle", in: "medallion.svg"))
        XCTAssertEqual(SP_LOGO_DISC_FILL, try attribute("fill", of: "circle", in: "medallion.svg").lowercased())
        XCTAssertEqual(SP_LOGO_GOLD, try attribute("stroke", of: "circle", in: "medallion.svg").lowercased())
    }
}
