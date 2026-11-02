import AppKit
import Carbon
import Foundation

/// Remembers the last active layout per application bundle ID.
/// When the user switches to an app, restores the layout they were using there.
final class PerAppLayoutManager {

    private var appLayouts: [String: String] = [:]  // bundleID → layout sourceID
    private var currentBundleID: String?

    // MARK: - App activation events

    func applicationDidActivate(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }

        // Save layout for the app we're leaving
        if let leaving = currentBundleID {
            appLayouts[leaving] = LayoutManager.sourceID(of: LayoutManager.currentLayout)
        }

        currentBundleID = bundleID

        // Restore layout for the app we're entering
        if let savedID = appLayouts[bundleID] {
            restoreLayout(sourceID: savedID)
        }
    }

    // MARK: - Private

    private func restoreLayout(sourceID: String) {
        let layouts = LayoutManager.availableLayouts
        guard let target = layouts.first(where: { LayoutManager.sourceID(of: $0) == sourceID }) else {
            return
        }
        // Selecting an input source that is already active is not a no-op for
        // the system: every TISSelectInputSource call makes HIToolbox show the
        // cursor input-source indicator (CursorUIViewService). Skip it when
        // nothing would change, so app switching doesn't poke that service.
        if LayoutManager.sourceID(of: LayoutManager.currentLayout) == sourceID {
            return
        }
        LayoutManager.switchTo(target)
    }
}
