import AppKit
import CryptoKit
import SwiftUI
import WebKit

final class HtmlAnswerWeb: WKWebView {
    var fileURL: URL?
    private var fileMenu: NSMenu?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let fileURL else { return super.menu(for: event) }
        let menu = AnswerMenus.file(fileURL)
        fileMenu = menu
        return menu
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        guard let fileURL else { return }
        let custom = AnswerMenus.file(fileURL)
        fileMenu = custom
        menu.removeAllItems()
        for item in custom.items {
            custom.removeItem(item)
            menu.addItem(item)
        }
    }
}

struct HtmlAnswerWebView: NSViewRepresentable {
    var identity: String
    var html: String
    var file: URL?
    var visible: Bool
    var onHeight: (CGFloat) -> Void

    func makeNSView(context: Context) -> DemoWebHost { DemoWebHost() }

    func updateNSView(_ host: DemoWebHost, context: Context) {
        host.configure(identity: identity, html: html, file: file, visible: visible, onHeight: onHeight)
    }

    static func dismantleNSView(_ host: DemoWebHost, coordinator: ()) {
        host.deactivate()
    }
}

/// A cheap native placeholder. Offscreen cards never allocate a WKWebView.
final class DemoWebHost: NSView {
    var html = ""
    private(set) var identity = ""
    var file: URL?
    var onHeight: (CGFloat) -> Void = { _ in }
    private(set) var active = false
    private var requested = false
    private var disposed = false
    private var scrollObserver: NSObjectProtocol?
    private var digest = ""
    private var lastKey = ""
    private let picture = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        picture.imageScaling = .scaleAxesIndependently
        picture.autoresizingMask = [.width, .height]
        addSubview(picture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var cacheKey: String {
        "\(identity)-\(digest)-\((bounds.width * 2).rounded())-\(window?.backingScaleFactor ?? 2)"
    }

    var distanceFromCenter: CGFloat {
        guard let window else { return .greatestFiniteMagnitude }
        let center = enclosingScrollView.map { $0.convert($0.bounds, to: nil).midY } ?? window.contentView?.bounds.midY ?? 0
        return abs(convert(bounds, to: nil).midY - center)
    }

    func configure(identity: String = "", html: String, file: URL?, visible: Bool, onHeight: @escaping (CGFloat) -> Void) {
        self.onHeight = onHeight
        self.file = file
        self.identity = identity
        if self.html != html {
            self.html = html
            digest = SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
            lastKey = ""
        }
        disposed = false
        requested = visible
        refresh()
    }

    override func layout() {
        super.layout()
        picture.frame = bounds
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        if window != nil, let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    private func refresh() {
        guard !disposed, bounds.width > 1 else { return }
        var near = false
        if window != nil, let scroll = enclosingScrollView, let document = scroll.documentView {
            let viewport = scroll.contentView.bounds.insetBy(dx: 0, dy: -scroll.contentView.bounds.height)
            near = convert(bounds, to: document).intersects(viewport)
        }
        active = window != nil && (requested || near)
        let key = cacheKey
        if lastKey != key {
            lastKey = key
            picture.image = DemoSnapshots.shared.image(for: key)
            if let height = DemoSnapshots.shared.height(for: key) { report(height) }
        }
        // Defer native mounting and SwiftUI height writes out of layout/updateNSView.
        DemoWebPool.shared.schedule(self)
    }

    func report(_ height: CGFloat) {
        let key = cacheKey
        DispatchQueue.main.async { [weak self] in
            guard let self, self.cacheKey == key else { return }
            self.onHeight(height)
        }
    }

    func mount(_ web: WKWebView) {
        if web.superview !== self {
            web.removeFromSuperview()
            web.frame = bounds
            web.autoresizingMask = [.width, .height]
            addSubview(web)
        }
    }

    func showSnapshot() { picture.image = DemoSnapshots.shared.image(for: cacheKey) }

    func deactivate() {
        disposed = true
        active = false
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        DemoWebPool.shared.release(self)
    }

    override func mouseDown(with event: NSEvent) {
        guard active else { return }
        DemoWebPool.shared.activate(self, force: true)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === picture ? self : hit
    }

    override func menu(for event: NSEvent) -> NSMenu? { file.map { AnswerMenus.file($0) } }
}

@MainActor
private final class DemoSnapshots {
    static let shared = DemoSnapshots()
    private let images = NSCache<NSString, NSImage>()
    private let heights = NSCache<NSString, NSNumber>()

    init() {
        images.totalCostLimit = 64 * 1_024 * 1_024
        images.countLimit = 128
        heights.countLimit = 512
    }

    func image(for key: String) -> NSImage? { images.object(forKey: key as NSString) }
    func height(for key: String) -> CGFloat? { heights.object(forKey: key as NSString).map { CGFloat($0.doubleValue) } }
    func remember(height: CGFloat, key: String) { heights.setObject(NSNumber(value: Double(height)), forKey: key as NSString) }
    func remember(image: NSImage, key: String) {
        let cost = image.representations.map { $0.pixelsWide * $0.pixelsHigh * 4 }.max() ?? 0
        images.setObject(image, forKey: key as NSString, cost: cost)
    }
}

/// Bounds WKWebView instances, not WebKit's internal process count.
@MainActor
final class DemoWebPool {
    static let shared = DemoWebPool()
    static let limit = 3
    private let store = WKWebsiteDataStore.nonPersistent()
    private var slots: [DemoWebSlot] = []
    private let waiting = NSHashTable<DemoWebHost>.weakObjects()
    private let scheduled = NSHashTable<DemoWebHost>.weakObjects()
    var instanceCount: Int { slots.count }
    var activeCount: Int { slots.filter { $0.owner != nil || $0.retiring }.count }

    func schedule(_ host: DemoWebHost) {
        guard !scheduled.contains(host) else { return }
        scheduled.add(host)
        DispatchQueue.main.async { [weak self, weak host] in
            guard let self, let host else { return }
            self.scheduled.remove(host)
            self.activate(host)
        }
    }

    func release(_ host: DemoWebHost) {
        waiting.remove(host)
        if let slot = slots.first(where: { $0.owner === host && !$0.retiring }) { retire(slot) }
    }

    func activate(_ host: DemoWebHost, force: Bool = false) {
        guard host.active, host.window != nil else {
            waiting.remove(host)
            if let slot = slots.first(where: { $0.owner === host && !$0.retiring }) { retire(slot) }
            return
        }
        if let slot = slots.first(where: { $0.owner === host }) {
            if slot.retiring { waiting.add(host) } else { slot.attach(host) }
            return
        }
        waiting.add(host)
        if let slot = slots.first(where: { $0.owner == nil && !$0.retiring }) {
            waiting.remove(host)
            slot.attach(host)
        } else if slots.count < Self.limit {
            let slot = DemoWebSlot(store: store)
            slots.append(slot)
            waiting.remove(host)
            slot.attach(host)
        } else if let farthest = slots.filter({ !$0.retiring }).max(by: {
            ($0.owner?.distanceFromCenter ?? .greatestFiniteMagnitude) < ($1.owner?.distanceFromCenter ?? .greatestFiniteMagnitude)
        }), force || (farthest.owner?.distanceFromCenter ?? .greatestFiniteMagnitude) > host.distanceFromCenter + 40 {
            retire(farthest, preferred: host)
        }
    }

    private func retire(_ slot: DemoWebSlot, preferred: DemoWebHost? = nil) {
        slot.retire { [weak self, weak preferred] in
            guard let self else { return }
            if let preferred, self.isWaitingCandidate(preferred) {
                self.waiting.remove(preferred)
                slot.attach(preferred)
            } else if let next = self.waiting.allObjects.filter({ self.isWaitingCandidate($0) }).min(by: { $0.distanceFromCenter < $1.distanceFromCenter }) {
                self.waiting.remove(next)
                slot.attach(next)
            }
        }
    }

    private func isWaitingCandidate(_ host: DemoWebHost) -> Bool {
        host.active && host.window != nil && !slots.contains { $0.owner === host }
    }
}

@MainActor
private final class DemoWebSlot: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var owner: DemoWebHost?
    let web: HtmlAnswerWeb
    private(set) var retiring = false
    private var html = ""
    private var identity = ""
    private var loaded = false
    private var generation = 0
    private var height: CGFloat = 160
    private var navigation: WKNavigation?

    init(store: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        web = HtmlAnswerWeb(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "nomi")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.heightScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsMagnification = false
        web.allowsBackForwardNavigationGestures = false
        web.underPageBackgroundColor = .clear
    }

    func attach(_ host: DemoWebHost) {
        owner = host
        host.mount(web)
        web.fileURL = host.file
        if html != host.html || identity != host.identity {
            generation += 1
            html = host.html
            identity = host.identity
            loaded = false
            web.isHidden = true
            navigation = web.loadHTMLString(html, baseURL: nil)
        }
    }

    func retire(onComplete: @escaping () -> Void) {
        retiring = true
        generation += 1
        let ticket = generation
        let key = owner?.cacheKey
        let finish: (NSImage?) -> Void = { [weak self] image in
            guard let self, self.generation == ticket, self.retiring else { return }
            if let key, let image { DemoSnapshots.shared.remember(image: image, key: key) }
            self.owner?.showSnapshot()
            self.owner = nil
            self.web.removeFromSuperview()
            self.web.stopLoading()
            // Stop timers and scripts while idle; the instance itself remains reusable.
            self.navigation = self.web.loadHTMLString("", baseURL: nil)
            self.html = ""
            self.loaded = false
            self.retiring = false
            onComplete()
        }
        if loaded, web.bounds.width > 0, web.bounds.height > 0 {
            let config = snapshotConfiguration()
            web.takeSnapshot(with: config) { image, _ in finish(image) }
            // An unresponsive demo must never hold a pool slot indefinitely.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { finish(nil) }
        } else { finish(nil) }
    }

    private func snapshotConfiguration() -> WKSnapshotConfiguration {
        let config = WKSnapshotConfiguration()
        let scale = web.window?.backingScaleFactor ?? 2
        let ratio = min(1, 2048 / max(web.bounds.width * scale, web.bounds.height * scale, 1))
        config.snapshotWidth = NSNumber(value: Double(web.bounds.width * ratio))
        return config
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation, !retiring, owner != nil, !html.isEmpty else { return }
        loaded = true
        web.isHidden = false
        let ticket = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.generation == ticket, !self.retiring, let key = self.owner?.cacheKey else { return }
            self.web.takeSnapshot(with: self.snapshotConfiguration()) { [weak self] image, _ in
                guard let self, self.generation == ticket, self.owner?.cacheKey == key, let image else { return }
                DemoSnapshots.shared.remember(image: image, key: key)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !retiring, message.name == "nomi", message.frameInfo.isMainFrame,
              let owner, let body = message.body as? [String: Any],
              let reported = (body["height"] as? NSNumber)?.doubleValue,
              reported.isFinite, reported > 0 else { return }
        let next = CGFloat(min(max(reported, 44), 16_000))
        guard abs(height - next) > 1 || DemoSnapshots.shared.height(for: owner.cacheKey) == nil else { return }
        height = next
        DemoSnapshots.shared.remember(height: next, key: owner.cacheKey)
        owner.report(next)
    }

    // Keep the original navigation sandbox, including response and popup checks.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        return navigationAction.navigationType == .other && (scheme == nil || scheme == "about") ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let scheme = navigationResponse.response.url?.scheme?.lowercased()
        return scheme == nil || scheme == "about" ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    private static let heightScript = """
    (() => {
      let timer = null;
      function report() {
        if (timer !== null) return;
        timer = setTimeout(() => {
          timer = null;
          const height = document.body ? Math.ceil(document.body.scrollHeight) : 0;
          window.webkit.messageHandlers.nomi.postMessage({ height });
        }, 60);
      }
      if (window.ResizeObserver && document.body) new ResizeObserver(report).observe(document.body, { box: 'border-box' });
      if (window.MutationObserver && document.body) new MutationObserver(report).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true });
      document.addEventListener('input', report);
      document.addEventListener('click', report);
      report();
    })();
    """
}
