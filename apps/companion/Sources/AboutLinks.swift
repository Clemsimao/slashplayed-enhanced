import AppKit

/// Opens the About panel's credit links with the call the Help menu uses. The standard About panel opens a
/// clicked link itself, and for the Acknowledgements folder (a file URL into the app's Resources) that fails
/// with Finder's "The application can't be opened. -50", while `NSWorkspace.open` on the same URL shows the
/// folder. So `About.show` makes this the panel's text view's delegate, and every link goes through `open`.
final class AboutLinks: NSObject, NSTextViewDelegate {
    let open: (URL) -> Void
    init(open: @escaping (URL) -> Void) { self.open = open }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        open(url)
        return true
    }

    /// The text views under `view` whose text contains `credits`: the panel's credits, not its other fields.
    static func textViews(in view: NSView, showing credits: String) -> [NSTextView] {
        if let text = view as? NSTextView, text.string.contains(credits) { return [text] }
        return view.subviews.flatMap { textViews(in: $0, showing: credits) }
    }
}
