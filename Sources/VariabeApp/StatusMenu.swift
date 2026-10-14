import AppKit
import SwiftUI

/// The menubar icon: the app icon's mark, a magnifier with a rounded-square lens (`Resources/AppIcon/menubar.svg`, drawn
/// here from the same geometry so it's sharp at any scale). While the model downloads or files index, the lens fills up
/// from the bottom as progress; while indexing is paused, two bars sit in the lens (at full strength: a dimmed icon
/// reads as "off", and search still works).
enum StatusIcon {
    /// `update`: a newer version is waiting, a dot at the mark's top right.
    static func image(progress: Double?, paused: Bool = false, update: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            // The SVG's 64-unit grid, y down.
            let grid = NSAffineTransform()
            grid.scale(by: rect.width / 64)
            grid.concat()
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let lens = NSRect(x: 8, y: 8, width: 36, height: 36)
            let ring = NSBezierPath(roundedRect: lens, xRadius: 10, yRadius: 10)
            ring.lineWidth = 5
            ring.stroke()
            let handle = NSBezierPath()
            handle.move(to: NSPoint(x: 42, y: 42))
            handle.line(to: NSPoint(x: 57, y: 57))
            handle.lineWidth = 7
            handle.lineCapStyle = .round
            handle.stroke()
            let inside = lens.insetBy(dx: 6, dy: 6)
            if let progress {
                // A faint lens, filled from the bottom up to how far it's got.
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSBezierPath(roundedRect: inside, xRadius: 4, yRadius: 4).fill()
                let level = inside.height * max(0.08, min(1, progress))
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: inside.minX, y: inside.maxY - level, width: inside.width, height: level))
                    .addClip()
                NSColor.black.setFill()
                NSBezierPath(roundedRect: inside, xRadius: 4, yRadius: 4).fill()
                NSGraphicsContext.restoreGraphicsState()
            } else if paused {
                for x in [inside.midX - 7.5, inside.midX + 2.5] {
                    NSBezierPath(roundedRect: NSRect(x: x, y: inside.minY + 2, width: 5, height: inside.height - 4),
                                 xRadius: 1.6, yRadius: 1.6).fill()
                }
            }
            if update {
                // Cut a gap around it, so it reads as a dot on the mark and not part of it.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 41, y: -1, width: 24, height: 24)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 46, y: 4, width: 14, height: 14)).fill()
            }
            return true
        }
        image.isTemplate = true   // takes the menubar's color, light or dark
        image.accessibilityDescription = "Variabe Search"
        return image
    }
}

/// The menubar icon and its menu: what's going on (with a progress bar), Search…, the window, Pause, Settings, Quit.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    var onSearch: () -> Void = {}
    var onOpenWindow: () -> Void = {}
    var onSettings: () -> Void = {}
    var onChooseFolders: () -> Void = {}
    var onPauseChanged: (Bool) -> Void = { _ in }
    var onCheckForUpdates: () -> Void = {}
    private var shownProgress: Double?
    private var shownPaused = false
    private var shownUpdate = false

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()
        observeModel()
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.status
            _ = model.progress
            _ = model.updateAvailable
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshButton()
                self?.observeModel()
            }
        }
    }

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let progress = model.progress.map { ($0 * 50).rounded() / 50 }   // redraw in 2% steps, not every file
        let paused = model.status.paused, update = model.updateAvailable != nil
        if progress != shownProgress || paused != shownPaused || update != shownUpdate || button.image == nil {
            button.image = StatusIcon.image(progress: progress, paused: paused, update: update)
            shownProgress = progress
            shownPaused = paused
            shownUpdate = update
        }
        button.toolTip = "Variabe Search — \(model.statusLine)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem()
        let view = NSHostingView(rootView: MenuStatusView(model: model))
        view.frame.size = view.fittingSize
        header.view = view
        menu.addItem(header)
        menu.addItem(.separator())
        if let version = model.updateAvailable {
            menu.addItem(ActionMenuItem("Update to Variabe Search \(version)…") { [weak self] in self?.onCheckForUpdates() })
            menu.addItem(.separator())
        }

        if !model.hasFolders {
            menu.addItem(ActionMenuItem("Choose Folders to Search…") { [weak self] in self?.onChooseFolders() })
        }
        let search = ActionMenuItem("Search…") { [weak self] in self?.onSearch() }
        if let hotkey = model.hotkey, let (key, modifiers) = hotkey.menuEquivalent {
            search.keyEquivalent = key
            search.keyEquivalentModifierMask = modifiers
        }
        menu.addItem(search)
        menu.addItem(ActionMenuItem("Open Variabe Search") { [weak self] in self?.onOpenWindow() })
        if model.hasFolders {
            menu.addItem(.separator())
            let paused = model.status.paused
            menu.addItem(ActionMenuItem(paused ? "Resume Indexing" : "Pause Indexing") { [weak self] in
                self?.onPauseChanged(!paused)
            })
        }
        switch model.download.phase {
        case .failed, .needed:
            menu.addItem(ActionMenuItem("Download the Model") { [weak self] in self?.model.download.start() })
        default:
            break
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", key: ",") { [weak self] in self?.onSettings() })
        if model.updateAvailable == nil, Updates.hasFeed {
            menu.addItem(ActionMenuItem("Check for Updates…") { [weak self] in self?.onCheckForUpdates() })
        }
        menu.addItem(ActionMenuItem("Quit Variabe Search", key: "q") { NSApp.terminate(nil) })
    }

    /// The menu as text, for the -debugMenu launch argument (menus can't be clicked from a script).
    func describeMenu() -> String {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        return menu.items.map { item in
            if item.isSeparatorItem { return "—" }
            if item.view != nil { return "[\(model.statusLine)]" }
            return item.title + (item.isEnabled ? "" : " (disabled)")
        }.joined(separator: " | ")
    }

    /// Runs a menu item by title, for -debugMenu.
    func performItem(titled title: String) {
        let menu = NSMenu()
        menuNeedsUpdate(menu)
        guard let item = menu.items.first(where: { $0.title == title }), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }
}

/// The top of the menu: the status line, a detail (where, or how long), and progress while there is some.
struct MenuStatusView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.statusLine)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let progress = model.progress {
                ProgressView(value: progress)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(width: 280, alignment: .leading)
    }

    private var detail: String? {
        if model.download.isActive { return model.download.progressText }
        if case .failed(let message) = model.download.phase { return message }
        guard model.hasFolders else { return "Pick the folders it should search." }
        let missing = Set(model.status.missingRoots), unreadable = Set(model.status.unreadableRoots)
        let names = model.settings.roots.map { root in
            root.lastPathComponent + (missing.contains(root.path) ? " (not connected)"
                                      : unreadable.contains(root.path) ? " (no access)" : "")
        }
        return "In " + names.joined(separator: ", ")
    }
}

/// Makes an NSMenuItem that runs a closure.
private final class MenuAction: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}

func ActionMenuItem(_ title: String, key: String = "", handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: key)
    item.target = action
    item.representedObject = action  // `target` is weak; this keeps the action alive
    return item
}
