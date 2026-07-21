import SwiftUI

// NSView that shows a native tooltip without intercepting mouse events.
// Use .tooltip() instead of .help() — .help() fails in ToolbarItem/borderless buttons.
final class TooltipView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct TooltipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = TooltipView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

extension View {
    func tooltip(_ text: String) -> some View {
        self.overlay(TooltipOverlay(text: text))
    }
}
