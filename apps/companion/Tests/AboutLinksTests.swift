import AppKit
import XCTest

/// The About panel's links go through the companion's own opener (AboutLinks), not the panel's link
/// handling, which fails on the Acknowledgements folder with Finder's -50.
@MainActor final class AboutLinksTests: XCTestCase {
    func testAFolderLinkGoesToTheOpener() throws {
        var opened: [URL] = []
        let links = AboutLinks(open: { opened.append($0) })
        let folder = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory).appending(path: "Acknowledgements")
        let text = NSTextView()
        text.textStorage?.setAttributedString(NSAttributedString(string: "Acknowledgements", attributes: [.link: folder]))
        text.delegate = links
        text.clicked(onLink: folder, at: 0)
        XCTAssertEqual(opened, [folder])
        // A link given as a string (NSTextView allows either) is opened as its URL.
        text.clicked(onLink: "https://slashplayed.strawdynamics.com", at: 0)
        XCTAssertEqual(opened.last, URL(string: "https://slashplayed.strawdynamics.com"))
    }

    func testFindsOnlyTheCreditsView() {
        let root = NSView()
        let credits = NSTextView(), other = NSTextView()
        credits.string = "Runs the Mac World of Warcraft clients on iPad.\nUnofficial."
        other.string = "Copyright"
        let group = NSView()
        group.addSubview(credits)
        root.addSubview(group)
        root.addSubview(other)
        XCTAssertEqual(AboutLinks.textViews(in: root, showing: "Runs the Mac World of Warcraft clients on iPad."), [credits])
    }
}
