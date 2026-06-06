import Cocoa
import SwiftUI
import Combine
import IOKit.ps
import Darwin

// MARK: - Clipboard Item Model
enum ClipboardContentType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Codable, Identifiable, Hashable {
    var id: UUID
    var type: ClipboardContentType
    var textContent: String?
    var imagePath: String?
    var timestamp: Date
    var sourceApp: String?
    var sourceAppBundleId: String?
    var isFavorite: Bool?
    
    static func text(_ content: String, sourceApp: String?, sourceAppBundleId: String?) -> ClipboardItem {
        ClipboardItem(id: UUID(), type: .text, textContent: content, imagePath: nil, timestamp: Date(), sourceApp: sourceApp, sourceAppBundleId: sourceAppBundleId, isFavorite: false)
    }
    
    static func image(_ path: String, sourceApp: String?, sourceAppBundleId: String?) -> ClipboardItem {
        ClipboardItem(id: UUID(), type: .image, textContent: nil, imagePath: path, timestamp: Date(), sourceApp: sourceApp, sourceAppBundleId: sourceAppBundleId, isFavorite: false)
    }
    
    // MARK: - Smart Detection Helpers
    
    var isURL: Bool {
        guard type == .text, let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let pattern = "^(https?://)?[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(/\\S*)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    var urlHost: String? {
        guard isURL, let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        var urlString = text
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        return URL(string: urlString)?.host
    }
    
    var isColor: Bool {
        guard type == .text, let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let hexPattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{8})$"
        let hexRegex = try? NSRegularExpression(pattern: hexPattern, options: [])
        let range = NSRange(location: 0, length: text.utf16.count)
        if hexRegex?.firstMatch(in: text, options: [], range: range) != nil {
            return true
        }
        let rgbPattern = "^rgb\\s*\\(\\s*\\d+\\s*,\\s*\\d+\\s*,\\s*\\d+\\s*\\)$|^rgba\\s*\\(\\s*\\d+\\s*,\\s*\\d+\\s*,\\s*\\d+\\s*,\\s*([0-9]*\\.)?[0-9]+\\s*\\)$"
        let rgbRegex = try? NSRegularExpression(pattern: rgbPattern, options: .caseInsensitive)
        return rgbRegex?.firstMatch(in: text, options: [], range: range) != nil
    }
    
    var isCodeSnippet: Bool {
        guard type == .text, let text = textContent else { return false }
        let codeIndicators = ["{", "}", ";", "func ", "import ", "let ", "var ", "class ", "def ", "function ", "const ", "class="]
        let lines = text.components(separatedBy: .newlines)
        if lines.count >= 2 {
            let matches = codeIndicators.filter { text.contains($0) }.count
            return matches >= 2
        }
        return false
    }
    
    func parseColor() -> SwiftUI.Color? {
        guard isColor, let text = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        
        if text.hasPrefix("#") {
            var hex = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            if hex.count == 6 {
                var rgbValue: UInt64 = 0
                Scanner(string: hex).scanHexInt64(&rgbValue)
                let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
                let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
                let b = Double(rgbValue & 0x0000FF) / 255.0
                return SwiftUI.Color(red: r, green: g, blue: b)
            } else if hex.count == 8 {
                var rgbaValue: UInt64 = 0
                Scanner(string: hex).scanHexInt64(&rgbaValue)
                let r = Double((rgbaValue & 0xFF000000) >> 24) / 255.0
                let g = Double((rgbaValue & 0x00FF0000) >> 16) / 255.0
                let b = Double((rgbaValue & 0x0000FF00) >> 8) / 255.0
                let a = Double(rgbaValue & 0x000000FF) / 255.0
                return SwiftUI.Color(red: r, green: g, blue: b, opacity: a)
            }
        } else {
            let pattern = "rgba?\\s*\\(\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*(?:,\\s*([0-9.]+)\\s*)?\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) else {
                return nil
            }
            
            let nsText = text as NSString
            let rStr = nsText.substring(with: match.range(at: 1))
            let gStr = nsText.substring(with: match.range(at: 2))
            let bStr = nsText.substring(with: match.range(at: 3))
            
            let r = (Double(rStr) ?? 0) / 255.0
            let g = (Double(gStr) ?? 0) / 255.0
            let b = (Double(bStr) ?? 0) / 255.0
            
            var a = 1.0
            if match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound {
                let aStr = nsText.substring(with: match.range(at: 4))
                a = Double(aStr) ?? 1.0
            }
            
            return SwiftUI.Color(red: r, green: g, blue: b, opacity: a)
        }
        return nil
    }
}

// MARK: - Notch Panel Controller

class NotchPanelController: ObservableObject {
    
    private var panel: NSPanel?
    private var hostingView: NotchHostingView<NotchContentView>?
    private var screenObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isExpanded: Bool = false {
        didSet {
            if isExpanded {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.updatePanelFrame(expanding: true, clipboard: self.isClipboardAlertActive)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self, !self.isExpanded, !self.isClipboardAlertActive else { return }
                    self.updatePanelFrame()
                }
            }
        }
    }
    @Published var isHovering: Bool = false
    @Published var isPinned: Bool = false
    @Published var isClipboardAlertActive: Bool = false {
        didSet {
            if isClipboardAlertActive {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.updatePanelFrame(expanding: self.isExpanded, clipboard: true)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self, !self.isExpanded, !self.isClipboardAlertActive else { return }
                    self.updatePanelFrame()
                }
            }
        }
    }
    
    @Published var clipboardHistory: [ClipboardItem] = []
    
    private var clipboardTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var alertTimer: Timer?
    
    // Detected notch dimensions (will be set from screen info)
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    
    // Expanded dimensions
    let expandedWidth: CGFloat = 520
    let expandedHeight: CGFloat = 210
    
    var isMediaActive: Bool {
        let enabled = UserDefaults.standard.object(forKey: "mediaPlayerEnabled") as? Bool ?? true
        return enabled && !SystemMediaManager.shared.title.isEmpty
    }
    
    init() {
        loadClipboardHistory()
        
        // Listen to media remote changes to dynamically adjust expanded window height
        SystemMediaManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.objectWillChange.send()
                if self.isExpanded {
                    self.updatePanelFrame()
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        closePanel()
        stopClipboardMonitoring()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Notch Detection
    
    /// Detects the actual notch dimensions from the screen
    private func detectNotchDimensions(screen: NSScreen) {
        // The notch height = screen.frame.height - screen.visibleFrame.height - visibleFrame y offset
        // On notch MacBooks, the safe area insets reveal the notch
        
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        // Menu bar height (includes notch on notch MacBooks)
        // On notch MacBooks this is ~37pt, on non-notch it's ~25pt
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        
        // If menu bar height > 30, it's likely a notch MacBook
        let hasNotch = menuBarHeight > 30
        
        if hasNotch {
            // Notch height is the menu bar area
            notchHeight = menuBarHeight
            
            // Try to detect notch width from auxiliary areas (macOS 14+)
            if #available(macOS 14.0, *) {
                let topLeft = screen.auxiliaryTopLeftArea
                let topRight = screen.auxiliaryTopRightArea
                
                if let left = topLeft, let right = topRight {
                    // Notch width = screen width - left area - right area
                    notchWidth = screenFrame.width - left.width - right.width
                } else {
                    // Fallback: standard MacBook Pro notch width
                    notchWidth = 180
                }
            } else {
                notchWidth = 180
            }
        } else {
            // No notch detected, use a default small bar
            notchHeight = 28
            notchWidth = 180
        }
    }
    
    // MARK: - Panel Lifecycle
    
    func showPanel() {
        guard let screen = NSScreen.main else { return }
        
        // Detect actual notch dimensions
        detectNotchDimensions(screen: screen)
        
        let contentView = NotchContentView(controller: self)
        
        // Width is always fixed to expanded width to prevent horizontal coordinate shifts
        let panelWidth = expandedWidth + 60
        let panelHeight = notchHeight + 20
        
        let screenFrame = screen.frame
        
        // Position centered at the very top of the screen
        let xPos = screenFrame.midX - panelWidth / 2
        let yPos = screenFrame.maxY - panelHeight
        
        let panelRect = NSRect(x: xPos, y: yPos, width: panelWidth, height: panelHeight)
        
        // Create the panel
        let panel = NotchPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Panel configuration
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        
        // Setup hosting view
        let hosting = NotchHostingView(rootView: contentView)
        hosting.controller = self
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        
        // Disable automatic sizing options to prevent Auto Layout conflicts with window size changes
        hosting.sizingOptions = []
        
        panel.contentView = hosting
        panel.orderFrontRegardless()
        
        self.panel = panel
        self.hostingView = hosting
        
        // Observe screen changes
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionPanel()
        }
        
        // Start clipboard monitoring
        startClipboardMonitoring()
    }
    
    func closePanel() {
        stopClipboardMonitoring()
        panel?.orderOut(nil)
        panel = nil
    }
    
    // MARK: - Interaction
    
    func toggleExpanded() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)) {
            isExpanded.toggle()
        }
    }
    
    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
    
    // MARK: - Positioning
    
    private func repositionPanel() {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        
        // Re-detect notch dimensions in case display changed
        detectNotchDimensions(screen: screen)
        
        updatePanelFrame()
    }
    
    func updatePanelFrame(expanding: Bool? = nil, clipboard: Bool? = nil) {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        
        let isExp = expanding ?? isExpanded
        let isClip = clipboard ?? isClipboardAlertActive
        
        let targetWidth = expandedWidth + 60
        let targetHeight: CGFloat
        
        if isExp {
            targetHeight = expandedHeight + 20 + notchHeight
        } else if isClip {
            targetHeight = notchHeight + 20
        } else {
            targetHeight = notchHeight + 20
        }
        
        let screenFrame = screen.frame
        let xPos = screenFrame.midX - targetWidth / 2
        let yPos = screenFrame.maxY - targetHeight
        
        let newFrame = NSRect(x: xPos, y: yPos, width: targetWidth, height: targetHeight)
        
        panel.setFrame(newFrame, display: true, animate: false)
        hostingView?.frame = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    }
    
    // MARK: - Clipboard Monitoring
    
    func startClipboardMonitoring() {
        clipboardTimer?.invalidate()
        lastChangeCount = NSPasteboard.general.changeCount
        
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheDir = paths[0].appendingPathComponent("BarOnClipboardCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        return cacheDir
    }
    
    private func checkClipboard() {
        let changeCount = NSPasteboard.general.changeCount
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            
            let pasteboard = NSPasteboard.general
            let frontApp = NSWorkspace.shared.frontmostApplication
            let sourceApp = frontApp?.localizedName ?? LocalizationManager.shared[.system]
            let sourceAppBundleId = frontApp?.bundleIdentifier
            
            // 1. Check for Image content
            if pasteboard.types?.contains(.tiff) == true || pasteboard.types?.contains(.png) == true {
                if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                    saveImageToHistory(image, sourceApp: sourceApp, sourceAppBundleId: sourceAppBundleId)
                    
                    let enabled = UserDefaults.standard.object(forKey: "clipboardAlertEnabled") as? Bool ?? true
                    if enabled {
                        triggerClipboardAlert()
                    }
                    return
                }
            }
            
            // 2. Check for Text content
            if let newString = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !newString.isEmpty {
                addToClipboardHistory(.text(newString, sourceApp: sourceApp, sourceAppBundleId: sourceAppBundleId))
                
                let enabled = UserDefaults.standard.object(forKey: "clipboardAlertEnabled") as? Bool ?? true
                if enabled {
                    triggerClipboardAlert()
                }
            }
        }
    }
    
    private func saveImageToHistory(_ image: NSImage, sourceApp: String?, sourceAppBundleId: String?) {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return
        }
        
        let filename = "\(UUID().uuidString).png"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        do {
            try pngData.write(to: fileURL)
            let item = ClipboardItem.image(fileURL.absoluteString, sourceApp: sourceApp, sourceAppBundleId: sourceAppBundleId)
            addToClipboardHistory(item)
        } catch {
            print("Failed to save copied image: \(error)")
        }
    }
    
    func triggerClipboardAlert() {
        alertTimer?.invalidate()
        
        // If expanded, collapse it first
        if isExpanded {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = false
            }
        }
        
        let enabled = UserDefaults.standard.object(forKey: "clipboardAlertEnabled") as? Bool ?? true
        if !enabled {
            return
        }
        
        // Activate clipboard alert state
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isClipboardAlertActive = true
        }
        
        // Auto-dismiss after 1.6 seconds
        alertTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                self.isClipboardAlertActive = false
            }
        }
    }
    
    // MARK: - Clipboard History Persistence
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastChangeCount = pasteboard.changeCount
    }
    
    func copyImageToClipboard(from path: String) {
        guard let url = URL(string: path), let image = NSImage(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image, url as NSURL])
        self.lastChangeCount = pasteboard.changeCount
    }
    
    func addToClipboardHistory(_ item: ClipboardItem) {
        // Filter out items of the same text or image path (deduplicate)
        var history = clipboardHistory.filter { current in
            if current.type == .text && item.type == .text {
                return current.textContent != item.textContent
            }
            if current.type == .image && item.type == .image {
                return current.imagePath != item.imagePath
            }
            return true
        }
        
        // Preserve favorite status of duplicate if it was favorited
        if let existing = clipboardHistory.first(where: {
            if $0.type == .text && item.type == .text { return $0.textContent == item.textContent }
            if $0.type == .image && item.type == .image { return $0.imagePath == item.imagePath }
            return false
        }) {
            var itemWithFav = item
            itemWithFav.isFavorite = existing.isFavorite
            history.insert(itemWithFav, at: 0)
        } else {
            history.insert(item, at: 0)
        }
        
        if history.count > 15 {
            // Keep all favorites, and keep the newest non-favorites up to total limit of 15
            let favorites = history.filter { $0.isFavorite == true }
            let nonFavorites = history.filter { $0.isFavorite != true }
            
            let maxNonFavorites = max(0, 15 - favorites.count)
            let nonFavoritesToKeep = Array(nonFavorites.prefix(maxNonFavorites))
            let nonFavoritesToRemove = Array(nonFavorites.dropFirst(maxNonFavorites))
            
            // Delete files of removed image items to avoid leaking cache space
            for oldItem in nonFavoritesToRemove {
                if oldItem.type == .image, let path = oldItem.imagePath, let url = URL(string: path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            var newHistory = favorites + nonFavoritesToKeep
            newHistory.sort { $0.timestamp > $1.timestamp }
            history = newHistory
        }
        
        clipboardHistory = history
        saveClipboardHistory()
    }
    
    func removeFromClipboardHistory(_ item: ClipboardItem) {
        if item.type == .image, let path = item.imagePath, let url = URL(string: path) {
            try? FileManager.default.removeItem(at: url)
        }
        clipboardHistory.removeAll { $0.id == item.id }
        saveClipboardHistory()
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let index = clipboardHistory.firstIndex(where: { $0.id == item.id }) {
            var updated = clipboardHistory[index]
            updated.isFavorite = !(updated.isFavorite ?? false)
            clipboardHistory[index] = updated
            saveClipboardHistory()
        }
    }
    
    private func saveClipboardHistory() {
        if let encoded = try? JSONEncoder().encode(clipboardHistory) {
            UserDefaults.standard.set(encoded, forKey: "clipboardHistoryJSON")
        }
    }
    
    func loadClipboardHistory() {
        if let data = UserDefaults.standard.data(forKey: "clipboardHistoryJSON"),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            clipboardHistory = decoded
        } else {
            // Check if there was old string-only history and migrate it
            if let saved = UserDefaults.standard.stringArray(forKey: "clipboardHistory") {
                clipboardHistory = saved.map { ClipboardItem.text($0, sourceApp: nil, sourceAppBundleId: nil) }
                // Clear old key
                UserDefaults.standard.removeObject(forKey: "clipboardHistory")
                saveClipboardHistory()
            }
        }
    }
}

// MARK: - Notch Panel
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - Notch Hosting View
class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: NotchPanelController?
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = controller else { return super.hitTest(point) }
        
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        
        if controller.isExpanded {
            targetWidth = controller.expandedWidth
            targetHeight = controller.expandedHeight + controller.notchHeight
        } else if controller.isClipboardAlertActive {
            targetWidth = 380
            targetHeight = controller.notchHeight
        } else if controller.isMediaActive {
            targetWidth = 340
            targetHeight = controller.notchHeight
        } else {
            targetWidth = controller.notchWidth
            targetHeight = controller.notchHeight
        }
        
        let windowWidth = bounds.width
        let windowHeight = bounds.height
        
        let xPos = (windowWidth - targetWidth) / 2
        let yPos = windowHeight - targetHeight
        
        let visibleRect = NSRect(x: xPos, y: yPos, width: targetWidth, height: targetHeight)
        
        if visibleRect.contains(point) {
            return super.hitTest(point)
        }
        
        return nil
    }
}
