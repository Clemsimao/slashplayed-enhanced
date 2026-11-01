// The newer-build screen, in SwiftUI (sppatch.m keeps the check, the download, the update, and the wait for
// a choice): the news, what to do, a progress line while it downloads (sp_screen_status), a quieter note
// under it (the build this device has, or why an update failed), and the buttons sppatch.m offers. The
// first button is the screen's action, drawn as a game button; any other is gold text under it, as the
// pairing screen's "No code?" is, so the one to press reads first. Without buttons a spinner turns.
import SwiftUI
import UIKit

final class PatchModel: ObservableObject {
    @Published var heading = ""
    @Published var message = ""
    @Published var note = ""
    @Published var buttons: [String] = []
}

private struct PatchView: View {
    @ObservedObject var screen: ScreenModel
    @ObservedObject var model: PatchModel
    let choose: (Int) -> Void

    var body: some View {
        LauncherScreen(model: screen, title: model.heading, message: model.message) {
            VStack(spacing: 20) {
                if !model.note.isEmpty {
                    Text(model.note).font(.footnote).foregroundStyle(gold.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.buttons.isEmpty {
                    ProgressView().controlSize(.large).tint(gold)
                } else {
                    ForEach(Array(model.buttons.enumerated()), id: \.offset) { i, title in
                        if i == 0 {
                            Button(title) { choose(i) }
                                .buttonStyle(GameButtonStyle(height: 56))
                                .frame(maxWidth: 380)
                        } else {
                            Button(title) { choose(i) }.foregroundStyle(gold)
                        }
                    }
                }
            }
        }
    }
}

// The screen; `choose` gets the index of the button tapped, in sp_patch_show's order.
@_cdecl("sp_patch_screen")
public func patchScreen(_ choose: @escaping @convention(block) (Int) -> Void) -> UIViewController {
    let screen = ScreenModel(), model = PatchModel()
    let host = LauncherHost(model: screen, view: PatchView(screen: screen, model: model, choose: choose))
    host.patch = model
    return host
}

// What it says now. A new state clears the progress line: only the download sets it.
@_cdecl("sp_patch_show")
public func patchShow(_ host: UIViewController, _ heading: NSString, _ message: NSString, _ note: NSString?,
                      _ buttons: NSArray) {
    guard let host = host as? LauncherHost, let model = host.patch else { return }
    model.heading = heading as String
    model.message = message as String
    model.note = (note as String?) ?? ""
    model.buttons = buttons.compactMap { $0 as? String }
    host.model.status = ""
}
