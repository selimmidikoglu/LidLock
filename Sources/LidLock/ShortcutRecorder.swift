import Carbon.HIToolbox
import AppKit
import SwiftUI

/// The little "press a key" well in Settings.
///
/// A plain `NSView` rather than SwiftUI's key handling: a shortcut recorder has
/// to see the raw key code and the modifier flags of a combination that is
/// meaningless as text, which is exactly what `keyDown` hands over.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Hotkey.Shortcut?
    var onRecorded: (Hotkey.Shortcut?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecorded = onRecorded
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.onRecorded = onRecorded
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var shortcut: Hotkey.Shortcut?
        var onRecorded: ((Hotkey.Shortcut?) -> Void)?
        private var listening = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

        override func mouseDown(with event: NSEvent) {
            listening = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            listening = false
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard listening else { return super.keyDown(with: event) }

            if event.keyCode == UInt16(kVK_Escape) {
                listening = false
                return
            }

            if event.keyCode == UInt16(kVK_Delete) {
                shortcut = nil
                listening = false
                onRecorded?(nil)
                return
            }

            // A shortcut without a real modifier would swallow a letter
            // everywhere on the Mac, so hold out for one.
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !flags.intersection([.command, .control, .option]).isEmpty,
                  let typed = event.charactersIgnoringModifiers, !typed.isEmpty else {
                NSSound.beep()
                return
            }

            let recorded = Hotkey.Shortcut(
                keyCode: event.keyCode,
                modifiers: flags.rawValue,
                label: typed.uppercased()
            )
            shortcut = recorded
            listening = false
            onRecorded?(recorded)
        }

        override func draw(_ dirtyRect: NSRect) {
            let box = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
            (listening ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                       : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
            path.fill()
            (listening ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = listening ? 2 : 1
            path.stroke()

            let text = listening ? "Press keys…" : (shortcut?.display ?? "Click to set")
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: shortcut == nil ? .regular : .medium),
                .foregroundColor: listening || shortcut != nil
                    ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: style,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                in: NSRect(x: 0, y: (bounds.height - size.height) / 2,
                           width: bounds.width, height: size.height),
                withAttributes: attributes
            )
        }
    }
}
