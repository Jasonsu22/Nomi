import Foundation
import Sparkle

/// Updates through Sparkle: a daily check against the appcast on the latest GitHub release,
/// release notes, and one click to download, install and relaunch. Every update must carry
/// an EdDSA signature that matches `SUPublicEDKey` in Info.plist, or Sparkle refuses it.
@MainActor
@Observable
final class AppUpdater {
    private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// False while a check or an install is already running.
    private(set) var canCheck = false

    init() {
        // Only the packaged app has a feed and key in Info.plist; `swift run` and tests skip Sparkle.
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheck = value }
        }
    }

    var isAvailable: Bool { controller != nil }

    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
