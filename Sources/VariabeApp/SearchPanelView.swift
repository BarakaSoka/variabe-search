import AppKit
import VariabeKit
import SwiftUI

struct SearchPanelView: View {
    @Bindable var controller: SearchPanelController

    var body: some View {
        VStack(spacing: 0) {
            header
            if controller.phase != .empty {
                if controller.scopes.count > 1 { ScopeChips(controller: controller) }
                Divider().opacity(0.5)
                content
                    .frame(maxHeight: .infinity)
                Divider().opacity(0.5)
                footer
            }
        }
        .frame(width: SearchPanelController.width)
        .frame(maxHeight: .infinity, alignment: .top)
        // A light frost over the glass: Liquid Glass alone is too see-through over busy backgrounds.
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: controller.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: controller.cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .tint(Brand.accent)
    }

    private var header: some View {
        HStack(spacing: 12) {
            // A search of code shows it: the field's magnifier becomes code's mark.
            Group {
                if controller.isCode {
                    Image(systemName: FileKind.code.symbol).font(.system(size: 18, weight: .semibold))
                } else {
                    LensGlyph(size: 24)
                }
            }
            .foregroundStyle(Brand.gradient)
            .frame(width: 26)
            .help(controller.isCode ? "Searching your code" : "")
            SearchField(text: $controller.query, fontSize: 24, placeholder: "Search what you remember in your files") {
                controller.field = $0
            }
            if controller.phase == .words, controller.encoder == .starting {
                ProgressView().controlSize(.small)
            }
            if let activity = controller.model.activityBadge {
                Text(activity)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    .help(controller.model.statusLine)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: SearchPanelController.fieldHeight)
    }

    @ViewBuilder private var content: some View {
        if controller.phase == .codeHint || controller.phase == .codeOff {
            CodeHint(controller: controller)
        } else if controller.results.isEmpty {
            VStack(spacing: 8) {
                if controller.phase == .words {
                    Text("Searching…").foregroundStyle(.secondary)
                } else if !controller.model.hasFolders {
                    Text("No folders chosen yet").font(.system(size: 15, weight: .semibold))
                    Text("Variabe Search only searches the folders you pick.").foregroundStyle(.secondary)
                    Button("Choose Folders…") { controller.chooseFolders() }
                        .padding(.top, 4)
                } else if controller.isCode {
                    Text("No matches in your code").font(.system(size: 15, weight: .semibold))
                } else {
                    LensGlyph(size: 36, weight: 3.5)
                        .foregroundStyle(Brand.gradient)
                        .padding(.bottom, 4)
                    Text("No matches").font(.system(size: 15, weight: .semibold))
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                ResultList(controller: controller)
                    .frame(width: SearchPanelController.listWidth)
                Divider().opacity(0.5)
                Group {
                    if let row = controller.selectedRow {
                        VStack(alignment: .leading, spacing: 12) {
                            PreviewPane(row: row, imageSize: CGSize(width: 400, height: 230),
                                        open: { controller.openSelected() })
                            PreviewActions(row: row, open: { controller.openSelected() },
                                           reveal: { controller.revealSelected() }, controlSize: .small)
                        }
                    } else if controller.selection == SearchPanelController.weakerToggle {
                        WeakerExplainer(count: controller.weaker.count, expanded: controller.showWeaker)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ForEach(controller.selectedRow == nil ? [] : keyHints, id: \.label) { hint in
                KeyHint(key: hint.key, label: hint.label)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    /// The keys, saying where ↩ and Space go for a page or moment: "↩ Open at 0:06", "␣ Quick Look at 0:06", and for
    /// code, at which line: "↩ Open in Zed at line 12".
    private var keyHints: [(key: String, label: String)] {
        let row = controller.selectedRow
        if let row, row.kind == .code {
            let line = row.segment == .lines ? " at line \(row.codeLine)" : ""
            return [("↩", "\(row.openTitle)\(line)"), ("⌘↩", "Reveal"), ("␣", "Quick Look"), ("⌘C", "Copy")]
        }
        let place = row?.jump.map { " at \($0)" } ?? ""
        return [("↩", row?.openTitle ?? "Open"), ("⌘↩", "Reveal"), ("␣", "Quick Look\(place)"), ("⌘C", "Copy")]
    }

    private var statusText: String {
        if let note = controller.note { return note }
        switch controller.phase {
        case .words:
            return controller.encoder == .starting ? "Matching words; meaning search is warming up…" : "Matching words…"
        case .wordsOnly:
            return controller.model.meaningUnavailable ?? "Words only: meaning search isn't available"
        case .codeHint, .codeOff:
            return controller.phase == .codeOff ? "Code search is off" : "Searching your code"
        case .meaning, .empty:
            if controller.isCode, let indexing = controller.model.status.code.indexing, indexing.total > 0 {
                return "Still reading code (\(Int(Double(indexing.done) / Double(indexing.total) * 100))%): some isn't in yet"
            }
            if !controller.isCode, let caveat = controller.model.resultsCaveat { return caveat }
            let count = controller.groups.reduce(0) { $0 + $1.rows.count }
            let weaker = controller.weaker.count
            return (count == 1 ? "1 result" : "\(count) results") + (controller.isCode ? " in your code" : "")
                + (weaker > 0 ? " · \(weaker) weaker" : "")
        }
    }
}

private struct ResultList: View {
    let controller: SearchPanelController

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(controller.groups) { group in
                        GroupHeader(title: group.kind.title, symbol: group.kind.symbol)
                        ForEach(group.rows) { row in
                            PanelRow(row: row, selected: row.id == controller.selection)
                                .id(row.id)
                                .overlay(FileDragArea(url: row.url, openTitle: row.openTitle,
                                                      onClick: { controller.select(row) },
                                                      onOpen: {
                                                          controller.select(row)
                                                          controller.openSelected()
                                                      }))
                        }
                        if group.total > group.rows.count {
                            Button {
                                controller.openInWindow(group.kind)
                            } label: {
                                Text("Show all \(group.total) \(group.kind.title.lowercased())…")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Brand.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                            .help("Open them in the Variabe Search window (⌘O shows everything)")
                        }
                    }
                    if !controller.weaker.isEmpty {
                        WeakerRow(count: controller.weaker.count, expanded: controller.showWeaker,
                                  selected: controller.selection == SearchPanelController.weakerToggle)
                            .id(SearchPanelController.weakerToggle)
                            .onTapGesture { controller.toggleWeaker() }
                            .padding(.top, 6)
                        if controller.showWeaker {
                            ForEach(controller.weaker) { row in
                                PanelRow(row: row, selected: row.id == controller.selection)
                                    .id(row.id)
                                    .opacity(0.85)
                                    .overlay(FileDragArea(url: row.url, openTitle: row.openTitle,
                                                          onClick: { controller.select(row) },
                                                          onOpen: {
                                                              controller.select(row)
                                                              controller.openSelected()
                                                          }))
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: controller.selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}

struct GroupHeader: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Brand.gradient)
            }
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A result in the panel's list: thumbnail, name with the page or moment, and the matched words (or the folder).
private struct PanelRow: View {
    let row: ResultRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            // Code's thumbnail would be a page of tiny text: its file type's icon says more.
            ThumbnailView(url: row.url, side: 38, iconOnly: row.kind == .code)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let place = row.place { PlaceBadge(text: place) }
                }
                Group {
                    if let excerpt = row.excerpt, row.matchedWords, row.kind != .code {
                        Text(highlighted(excerpt, size: 11.5))
                            .lineLimit(1)
                    } else {
                        Text(row.folder)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? Brand.highlight : Color.clear))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.kind.title), \(row.name), \(row.reason)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "▸ 14 weaker matches", selectable with the arrows like a result; ↩ or a click unfolds them.
private struct WeakerRow: View {
    let count: Int
    let expanded: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .bold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
            Text(expanded ? "Weaker matches" : "\(count) weaker \(count == 1 ? "match" : "matches")")
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .foregroundStyle(.secondary)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? Brand.highlight : Color.clear))
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
    }
}

private struct WeakerExplainer: View {
    let count: Int
    let expanded: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(expanded ? "Weaker matches" : "\(count) weaker \(count == 1 ? "match" : "matches")")
                .font(.system(size: 14, weight: .semibold))
            Text("They match much less well than the results above. Press Return to "
                 + (expanded ? "fold them away." : "show them."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ThumbnailView: View {
    static let side: CGFloat = 36
    let url: URL
    var side: CGFloat = ThumbnailView.side
    /// The file type's icon, not a picture of the file.
    var iconOnly = false
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side > 60 ? 8 : 6, style: .continuous))
        .task(id: url) {
            guard !iconOnly else { return }
            image = Thumbnails.shared.cached(url, side: side)
            if image == nil {
                image = await Thumbnails.shared.load(url, side: side, scale: scale)
            }
        }
    }
}

/// The search field. AppKit, so the panel and the window can focus it and see its text selection (for ⌘C) directly;
/// the arrows, ↩ and Esc never reach it, because their key monitors take those first.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 22
    let placeholder: String
    var onMake: (NSTextField) -> Void = { _ in }
    /// The field got the cursor (true) or lost it (false).
    var onFocus: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingField()
        field.onFocus = onFocus
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search")
        onMake(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        (field as? FocusReportingField)?.onFocus = onFocus
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        // The window's field grows while it sits in the middle and shrinks at the top.
        if field.font?.pointSize != fontSize { field.font = .systemFont(ofSize: fontSize) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// A text field that says when it gets the cursor and when it gives it up (its editing ends).
final class FocusReportingField: NSTextField {
    var onFocus: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus(true) }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocus(false)
    }
}

/// Click to select, double-click to open, drag to copy the file into Finder, Mail, a chat… (an AppKit dragging
/// source, `FileDragView`).
struct FileDragArea: NSViewRepresentable {
    let url: URL
    /// "Open at 0:06": what double-click and the menu's first item do.
    var openTitle = "Open"
    let onClick: () -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.url = url
        view.openTitle = openTitle
        view.onClick = onClick
        view.onOpen = onOpen
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var openTitle = "Open"
    var onClick: () -> Void = {}
    var onOpen: () -> Void = {}
    private var mouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            mouseDownEvent = nil
            onOpen()
        } else {
            mouseDownEvent = event
            onClick()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let url else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 9 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let point = convert(down.locationInWindow, from: nil)
        let side: CGFloat = 44
        let image = Thumbnails.shared.cached(url, side: ThumbnailView.side) ?? NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                              contents: image)
        beginDraggingSession(with: [item], event: down, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    /// Right-click: select it, and offer what you'd do with a file.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url else { return nil }
        onClick()
        let menu = NSMenu()
        menu.addItem(ActionMenuItem(openTitle) { [onOpen] in onOpen() })
        menu.addItem(ActionMenuItem("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([url as NSURL])
        })
        menu.addItem(ActionMenuItem("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        })
        return menu
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Copy, never move: dropping a result into a Finder folder must not take it away from where it lives.
        context == .outsideApplication ? [.copy, .generic] : []
    }
}

/// "code:" typed: what to type after it, or (without code folders) how to turn code search on.
private struct CodeHint: View {
    let controller: SearchPanelController

    static let examples = ["code: retry a request with backoff", "code: where the settings are saved",
                           "code: parse the command line options"]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: FileKind.code.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Brand.gradient)
            if controller.phase == .codeOff {
                Text("Code search is off").font(.system(size: 15, weight: .semibold))
                Text("Variabe Search can find code by what it does, in the folders you pick. Code gets an index of its own "
                     + "and never shows up in other searches.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Choose Code Folders…") { controller.setUpCodeSearch() }
                    .padding(.top, 4)
            } else {
                Text("Search your code").font(.system(size: 15, weight: .semibold))
                Text("Say what the code does, or type a name that's in it.").foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { controller.tryExample(example) } label: {
                            Text(example)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Brand.fill))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Spotlight-style chips under the field: All, then each kind this search found (⌘1, ⌘2…). They narrow the list;
/// the search itself stays the same.
private struct ScopeChips: View {
    let controller: SearchPanelController

    var body: some View {
        HStack(spacing: 6) {
            chip("All", symbol: "square.grid.2x2", count: nil, on: controller.scope == nil) {
                controller.setScope(nil)
            }
            ForEach(controller.scopes, id: \.self) { kind in
                let count = (controller.results.groups.first { $0.kind == kind }?.total ?? 0)
                chip(kind.title, symbol: kind.symbol, count: count > 0 ? count : nil, on: controller.scope == kind) {
                    controller.setScope(kind)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func chip(_ title: String, symbol: String, count: Int?, on: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
                if let count {
                    Text("\(count)").font(.system(size: 11, weight: .medium).monospacedDigit()).opacity(0.7)
                }
            }
            .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .modifier(ChipBackground(on: on))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A key and what it does, for the footer: a small keycap, then the label.
private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .frame(minWidth: 20, minHeight: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Brand.fill))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            Text(label).lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}
