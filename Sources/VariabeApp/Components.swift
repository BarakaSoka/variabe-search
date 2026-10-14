import AppKit
import VariabeKit
import SwiftUI

/// The app's colors: Spotlight's neutral grays, light in Light Mode and dark in Dark Mode (each color resolves for the
/// appearance it's drawn in, so the app follows System Settings by itself). No hues: text, icons and selection are
/// shades of the label color, and depth comes from Liquid Glass (`glass(in:)`), not tint.
enum Brand {
    /// Controls that need a color (toggles, links, the field's ring): a mid gray that reads on both appearances.
    static let accent = adaptive(light: NSColor(white: 0.28, alpha: 1), dark: NSColor(white: 0.80, alpha: 1))
    /// The strongest gray: near-black in Light Mode, near-white in Dark Mode.
    static let ink = adaptive(light: NSColor(white: 0.11, alpha: 1), dark: NSColor(white: 0.96, alpha: 1))
    static let inkSoft = adaptive(light: NSColor(white: 0.44, alpha: 1), dark: NSColor(white: 0.70, alpha: 1))
    /// Accent icons: ink fading to a softer gray.
    static let gradient = LinearGradient(colors: [ink, inkSoft], startPoint: .top, endPoint: .bottom)
    /// The selected row or chip, like Spotlight's: a gray wash under text that stays the label color.
    static let highlight = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.15))
    /// Quiet fills: fields, chips that aren't on, keycaps.
    static let fill = adaptive(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.08))
    /// The soft light behind onboarding's steps.
    static let wash = LinearGradient(colors: [inkSoft, ink], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// The app's search mark, a magnifier with a rounded-square lens: the app icon's and the menu bar's shape, where a
/// search field would show the round SF Symbol. It takes the foreground style, like a symbol.
struct LensGlyph: View {
    var size: CGFloat = 20
    /// The stroke, in units of the mark's 64-point grid (5: regular, like the menu bar; lower is lighter).
    var weight: CGFloat = 5.5

    var body: some View {
        SquareLens()
            .stroke(style: StrokeStyle(lineWidth: weight * size / 64, lineCap: .round, lineJoin: .round))
            .overlay(SquareLens.Handle()
                .stroke(style: StrokeStyle(lineWidth: weight * 1.4 * size / 64, lineCap: .round)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The lens of `LensGlyph` (`Resources/AppIcon/menubar.svg`): a rounded square in the top left of a 64-point grid.
nonisolated struct SquareLens: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 64
        return Path(roundedRect: CGRect(x: 8 * unit, y: 8 * unit, width: 36 * unit, height: 36 * unit),
                    cornerRadius: 10 * unit, style: .continuous)
    }

    /// The handle, out of the lens's bottom-right corner.
    nonisolated struct Handle: Shape {
        func path(in rect: CGRect) -> Path {
            let unit = rect.width / 64
            var path = Path()
            path.move(to: CGPoint(x: 42 * unit, y: 42 * unit))
            path.addLine(to: CGPoint(x: 57 * unit, y: 57 * unit))
            return path
        }
    }
}

/// A chip's background: Liquid Glass when it's on, a quiet gray when it isn't.
struct ChipBackground: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.glass(in: Capsule(), interactive: true)
        } else {
            content.background(Capsule().fill(Brand.fill))
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later (`interactive`: it reacts to the pointer, for controls); the closest
    /// material before that.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Buttons in Liquid Glass on macOS 26 and later, bordered before that. (Not `.glassProminent`: it draws white
    /// text on the tint, which a light gray can't carry in Dark Mode.)
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}

/// ⇧ ⌘ Space as keycaps.
struct Keycaps: View {
    let caps: [String]
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: size, weight: .medium, design: .rounded))
                    .frame(minWidth: size * 1.6)
                    .padding(.horizontal, size * 0.45)
                    .padding(.vertical, size * 0.28)
                    .background(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined(separator: " "))
    }
}

/// "p. 3" or "0:06" on a result: the page or moment that matched.
struct PlaceBadge: View {
    let text: String
    var onImage = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(onImage ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(onImage ? AnyShapeStyle(.black.opacity(0.6)) : AnyShapeStyle(.quaternary)))
    }
}

/// Where a moment sits in a recording: a track with the matched stretch lit.
struct MomentBar: View {
    let start: Double
    let end: Double
    let duration: Double
    /// Drawn over a picture: white on a dark track.
    var onImage = false
    /// Where playback is, while it plays.
    var playhead: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let from = max(0, min(1, start / duration)), to = max(from, min(1, end / duration))
            ZStack(alignment: .leading) {
                Capsule().fill(onImage ? Color.white.opacity(0.3) : Color.primary.opacity(0.12))
                Capsule()
                    .fill(onImage ? Color.white : Brand.ink)
                    .frame(width: max(4, width * (to - from)))
                    .offset(x: width * from)
                if let playhead {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 9, height: 9)
                        .offset(x: width * max(0, min(1, playhead / duration)) - 4.5)
                }
            }
        }
        .frame(height: 4)
        .accessibilityLabel("At \(ResultRow.clock(start)) of \(ResultRow.clock(duration))")
    }
}

/// What a folder holds, compactly: 📷 136  🖼 104  📄 25 … (the full wording in the tooltip).
struct KindCounts: View {
    let counts: [FileKind: Int]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(FileKind.allCases.filter { (counts[$0] ?? 0) > 0 }, id: \.self) { kind in
                Label(counts[kind]!.formatted(), systemImage: kind.symbol)
                    .labelStyle(CompactLabel())
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(.secondary)
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }

    /// "136 screenshots, 104 images, 25 PDFs"
    var description: String {
        FileKind.allCases.compactMap { kind in
            counts[kind].flatMap { $0 > 0 ? kind.counted($0) : nil }
        }.joined(separator: ", ")
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10))
            configuration.title
        }
    }
}

extension FileKind {
    /// "1 screenshot", "25 PDFs", "6 audio files"
    func counted(_ count: Int) -> String {
        let one = count == 1
        let noun = switch self {
        case .screenshot: one ? "screenshot" : "screenshots"
        case .image: one ? "image" : "images"
        case .pdf: one ? "PDF" : "PDFs"
        case .doc: one ? "document" : "documents"
        case .audio: one ? "audio file" : "audio files"
        case .video: one ? "video" : "videos"
        case .code: one ? "code file" : "code files"
        }
        return "\(count.formatted()) \(noun)"
    }
}

/// System Settings → Privacy & Security → Files and Folders, where a folder denied in macOS's prompt can be allowed.
func openFolderPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
        NSWorkspace.shared.open(url)
    }
}

/// Matched words, which FTS marks with « », in bold.
func highlighted(_ text: String, size: CGFloat) -> AttributedString {
    var result = AttributedString()
    var bold = false
    var piece = ""
    func flush() {
        guard !piece.isEmpty else { return }
        var run = AttributedString(piece)
        if bold {
            run.font = .system(size: size, weight: .bold)
            run.foregroundColor = .primary
        }
        result += run
        piece = ""
    }
    for character in text {
        switch character {
        case "«": flush(); bold = true
        case "»": flush(); bold = false
        default: piece.append(character)
        }
    }
    flush()
    return result
}

/// Click, then press the new shortcut; Esc cancels. While it listens, the global hotkey steps aside (`listening`) so
/// that pressing the current one lands here instead of opening the panel.
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    /// Tries a combination: nil when it's set, else why it can't be used.
    let apply: (KeyCombo) -> String?
    let listening: (Bool) -> Void
    var capSize: CGFloat = 15
    @State private var recording = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 6) {
            Button { setRecording(!recording) } label: {
                Group {
                    if recording {
                        Text("Press the new shortcut…").foregroundStyle(.secondary)
                    } else if let combo {
                        Keycaps(caps: combo.caps, size: capSize)
                    } else {
                        Text("Click to set a shortcut").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .frame(minWidth: 190, minHeight: capSize * 2.4)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(recording ? 0.03 : 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(recording ? Brand.accent : Color.primary.opacity(0.15),
                                  lineWidth: recording ? 2 : 1))
            }
            .buttonStyle(.plain)
            .background(KeyCatcher(active: recording, onKey: handle, onResign: { setRecording(false) }))
            .accessibilityLabel(recording ? "Recording a new shortcut" : "Shortcut \(combo?.display ?? "none"), click to change")
            Text(problem ?? (recording ? "Esc cancels" : "Click to change"))
                .font(.system(size: 11))
                .foregroundStyle(problem == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.red))
                .multilineTextAlignment(.center)
        }
        .onDisappear { if recording { listening(false) } }
    }

    private func setRecording(_ on: Bool) {
        guard on != recording else { return }
        recording = on
        if !on { problem = nil }
        listening(on)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function,
                                                                                               .numericPad])
        if event.keyCode == 53, flags.isEmpty { return setRecording(false) }   // Esc
        guard let combo = KeyCombo(keyCode: event.keyCode, flags: flags) else {
            problem = "Use ⌘, ⌥ or ⌃ with a key"
            return
        }
        if let why = apply(combo) {
            problem = why
        } else {
            setRecording(false)
        }
    }
}

/// Takes key presses (⌘-combinations too, before any menu sees them) while `active`. `onResign`: the window or the
/// view lost the keyboard, so listening must stop (the global hotkey is off meanwhile).
private struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onKey: (NSEvent) -> Void
    let onResign: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView { KeyCatcherView() }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.onResign = onResign
        guard view.active != active else { return }
        view.active = active
        DispatchQueue.main.async {
            if active {
                view.window?.makeFirstResponder(view)
            } else if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
        }
    }
}

private final class KeyCatcherView: NSView {
    var active = false
    var onKey: (NSEvent) -> Void = { _ in }
    var onResign: () -> Void = {}
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { active }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.active else { return }
                self.onResign()
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        if active { DispatchQueue.main.async { [weak self] in self?.onResign() } }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if active { onKey(event) } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard active, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        onKey(event)
        return true
    }
}
