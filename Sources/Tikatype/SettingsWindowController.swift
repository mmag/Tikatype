import AppKit
import Carbon
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController,
                                      NSTableViewDataSource,
                                      NSTableViewDelegate {

    private let settings: SettingsManager
    private var excludedApps: [String] = []
    private var layouts: [TISInputSource] = []

    private var primaryPopup:   NSPopUpButton!
    private var secondaryPopup: NSPopUpButton!
    private var tableView:      NSTableView!
    private var removeButton:   NSButton!
    private var loginCheckbox:  NSButton!

    private let contentWidth: CGFloat = 360  // 400 window − 20 padding each side

    // MARK: - Init

    init(settings: SettingsManager) {
        self.settings = settings
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.settingsTitle
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        loadState()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment   = .leading
        root.spacing     = 8
        root.edgeInsets  = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Layouts
        root.addArrangedSubview(sectionHeader(L10n.settingsLayouts))
        primaryPopup   = NSPopUpButton(); primaryPopup.target   = self; primaryPopup.action   = #selector(layoutChanged)
        secondaryPopup = NSPopUpButton(); secondaryPopup.target = self; secondaryPopup.action = #selector(layoutChanged)
        root.addArrangedSubview(formRow(L10n.settingsPrimary,   control: primaryPopup))
        root.addArrangedSubview(formRow(L10n.settingsSecondary, control: secondaryPopup))
        root.addArrangedSubview(separator())

        // Hotkeys (read-only)
        root.addArrangedSubview(sectionHeader(L10n.settingsHotkeys))
        root.addArrangedSubview(hotkeyRow(L10n.settingsWord,      value: "Ctrl+Shift"))
        root.addArrangedSubview(hotkeyRow(L10n.settingsPhrase,    value: "⌥ ⌥"))
        root.addArrangedSubview(hotkeyRow(L10n.settingsSelection, value: L10n.settingsMenuOnly))
        root.addArrangedSubview(separator())

        // Excluded apps
        root.addArrangedSubview(sectionHeader(L10n.settingsExcluded))
        root.addArrangedSubview(buildTableScroll())
        root.addArrangedSubview(buildTableButtons())
        root.addArrangedSubview(separator())

        // Launch at login
        loginCheckbox = NSButton(checkboxWithTitle: L10n.settingsLaunchLogin,
                                 target: self, action: #selector(toggleLogin))
        root.addArrangedSubview(loginCheckbox)
    }

    // MARK: - UI helpers

    private func sectionHeader(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font      = .systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        return lbl
    }

    private func formRow(_ labelText: String, control: NSView) -> NSStackView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = .systemFont(ofSize: 13)
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        lbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        let row = NSStackView(views: [lbl, control])
        row.orientation  = .horizontal
        row.alignment    = .centerY
        row.spacing      = 8
        row.distribution = .fill
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return row
    }

    private func hotkeyRow(_ labelText: String, value: String) -> NSStackView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = .systemFont(ofSize: 13)
        lbl.setContentHuggingPriority(.required, for: .horizontal)
        let val = NSTextField(labelWithString: value)
        val.font      = .monospacedSystemFont(ofSize: 13, weight: .regular)
        val.textColor = .secondaryLabelColor
        let row = NSStackView(views: [lbl, val])
        row.orientation = .horizontal
        row.alignment   = .centerY
        row.spacing     = 8
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return box
    }

    private func buildTableScroll() -> NSScrollView {
        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.headerView = nil
        tableView.rowHeight  = 20
        let col = NSTableColumn(identifier: .init("id"))
        tableView.addTableColumn(col)

        let scroll = NSScrollView()
        scroll.documentView     = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType       = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 80).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        return scroll
    }

    private func buildTableButtons() -> NSStackView {
        let add = NSButton(title: L10n.settingsAdd, target: self, action: #selector(addApp))
        add.bezelStyle = .smallSquare

        removeButton = NSButton(title: L10n.settingsRemove, target: self, action: #selector(removeApp))
        removeButton.bezelStyle = .smallSquare
        removeButton.isEnabled  = false

        let row = NSStackView(views: [add, removeButton])
        row.orientation = .horizontal
        row.spacing     = 4
        return row
    }

    // MARK: - Load state

    private func loadState() {
        layouts = LayoutManager.availableLayouts
        populateLayoutPopups()

        excludedApps = Array(settings.excludedApps).sorted()
        tableView.reloadData()

        loginCheckbox.state = settings.launchAtLogin ? .on : .off
    }

    private func populateLayoutPopups() {
        primaryPopup.removeAllItems()
        secondaryPopup.removeAllItems()

        for layout in layouts {
            let name = LayoutManager.localizedName(of: layout)
                    ?? LayoutManager.sourceID(of: layout)
                    ?? "Unknown"
            primaryPopup.addItem(withTitle: name)
            secondaryPopup.addItem(withTitle: name)
        }

        let pIdx = layouts.firstIndex { LayoutManager.sourceID(of: $0) == settings.primaryLayoutID } ?? 0
        let sIdx = layouts.firstIndex { LayoutManager.sourceID(of: $0) == settings.secondaryLayoutID }
               ?? (layouts.count > 1 ? 1 : 0)

        primaryPopup.selectItem(at: pIdx)
        secondaryPopup.selectItem(at: sIdx)
    }

    // MARK: - Actions

    @objc private func layoutChanged() {
        let pIdx = primaryPopup.indexOfSelectedItem
        let sIdx = secondaryPopup.indexOfSelectedItem
        if pIdx < layouts.count { settings.primaryLayoutID   = LayoutManager.sourceID(of: layouts[pIdx]) }
        if sIdx < layouts.count { settings.secondaryLayoutID = LayoutManager.sourceID(of: layouts[sIdx]) }
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = true
        panel.canChooseDirectories    = false
        panel.allowsMultipleSelection = false
        panel.directoryURL            = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes     = [.applicationBundle]

        panel.begin { [weak self] response in
            guard response == .OK,
                  let url    = panel.url,
                  let bundle = Bundle(url: url),
                  let id     = bundle.bundleIdentifier
            else { return }
            self?.insertBundleID(id)
        }
    }

    private func insertBundleID(_ id: String) {
        guard !excludedApps.contains(id) else { return }
        excludedApps.append(id)
        excludedApps.sort()
        settings.excludedApps = Set(excludedApps)
        tableView.reloadData()
    }

    @objc private func removeApp() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        excludedApps.remove(at: row)
        settings.excludedApps = Set(excludedApps)
        tableView.reloadData()
    }

    @objc private func toggleLogin() {
        settings.launchAtLogin = (loginCheckbox.state == .on)
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { excludedApps.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let cellID = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellID
            let tf = NSTextField(labelWithString: "")
            tf.font = .systemFont(ofSize: 12)
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = excludedApps[row]
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = tableView.selectedRow >= 0
    }
}
