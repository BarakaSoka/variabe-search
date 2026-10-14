import AppKit
import VariabeKit
import Observation
import Quartz
import SwiftUI

/// The search window, for the searches the panel is too small for: a big field, kind filters with counts, the results
/// as a grid of pictures, and the selected one in a preview pane with why it matched. The Dock icon shows while it's
/// open, and closing it frees its views (the app goes back to its idle size).
final class SearchWindowController: NSObject, NSWindowDelegate {
    let search: SearchModel
    private unowned let app: AppController
    private var window: QuickLookWindow?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    /// The window is at its small size, for the field alone (nothing typed).
    private var compact = false

    /// Only the field and what's indexed: no room wasted around them.
    static let compactSize = NSSize(width: 720, height: 320)
    static let compactMinSize = NSSize(width: 600, height: 280)
    /// Results: the room a grid and a preview need, at least.
    static let resultsMinSize = NSSize(width: 820, height: 520)
    private static let resultsSizeKey = "searchWindowResultsSize"

    /// The size for results: as you last left it (resizing the window with results showing changes it).
    private var resultsSize: NSSize {
        get {
            UserDefaults.standard.string(forKey: Self.resultsSizeKey).map(NSSizeFromString)
                .flatMap { $0.width >= Self.resultsMinSize.width ? $0 : nil } ?? NSSize(width: 1040, height: 700)
        }
        set { UserDefaults.standard.set(NSStringFromSize(newValue), forKey: Self.resultsSizeKey) }
    }

    init(app: AppController) {
        self.app = app
        search = SearchModel(engine: app.engine)
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(query: String? = nil, kind: ResultGroupKind? = nil) {
        let window = self.window ?? makeWindow()
        if let query {
            search.filter = kind
            search.query = query
        }
        fit(compact: wantsCompact, animate: false)
        app.present(window)
        if !AppController.offscreen { window.makeFirstResponder(search.field) }
        installKeyMonitor()
    }

    func close() {
        window?.close()
    }

    /// Nothing typed (with folders chosen): the window's small size, the field in the middle of it.
    var wantsCompact: Bool {
        app.model.hasFolders && search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Small for the field alone, big for results (`resultsSize`): grows and shrinks around its top edge, keeping its
    /// center, so the field stays near where it was. The results size is remembered on the way back to small.
    func fit(compact: Bool, animate: Bool = true) {
        guard let window, compact != self.compact else { return }
        if !self.compact { resultsSize = window.frame.size }
        self.compact = compact
        window.minSize = compact ? Self.compactMinSize : Self.resultsMinSize
        let size = compact ? Self.compactSize : resultsSize
        var frame = NSRect(x: window.frame.midX - size.width / 2, y: window.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if let area = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.size.width = min(frame.width, area.width)
            frame.size.height = min(frame.height, area.height)
            frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
            frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        }
        guard animate, !AppController.offscreen else {
            window.setFrame(frame, display: true)
            return
        }
        // Through the animator: setFrame(_:display:animate:) would hold the main thread, and the keys being typed.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func makeWindow() -> QuickLookWindow {
        let window = QuickLookWindow(contentRect: NSRect(origin: .zero, size: Self.compactSize),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                     backing: .buffered, defer: false)
        // An empty unified toolbar makes the title bar tall enough for the search field to sit beside the window
        // buttons.
        window.toolbar = NSToolbar(identifier: "VariabeSearch")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Variabe Search"
        window.minSize = Self.compactMinSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SearchWindowView(search: search, model: app.model, app: app).tint(Brand.accent))
        // Small, centered, a little above the middle of the screen; `show` grows it if there's a query.
        window.center()
        compact = true
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        }
        removeKeyMonitor()
        PreviewPlayback.shared.stop()
        if let window, !compact { resultsSize = window.frame.size }
        window?.contentView = nil
        window = nil
        app.windowClosed()
    }

    func snapshot(to url: URL) throws {
        try Snapshot.write(window, to: url)
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window else { return event }
            // Keys typed here, or in Quick Look while this window is the one showing it (not the panel's).
            let previewing = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
                && event.window === QLPreviewPanel.shared() && QLPreviewPanel.shared().dataSource === window
            guard event.window === window || previewing else { return event }
            return handle(event) ? nil : event
        }
        // A click back in the search field: Space and ← → type again (after a click on a result, they were its).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window, event.window === window, let field = search.field else { return event }
            if field.bounds.contains(field.convert(event.locationInWindow, from: nil)) { search.editing() }
            return event
        }
    }

    private func removeKeyMonitor() {
        for monitor in [keyMonitor, mouseMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    /// Arrows move through the grid (← → only once you've arrowed, so they still move the cursor while you type),
    /// ↩ opens, ⌘↩ reveals, Space previews, ⌘C copies, Esc closes the preview or clears the search.
    private func handle(_ event: NSEvent) -> Bool {
        // An input method is composing (Japanese, Chinese…): ↩, the arrows and Esc are its keys until it's done.
        if (search.field?.currentEditor() as? NSTextView)?.hasMarkedText() == true { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let previewing = QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
        switch event.keyCode {
        case 125, 126:   // ↓ ↑
            guard modifiers.isEmpty else { return false }
            search.move(by: event.keyCode == 125 ? search.columns : -search.columns)
        case 123, 124:   // ← →
            guard modifiers.isEmpty, search.navigated || previewing else { return false }
            search.move(by: event.keyCode == 124 ? 1 : -1)
        case 36, 76:   // ↩
            guard let row = search.selectedRow else { return false }
            if modifiers == .command {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            } else if modifiers.isEmpty {
                search.open(row)
            } else {
                return false
            }
        case 49 where modifiers.isEmpty && (search.navigated || previewing) && search.selectedRow != nil:   // Space
            toggleQuickLook()
        case 16 where modifiers == .command:   // ⌘Y
            toggleQuickLook()
        case 18...23 where modifiers == .command:   // ⌘1 all, ⌘2…⌘6 one kind
            let kinds: [ResultGroupKind?] = [nil] + ResultGroupKind.files
            let index = [18, 19, 20, 21, 23, 22].firstIndex(of: Int(event.keyCode)) ?? 0   // key codes of 1…6
            search.filter = kinds[index]
        case 26 where modifiers == .command && app.model.hasCode:   // ⌘7: code
            search.filter = .code
        case 8 where modifiers == .command && search.navigated:   // ⌘C
            guard let row = search.selectedRow else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([row.url as NSURL])
        case 53:   // Esc
            if previewing {
                QLPreviewPanel.shared().orderOut(nil)
            } else if !search.query.isEmpty {
                search.query = ""
            } else {
                return false
            }
        default:
            return false
        }
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { updateQuickLook() }
        return true
    }

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
        } else if search.selectedRow != nil {
            updateQuickLook()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Quick Look shows the selected result at its page or moment.
    private func updateQuickLook() {
        window?.previewURL = search.selectedRow?.url
        QLPreviewPanel.shared().reloadData()
        QuickLookMoment.show(search.selectedRow, in: QLPreviewPanel.shared())
    }
}

/// A window that hands Quick Look the selected file (Space / ⌘Y).
final class QuickLookWindow: NSWindow, QLPreviewPanelDataSource {
    var previewURL: URL?

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = self }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { panel.dataSource = nil }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
}

/// The window's query: keyword and meaning results together after a short pause in typing, optionally of one kind.
@Observable
final class SearchModel {
    var query = "" {
        didSet { if query != oldValue { run() } }
    }
    var filter: ResultGroupKind? {
        didSet { if filter != oldValue { run() } }
    }
    private(set) var results = ResultSet.empty
    /// Results per kind for the query, whatever the filter (the counts on the kind buttons).
    private(set) var counts: [ResultGroupKind: Int] = [:]
    private(set) var hasResults = false
    /// What the window shows instead of results: "code:" alone (what to type), or code search that's off.
    private(set) var codePhase: SearchPhase?
    var selection: String?
    var showWeaker = false
    var showsPreview = true
    /// You moved the selection with the arrow keys since the last edit: Space and ← → act on results then.
    private(set) var navigated = false
    /// The grid's columns right now (↑ ↓ move by a row).
    var columns = 4
    @ObservationIgnored weak var field: NSTextField?
    @ObservationIgnored private let engine: Engine
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(engine: Engine) {
        self.engine = engine
    }

    /// Every result shown, in order (strong ones, then the weaker ones once they're unfolded).
    var rows: [ResultRow] { results.ranked + (showWeaker ? results.weaker : []) }

    /// A search of code: the Code filter, or "code:" typed.
    var isCode: Bool { filter == .code || CodeQuery.text(of: query) != nil }
    var selectedRow: ResultRow? { rows.first { $0.id == selection } ?? rows.first }

    /// A click on a result: like the arrow keys, it makes Space and ← → act on the results.
    func select(_ row: ResultRow) {
        selection = row.id
        navigated = true
    }

    /// A click in the search field: keys are the text's again.
    func editing() {
        navigated = false
    }

    /// Puts the cursor in the search field (a click on the empty window lands there).
    func focusField() {
        guard let field, field.currentEditor() == nil else { return }
        field.window?.makeFirstResponder(field)
    }

    /// The file in its app, at the page or moment that matched when the app can be told where.
    func open(_ row: ResultRow) {
        engine.open(row)
    }

    func move(by step: Int) {
        let ids = rows.map(\.id)
        guard !ids.isEmpty else { return }
        let index = selection.flatMap { ids.firstIndex(of: $0) } ?? -1
        selection = ids[max(0, min(ids.count - 1, index + step))]
        navigated = true
    }

    private func run() {
        generation += 1
        let current = generation
        task?.cancel()
        navigated = false
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = isCode
        let text = CodeQuery.text(of: typed) ?? typed
        codePhase = nil
        guard !typed.isEmpty else {
            results = .empty
            counts = [:]
            hasResults = false
            return
        }
        if code, !engine.hasCode || text.isEmpty {
            results = .empty
            counts = [:]
            hasResults = false
            codePhase = engine.hasCode ? .codeHint : .codeOff
            return
        }
        engine.prewarm()
        engine.embedAhead(text, code: code)
        let filter = self.filter
        let showAt = ContinuousClock.now + SearchPanelController.typingPause
        if code {
            task = Task {
                let vector = await engine.embedQuery(text, code: true)
                guard !Task.isCancelled, current == generation else { return }
                let hits = await engine.search(text, vector: vector, prefixLast: false, limit: 120, code: true)
                try? await Task.sleep(until: showAt, tolerance: .milliseconds(1), clock: .continuous)
                guard !Task.isCancelled, current == generation else { return }
                counts = [.code: Searcher.strongCount(hits)]
                results = ResultSet(hits, query: text)
                showWeaker = false
                if !rows.contains(where: { $0.id == selection }) { selection = rows.first?.id }
                hasResults = true
                log("window: code \"\(text)\": \(results.ranked.count) results + \(results.weaker.count) weaker")
            }
            return
        }
        task = Task {
            let vector = await engine.embedQuery(text)
            guard !Task.isCancelled, current == generation else { return }
            let all = await engine.search(text, vector: vector, prefixLast: false, limit: 120)
            let shown = filter == nil ? all : await engine.search(text, vector: vector, prefixLast: false,
                                                                    kinds: filter!.kinds, limit: 120)
            try? await Task.sleep(until: showAt, tolerance: .milliseconds(1), clock: .continuous)
            guard !Task.isCancelled, current == generation else { return }
            var counts: [ResultGroupKind: Int] = [:]
            for hit in all.prefix(Searcher.strongCount(all)) { counts[ResultGroupKind(hit.kind), default: 0] += 1 }
            self.counts = counts
            results = ResultSet(shown, query: text)
            showWeaker = false
            if !rows.contains(where: { $0.id == selection }) { selection = rows.first?.id }
            hasResults = true
            log("window: \"\(text)\"\(filter.map { " in \($0.title)" } ?? ""): \(results.ranked.count) results "
                + "+ \(results.weaker.count) weaker")
        }
    }
}

// MARK: Views

struct SearchWindowView: View {
    @Bindable var search: SearchModel
    let model: AppModel
    let app: AppController
    @State private var fieldFocused = false

    var body: some View {
        VStack(spacing: 0) {
            // Nothing typed: the field sits in the middle with what's indexed under it, and moves to the top once you
            // type. It's the same field throughout (only the space around it changes), so typing never loses the cursor.
            if isHome { Spacer(minLength: 0) }
            header
            if isHome {
                HomeInfo(search: search, model: model, engine: app.engine)
                Spacer(minLength: 0)
                Spacer(minLength: 0)   // a little above the middle, as the eye expects
            } else {
                Divider()
                HStack(spacing: 0) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if search.showsPreview, let row = search.selectedRow, search.hasResults {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                PreviewPane(row: row, imageSize: CGSize(width: 292, height: 230),
                                            open: { search.open(row) })
                                PreviewActions(row: row, open: { search.open(row) },
                                               reveal: { NSWorkspace.shared.activateFileViewerSelecting([row.url]) })
                            }
                            .padding(16)
                        }
                        .frame(width: 324)
                        .background(Color.primary.opacity(0.025))
                    }
                }
            }
            Divider()
            statusBar
        }
        .overlay(alignment: .topTrailing) {
            if isHome { settingsButton.padding(.top, 16).padding(.trailing, 16) }
        }
        .animation(.smooth(duration: 0.3), value: isHome)
        .onChange(of: isHome) { _, home in app.searchWindow.fit(compact: home) }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: SearchWindowController.compactMinSize.width,
               minHeight: SearchWindowController.compactMinSize.height - 28)
    }

    /// Folders chosen and nothing typed: the field in the middle, nothing else but what's indexed.
    private var isHome: Bool {
        model.hasFolders && search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var settingsButton: some View {
        Button {
            app.showSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Settings (⌘,)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Group {
                        if search.isCode {
                            Image(systemName: FileKind.code.symbol).font(.system(size: 15, weight: .semibold))
                        } else {
                            LensGlyph(size: isHome ? 22 : 19)
                        }
                    }
                    .foregroundStyle(Brand.gradient)
                    .frame(width: 22)
                    SearchField(text: $search.query, fontSize: isHome ? 21 : 18, placeholder: placeholder,
                                onMake: { search.field = $0 }, onFocus: { fieldFocused = $0 })
                    if !search.query.isEmpty {
                        Button {
                            search.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear")
                    }
                }
                .padding(.horizontal, isHome ? 20 : 14)
                .frame(height: isHome ? 52 : 38)
                .frame(maxWidth: isHome ? 600 : .infinity)
                .glass(in: Capsule())
                // Where typing goes, as a Mac text field shows it: a ring while it has the cursor.
                .overlay(Capsule().strokeBorder(Brand.accent.opacity(fieldFocused ? 0.45 : 0), lineWidth: 1.5))
                .animation(.easeOut(duration: 0.15), value: fieldFocused)
                if !isHome {
                    Button {
                        search.showsPreview.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 15))
                            .foregroundStyle(search.showsPreview ? AnyShapeStyle(Brand.ink) : AnyShapeStyle(.secondary))
                    }
                    .buttonStyle(.plain)
                    .help(search.showsPreview ? "Hide Preview" : "Show Preview")
                    settingsButton
                }
            }
            .padding(.leading, isHome ? 0 : 78)   // beside the window buttons, once it's at the top
            .frame(maxWidth: .infinity)
            .frame(height: isHome ? 64 : 52)
            if !isHome { KindFilters(search: search, showsCode: model.hasCode) }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, isHome ? 0 : 10)
    }

    @ViewBuilder private var content: some View {
        if !model.hasFolders {
            VStack(spacing: 0) {
                Text("Choose folders to search").font(.system(size: 20, weight: .bold))
                Text("Variabe Search only looks where you tell it to.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Button("Choose Folders…") { app.chooseFolders() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 18)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let phase = search.codePhase {
            CodeOffOrHint(phase: phase, search: search) { app.chooseCodeFolders() }
        } else if !search.hasResults {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if search.results.isEmpty {
            EmptyState(symbol: search.isCode ? FileKind.code.symbol : nil,
                       title: "No matches for “\(search.query.trimmingCharacters(in: .whitespaces))”")
        } else if search.isCode {
            CodeResultsList(search: search)
        } else {
            ResultsGrid(search: search)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let progress = model.progress {
                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.mini)
            }
            // What's indexed: a click shows the folders and their progress.
            Button(model.statusLine) { app.showSettings(.folders) }
                .buttonStyle(.plain)
                .lineLimit(1)
                .help("Folders and indexing")
            Spacer()
            if search.hasResults, !search.query.isEmpty {
                Text(model.resultsCaveat ?? resultCount).lineLimit(1)
            }
            if let version = model.updateAvailable {
                Button {
                    app.updates.checkNow()
                } label: {
                    Label("Variabe Search \(version) is available", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Brand.ink)
                }
                .buttonStyle(.plain)
                .help("See what's new and update")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 28)
    }

    private var placeholder: String {
        search.filter == .code ? "Search what you remember in your code" : "Search what you remember in your files"
    }

    private var resultCount: String {
        let count = search.results.ranked.count
        return (count == 1 ? "1 result" : "\(count) results")
            + (search.results.weaker.isEmpty ? "" : " · \(search.results.weaker.count) weaker")
    }
}

/// All · Screenshots 4 · Images 9 · …: what the query found of each kind; click to see only that kind. With code search
/// on, Code after them: a search of code alone (as "code:" is).
private struct KindFilters: View {
    @Bindable var search: SearchModel
    var showsCode = false

    var body: some View {
        HStack(spacing: 6) {
            chip(title: "All", symbol: nil, count: nil, selected: search.filter == nil && !search.isCode) {
                search.filter = nil
            }
            ForEach(ResultGroupKind.files, id: \.self) { kind in
                chip(title: kind.title, symbol: kind.symbol, count: search.isCode ? nil : search.counts[kind],
                     selected: search.filter == kind && !search.isCode) {
                    search.filter = search.filter == kind ? nil : kind
                }
            }
            if showsCode {
                Divider().frame(height: 16).padding(.horizontal, 4)
                chip(title: "Code", symbol: FileKind.code.symbol, count: search.isCode ? search.counts[.code] : nil,
                     selected: search.isCode, shortcut: 7) {
                    search.filter = search.filter == .code ? nil : .code
                }
            }
        }
    }

    private func chip(title: String, symbol: String?, count: Int?, selected: Bool, shortcut: Int? = nil,
                      action: @escaping () -> Void) -> some View {
        let number = shortcut ?? (ResultGroupKind.files.firstIndex { $0.title == title }).map { $0 + 2 } ?? 1
        return Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10.5)) }
                Text(title)
                if let count, !search.query.isEmpty {
                    Text("\(count)").monospacedDigit().opacity(0.6)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .modifier(ChipBackground(on: selected))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(title) (⌘\(number))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ResultsGrid: View {
    @Bindable var search: SearchModel
    private static let cell = CGSize(width: 176, height: 132)

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell.width, maximum: 230), spacing: 14)],
                              alignment: .leading, spacing: 18) {
                        ForEach(search.results.ranked) { row in cell(row) }
                    }
                    .padding(16)
                    if !search.results.weaker.isEmpty {
                        WeakerToggle(count: search.results.weaker.count, expanded: search.showWeaker) {
                            search.showWeaker.toggle()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        if search.showWeaker {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell.width, maximum: 230),
                                                         spacing: 14)], alignment: .leading, spacing: 18) {
                                ForEach(search.results.weaker) { row in cell(row).opacity(0.85) }
                            }
                            .padding(16)
                        }
                    }
                }
                .onChange(of: search.selection) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
                }
            }
            .onAppear { updateColumns(geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in updateColumns(width) }
        }
    }

    private func updateColumns(_ width: CGFloat) {
        search.columns = max(1, Int((width - 32 + 14) / (Self.cell.width + 14)))
    }

    private func cell(_ row: ResultRow) -> some View {
        GridCell(row: row, selected: row.id == search.selectedRow?.id)
            .id(row.id)
            .overlay(FileDragArea(url: row.url, openTitle: row.openTitle, onClick: { search.select(row) },
                                  onOpen: { search.open(row) }))
    }
}

private struct GridCell: View {
    let row: ResultRow
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A fixed box the picture fills and is clipped to: a picture's own shape must never size the cell.
            Color.primary.opacity(0.05)
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .overlay {
                    if row.kind == .audio {
                        Image(systemName: "waveform")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Brand.gradient)
                    } else {
                        MomentThumbnail(row: row)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topLeading) {
                if row.kind != .image && row.kind != .screenshot {
                    Image(systemName: row.kind.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let place = row.place { PlaceBadge(text: place, onImage: true).padding(6) }
            }
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Brand.ink.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 0.5)
                .padding(selected ? -3 : 0))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.folder)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.kind.title), \(row.name), \(row.reason)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Code results, one under another: the file, where in its repo, the lines that matched, and why.
private struct CodeResultsList: View {
    @Bindable var search: SearchModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(search.results.ranked) { row in item(row) }
                    if !search.results.weaker.isEmpty {
                        WeakerToggle(count: search.results.weaker.count, expanded: search.showWeaker) {
                            search.showWeaker.toggle()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if search.showWeaker {
                            ForEach(search.results.weaker) { row in item(row).opacity(0.85) }
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: search.selection) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
            }
            .onAppear { search.columns = 1 }
        }
    }

    private func item(_ row: ResultRow) -> some View {
        CodeResultRow(row: row, selected: row.id == search.selectedRow?.id)
            .id(row.id)
            .overlay(FileDragArea(url: row.url, openTitle: row.openTitle, onClick: { search.select(row) },
                                  onOpen: { search.open(row) }))
    }
}

private struct CodeResultRow: View {
    let row: ResultRow
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThumbnailView(url: row.url, side: 30, iconOnly: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let place = row.place { PlaceBadge(text: place) }
                    Text(row.folder)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if let excerpt = row.excerpt {
                    Text(highlighted(excerpt, size: 11))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Brand.highlight : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Code, \(row.name), \(row.reason)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "code:" typed without code search on (how to turn it on), or with nothing after it (what to type).
private struct CodeOffOrHint: View {
    let phase: SearchPhase
    let search: SearchModel
    let chooseFolders: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: FileKind.code.symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Brand.gradient)
            if phase == .codeOff {
                Text("Code search is off").font(.system(size: 17, weight: .semibold))
                Text("Variabe Search can find code by what it does, in the folders you pick. Code gets an index of its own and "
                     + "never shows up in other searches.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Choose Code Folders…", action: chooseFolders).padding(.top, 6)
            } else {
                Text("Search your code").font(.system(size: 17, weight: .semibold))
                Text("Say what the code does, or type a name that's in it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A grid cell's picture: the video frame or PDF page that matched (from the preview cache), else Quick Look's.
private struct MomentThumbnail: View {
    let row: ResultRow
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if let image {
                // A page shows its top (its title), anything else its middle.
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: row.page == nil ? .center : .top)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: row.url.path))
                    .resizable()
                    .frame(width: 56, height: 56)
            }
        }
        .task(id: row.previewKey) {
            let side: CGFloat = 230
            image = Previews.shared.cached(row, side: side)
            if image == nil { image = await Previews.shared.load(row, side: side, scale: scale) }
        }
    }
}

struct WeakerToggle: View {
    let count: Int
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(expanded ? "Weaker matches" : "\(count) weaker \(count == 1 ? "match" : "matches")")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// After a search: a big quiet symbol, what happened, what to try.
private struct EmptyState: View {
    /// An SF Symbol, or nil for the app's own search mark.
    let symbol: String?
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 40, weight: .light))
                } else {
                    LensGlyph(size: 46, weight: 3.5)
                }
            }
            .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Under the field while nothing's typed: what's in the index (each kind's count, and where) and the shortcut. A click
/// anywhere around it puts the cursor in the field.
private struct HomeInfo: View {
    let search: SearchModel
    let model: AppModel
    let engine: Engine
    @State private var kinds: [FileKind: Int] = [:]

    var body: some View {
        VStack(spacing: 10) {
            if !kinds.isEmpty {
                HStack(spacing: 8) {
                    KindCounts(counts: kinds)
                    Text("in \(folders)")
                }
            } else if model.status.searchable > 0 {
                Text("\(model.status.searchable.formatted()) files to search in \(folders)")
            }
            if let hotkey = model.hotkey {
                HStack(spacing: 6) {
                    Keycaps(caps: hotkey.caps, size: 10)
                    Text("opens Variabe Search from any app")
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.tertiary)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { search.focusField() }
        .task(id: model.status.files) {
            var counts: [FileKind: Int] = [:]
            for summary in await engine.rootSummaries() { counts.merge(summary.kinds, uniquingKeysWith: +) }
            kinds = counts
        }
    }

    private var folders: String {
        let names = model.settings.roots.map(\.lastPathComponent)
        return names.count <= 3 ? names.formatted(.list(type: .and)) : "\(names.count) folders"
    }
}
