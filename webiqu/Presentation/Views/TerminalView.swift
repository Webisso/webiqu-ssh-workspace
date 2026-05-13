import AppKit
import SwiftUI

struct TerminalView: NSViewRepresentable {
    @Binding var output: String
    let isConnected: Bool
    let textColorName: String
    let onInput: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TerminalTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor.black
        textView.textColor = TerminalColorPalette.nsColor(named: textColorName)
        textView.insertionPointColor = TerminalColorPalette.nsColor(named: textColorName)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = output
        textView.onInput = onInput

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.black
        scrollView.documentView = textView

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }
        textView.onInput = onInput
        textView.isConnected = isConnected
        textView.textColor = TerminalColorPalette.nsColor(named: textColorName)
        textView.insertionPointColor = TerminalColorPalette.nsColor(named: textColorName)

        if textView.string != output {
            textView.string = output
            let endRange = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.scrollRangeToVisible(endRange)
            textView.scrollToEndOfDocument(nil)
        }

        if isConnected, textView.window?.firstResponder !== textView {
            textView.window?.makeFirstResponder(textView)
        }

        if isConnected {
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var textView: TerminalTextView?
    }
}

struct TerminalPanel: View {
    @Binding var output: String
    let isConnected: Bool
    let textColorName: String
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                TerminalView(
                    output: $output,
                    isConnected: isConnected,
                    textColorName: textColorName,
                    onInput: onInput
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "LIVE" : "IDLE")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(10)
            }
            .onAppear {
                if output.isEmpty {
                    output = "[terminal ready] Press Connect to start interactive shell.\n"
                }
                notifySize(proxy.size)
            }
            .onChange(of: proxy.size) { _, newSize in
                notifySize(newSize)
            }
        }
        .padding(12)
    }

    private func notifySize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        // Approximate terminal character grid from current view size and font metrics.
        let columns = max(40, Int(size.width / 8.0))
        let rows = max(12, Int(size.height / 16.0))
        onResize(columns, rows)
    }
}

final class TerminalTextView: NSTextView {
    var onInput: ((String) -> Void)?
    var isConnected = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isConnected {
            window?.makeFirstResponder(self)
            moveCaretToEnd()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isConnected else {
            super.mouseDown(with: event)
            return
        }

        // Keep insertion point at the live command line, regardless of click location.
        window?.makeFirstResponder(self)
        moveCaretToEnd()
    }

    override func keyDown(with event: NSEvent) {
        guard isConnected else {
            super.keyDown(with: event)
            return
        }

        if event.modifierFlags.contains(.control), let chars = event.charactersIgnoringModifiers, chars.count == 1,
           let scalar = chars.unicodeScalars.first {
            let value = scalar.value
            if value >= 97 && value <= 122 {
                let controlCode = UnicodeScalar(value - 96)!
                onInput?(String(controlCode))
                return
            }
        }

        switch event.keyCode {
        case 51, 117: // delete/backspace
            onInput?("\u{7F}")
            return
        case 123: // left
            onInput?("\u{1B}[D")
            return
        case 124: // right
            onInput?("\u{1B}[C")
            return
        case 125: // down
            onInput?("\u{1B}[B")
            return
        case 126: // up
            onInput?("\u{1B}[A")
            return
        case 48: // tab
            onInput?("\t")
            return
        case 36, 76: // return / keypad enter
            onInput?("\n")
            return
        default:
            break
        }

        if let text = event.characters, !text.isEmpty {
            onInput?(text)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isConnected else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           chars.lowercased() == "v",
           let pasted = NSPasteboard.general.string(forType: .string),
           !pasted.isEmpty {
            onInput?(pasted)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func moveCaretToEnd() {
        let end = (string as NSString).length
        setSelectedRange(NSRange(location: end, length: 0))
        scrollToEndOfDocument(nil)
    }
}

enum TerminalColorPalette {
    static let names: [String] = [
        "white",
        "green",
        "amber",
        "cyan",
        "blue",
        "mint",
        "pink",
        "red",
        "violet",
        "gray"
    ]

    static func nsColor(named name: String) -> NSColor {
        switch name {
        case "green":
            return NSColor.systemGreen
        case "amber":
            return NSColor.systemOrange
        case "cyan":
            return NSColor.systemCyan
        case "blue":
            return NSColor.systemBlue
        case "mint":
            return NSColor.systemMint
        case "pink":
            return NSColor.systemPink
        case "red":
            return NSColor.systemRed
        case "violet":
            return NSColor.systemPurple
        case "gray":
            return NSColor.lightGray
        default:
            return NSColor.white
        }
    }

    static func title(named name: String) -> String {
        switch name {
        case "green":
            return "Green"
        case "amber":
            return "Amber"
        case "cyan":
            return "Cyan"
        case "blue":
            return "Blue"
        case "mint":
            return "Mint"
        case "pink":
            return "Pink"
        case "red":
            return "Red"
        case "violet":
            return "Violet"
        case "gray":
            return "Gray"
        default:
            return "White"
        }
    }
}
