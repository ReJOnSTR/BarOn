import SwiftUI
import IOKit.ps
import Darwin
import Foundation

// MARK: - Notch Content View

struct NotchContentView: View {
    @ObservedObject var controller: NotchPanelController
    @ObservedObject private var l10n = LocalizationManager.shared
    @ObservedObject private var mediaManager = SystemMediaManager.shared
    @State private var hoverTimer: Timer?
    @State private var mouseInside = false
    @State private var showSettings = false
    
    @AppStorage("clipboardAlertEnabled") private var clipboardAlertEnabled = true
    @AppStorage("mediaPlayerEnabled") private var mediaPlayerEnabled = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main notch shape
                notchShape
                    .frame(
                        width: controller.isExpanded ? controller.expandedWidth : (controller.isClipboardAlertActive ? 380 : controller.notchWidth),
                        height: controller.isExpanded ? (controller.expandedHeight + controller.notchHeight) : controller.notchHeight
                    )
                    .animation(.spring(
                        response: 0.35,
                        dampingFraction: 0.82,
                        blendDuration: 0
                    ), value: controller.isExpanded)
                    .animation(.spring(
                        response: 0.35,
                        dampingFraction: 0.82,
                        blendDuration: 0
                    ), value: controller.isClipboardAlertActive)
                    .animation(.spring(
                        response: 0.35,
                        dampingFraction: 0.85
                    ), value: controller.isHovering)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Notch Shape View
    
    private var notchShape: some View {
        ZStack(alignment: .top) {
            // Background shape (keeping shadow outside clipping bounds)
            NotchShape(cornerRadius: controller.isExpanded ? 24 : 10, topCornerRadius: 0)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.5), radius: controller.isExpanded ? 20 : (controller.isClipboardAlertActive ? 8 : 3), y: controller.isExpanded ? 10 : 1)
            
            // Inner content wrapper (strictly clipped to the notch bounds)
            ZStack(alignment: .top) {
                // Expanded content
                if controller.isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Clipboard alert content
                if controller.isClipboardAlertActive && !controller.isExpanded {
                    clipboardAlertView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .clipShape(NotchShape(cornerRadius: controller.isExpanded ? 24 : 10, topCornerRadius: 0))
        }
        .onHover { hovering in
            mouseInside = hovering
            controller.setHovering(hovering)
            
            if controller.isPinned {
                return
            }
            
            hoverTimer?.invalidate()
            
            let openDelay = 0.12
            let closeDelay = 0.25
            let response = 0.35
            let damping = 0.82
            let closeDamping = 0.85
            
            if hovering {
                // Delay before expanding
                hoverTimer = Timer.scheduledTimer(withTimeInterval: openDelay, repeats: false) { _ in
                    if mouseInside && !controller.isClipboardAlertActive {
                        withAnimation(.spring(response: response, dampingFraction: damping)) {
                            controller.isExpanded = true
                        }
                    }
                }
            } else {
                // Delay before collapsing
                hoverTimer = Timer.scheduledTimer(withTimeInterval: closeDelay, repeats: false) { _ in
                    if !mouseInside && !controller.isPinned {
                        withAnimation(.spring(response: response, dampingFraction: closeDamping)) {
                            controller.isExpanded = false
                        }
                    }
                }
            }
        }
        .onTapGesture {
            if !controller.isExpanded && !controller.isClipboardAlertActive {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    controller.isExpanded = true
                }
            }
        }
    }
    
    // MARK: - Clipboard Alert View
    
    private var clipboardAlertView: some View {
        HStack {
            // Left side (outside physical notch)
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 11, weight: .bold))
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            // Right side (outside physical notch)
            HStack {
                Text(l10n[.copied])
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: controller.notchHeight)
    }
        // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Top area flanking the physical notch
            HStack(spacing: 0) {
                // Left side container (just the status light on the far left)
                HStack {
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.6), radius: 4)
                        .padding(.leading, 16)
                    
                    Spacer()
                }
                .frame(width: (controller.expandedWidth - controller.notchWidth) / 2)
                
                Spacer()
                    .frame(width: controller.notchWidth)
                
                // Right side container (both Settings and Pin buttons grouped at the far right)
                HStack(spacing: 8) {
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            controller.isPinned.toggle()
                            if !controller.isPinned && !mouseInside {
                                controller.isExpanded = false
                            }
                        }
                    }) {
                        Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(controller.isPinned ? Color.blue : Color.white.opacity(0.6))
                            .rotationEffect(.degrees(controller.isPinned ? 0 : 45))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(controller.isPinned ? Color.blue.opacity(0.15) : Color.white.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n[.pin])
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSettings.toggle()
                        }
                    }) {
                        Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(showSettings ? Color.blue : Color.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(showSettings ? Color.blue.opacity(0.15) : Color.white.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n[.settings])
                }
                .padding(.trailing, 16)
                .frame(width: (controller.expandedWidth - controller.notchWidth) / 2)
            }
            .frame(height: controller.notchHeight)
            
            // Divider below the notch line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            // Center content area with transitions
            ZStack(alignment: .top) {
                if showSettings {
                    settingsContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    VStack(spacing: 10) {
                        if controller.isMediaActive {
                            MediaPlayerWidget()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        ClipboardHistoryView(controller: controller)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
            .frame(height: controller.isMediaActive && !showSettings ? 236 : 170)
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Settings Content
    
    private var settingsContent: some View {
        HStack(spacing: 20) {
            // Clipboard alert toggle
            settingBlock(
                icon: clipboardAlertEnabled ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                label: l10n[.clipboardTracking],
                isActive: clipboardAlertEnabled,
                action: { clipboardAlertEnabled.toggle() }
            )
            
            // Media player toggle
            settingBlock(
                icon: mediaPlayerEnabled ? "play.circle.fill" : "play.circle",
                label: l10n[.mediaControls],
                isActive: mediaPlayerEnabled,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        mediaPlayerEnabled.toggle()
                        controller.updatePanelFrame()
                    }
                }
            )
            
            // Language toggle
            languageToggle
            
            // Quit button
            settingBlock(
                icon: "power",
                label: l10n[.quit],
                isActive: false,
                isDestructive: true,
                action: {
                    NSApp.terminate(nil)
                }
            )
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Language Toggle
    
    private var languageToggle: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                l10n.currentLanguage = l10n.currentLanguage == .turkish ? .english : .turkish
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.purple.opacity(0.18))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.purple.opacity(0.4), lineWidth: 1)
                        )
                    
                    Text(l10n.currentLanguage.flag)
                        .font(.system(size: 22))
                }
                
                Text(l10n.currentLanguage.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .frame(width: 80)
    }
    
    // MARK: - Setting Block
    
    private func settingBlock(icon: String, label: String, isActive: Bool, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? Color.blue.opacity(0.18) : (isDestructive ? Color.red.opacity(0.15) : Color.white.opacity(0.06)))
                        .frame(width: 52, height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isActive ? Color.blue.opacity(0.4) : (isDestructive ? Color.red.opacity(0.4) : Color.clear), lineWidth: 1)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isActive ? Color.blue : (isDestructive ? Color.red : .white.opacity(0.8)))
                }
                
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(isActive ? 0.8 : 0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 80)
    }
}

// MARK: - Clipboard Filter enum
enum ClipboardFilter: CaseIterable {
    case all
    case text
    case image
    case link
    case color
    case favorite
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .text: return "doc.text.fill"
        case .image: return "photo.fill"
        case .link: return "link"
        case .color: return "paintpalette.fill"
        case .favorite: return "star.fill"
        }
    }
    
    func localizedName(_ l10n: LocalizationManager) -> String {
        switch self {
        case .all: return l10n[.filterAll]
        case .text: return l10n[.filterText]
        case .image: return l10n[.filterImage]
        case .link: return l10n[.filterLink]
        case .color: return l10n[.filterColor]
        case .favorite: return l10n[.filterFavorites]
        }
    }
}

// MARK: - Clipboard History View
struct ClipboardHistoryView: View {
    @ObservedObject var controller: NotchPanelController
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all
    
    let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var filteredHistory: [ClipboardItem] {
        var items = controller.clipboardHistory
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .text:
            items = items.filter { $0.type == .text && !$0.isURL && !$0.isColor }
        case .image:
            items = items.filter { $0.type == .image }
        case .link:
            items = items.filter { $0.isURL }
        case .color:
            items = items.filter { $0.isColor }
        case .favorite:
            items = items.filter { $0.isFavorite == true }
        }
        
        // Apply search
        if !searchText.isEmpty {
            items = items.filter { item in
                if let text = item.textContent {
                    return text.localizedCaseInsensitiveContains(searchText)
                }
                if let source = item.sourceApp {
                    return source.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField(l10n[.searchPlaceholder], text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            
            // Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ClipboardFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedFilter = filter
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 8, weight: .bold))
                                Text(filter.localizedName(l10n))
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedFilter == filter ? Color.blue.opacity(0.18) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedFilter == filter ? Color.blue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.5)
                            )
                            .foregroundColor(selectedFilter == filter ? Color.blue : Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 22)
            
            // Scrollable Grid of Cards
            ScrollView(.vertical, showsIndicators: true) {
                if filteredHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.15))
                        Text(searchText.isEmpty ? (selectedFilter == .favorite ? l10n[.emptyFavorites] : l10n[.emptyHistory]) : l10n[.noResults])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(filteredHistory, id: \.id) { item in
                            ClipboardItemCard(item: item) {
                                if item.type == .image, let path = item.imagePath {
                                    controller.copyImageToClipboard(from: path)
                                } else if let text = item.textContent {
                                    controller.copyToClipboard(text)
                                }
                                controller.triggerClipboardAlert()
                            } onDelete: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    controller.removeFromClipboardHistory(item)
                                }
                            } onToggleFavorite: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    controller.toggleFavorite(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(height: 170)
    }
}

// MARK: - Clipboard Item Card
struct ClipboardItemCard: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    @State private var isHovering = false
    
    private var appIcon: NSImage? {
        guard let bundleId = item.sourceAppBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main clickable area
            Button(action: onCopy) {
                HStack(spacing: 10) {
                    leftIndicatorView
                    middleContentView
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Hover actions overlay
            if isHovering {
                HStack(spacing: 3) {
                    if item.isURL {
                        Button(action: {
                            if let text = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                var urlString = text
                                if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                                    urlString = "https://" + urlString
                                }
                                if let url = URL(string: urlString) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }) {
                            Image(systemName: "safari")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.blue)
                                .frame(width: 18, height: 18)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.75))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizationManager.shared[.openInBrowser])
                    }
                    
                    Button(action: onToggleFavorite) {
                        Image(systemName: (item.isFavorite ?? false) ? "star.fill" : "star")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor((item.isFavorite ?? false) ? .yellow : .white.opacity(0.6))
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.75))
                            )
                    }
                    .buttonStyle(.plain)
                    .help((item.isFavorite ?? false) ? LocalizationManager.shared[.removeFromFavorites] : LocalizationManager.shared[.addToFavorites])
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 8))
                            .foregroundColor(.red.opacity(0.9))
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.75))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(LocalizationManager.shared[.deleteFromHistory])
                }
                .padding(4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((item.isFavorite ?? false) ? Color.yellow.opacity(0.3) : Color.white.opacity(isHovering ? 0.15 : 0.06), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
        .onDrag {
            if item.type == .image, let path = item.imagePath, let url = URL(string: path) {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            } else {
                return NSItemProvider(object: (item.textContent ?? "") as NSString)
            }
        }
    }
    
    // MARK: - Left Indicator View
    @ViewBuilder
    private var leftIndicatorView: some View {
        if item.type == .image, let path = item.imagePath, let url = URL(string: path), let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        } else if item.isColor, let color = item.parseColor() {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        } else if item.isURL {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.blue)
            }
        } else if item.isCodeSnippet {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Middle Content View
    @ViewBuilder
    private var middleContentView: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Main Text Content/Preview
            if item.type == .image {
                Text(LocalizationManager.shared[.imageClipboard])
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            } else if item.isColor {
                Text(item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            } else if item.isURL {
                Text(item.urlHost ?? item.textContent ?? "")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.blue)
                    .lineLimit(1)
            } else if item.isCodeSnippet {
                let firstLine = item.textContent?.components(separatedBy: .newlines).first ?? ""
                Text(firstLine)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.95))
                    .lineLimit(1)
            } else {
                Text(item.textContent ?? "")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
            }
            
            // Metadata
            HStack(spacing: 4) {
                // App Icon & Name
                HStack(spacing: 2.5) {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 10, height: 10)
                            .cornerRadius(2)
                    } else {
                        Image(systemName: "app.badge")
                            .font(.system(size: 7))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    
                    Text(item.sourceApp ?? LocalizationManager.shared[.system])
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                // Dot
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5, height: 1.5)
                
                // Extra detail
                if item.type == .image, let path = item.imagePath, let url = URL(string: path), let nsImage = NSImage(contentsOf: url) {
                    Text("\(Int(nsImage.size.width))x\(Int(nsImage.size.height))")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                } else if item.isColor {
                    Text(LocalizationManager.shared[.colorLabel])
                        .font(.system(size: 7.5))
                        .foregroundColor(.white.opacity(0.4))
                } else if item.isURL {
                    Text(LocalizationManager.shared[.linkLabel])
                        .font(.system(size: 7.5))
                        .foregroundColor(.white.opacity(0.4))
                } else if item.isCodeSnippet {
                    let lines = item.textContent?.components(separatedBy: .newlines).count ?? 0
                    Text("\(lines)L")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                } else {
                    let charCount = item.textContent?.count ?? 0
                    Text("\(charCount)c")
                        .font(.system(size: 7.5))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Dot
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5, height: 1.5)
                
                // Time
                Text(formatTimestamp(item.timestamp))
                    .font(.system(size: 7.5))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Notch Shape

struct NotchShape: InsettableShape {
    var cornerRadius: CGFloat
    var topCornerRadius: CGFloat
    var insetAmount: CGFloat = 0
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, topCornerRadius) }
        set {
            cornerRadius = newValue.first
            topCornerRadius = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        
        let w = insetRect.width
        let h = insetRect.height
        let x = insetRect.minX
        let y = insetRect.minY
        
        let bottomLeftRadius = cornerRadius
        let bottomRightRadius = cornerRadius
        
        // Start from top-left
        path.move(to: CGPoint(x: x, y: y))
        
        // Top edge
        path.addLine(to: CGPoint(x: x + w, y: y))
        
        // Right edge going down to bottom-right corner
        path.addLine(to: CGPoint(x: x + w, y: y + h - bottomRightRadius))
        
        // Bottom-right corner
        path.addArc(
            center: CGPoint(x: x + w - bottomRightRadius, y: y + h - bottomRightRadius),
            radius: bottomRightRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: x + bottomLeftRadius, y: y + h))
        
        // Bottom-left corner
        path.addArc(
            center: CGPoint(x: x + bottomLeftRadius, y: y + h - bottomLeftRadius),
            radius: bottomLeftRadius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        // Left edge going back up
        path.addLine(to: CGPoint(x: x, y: y))
        
        path.closeSubpath()
        
        return path
    }
    
    func inset(by amount: CGFloat) -> NotchShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

// MARK: - Preview

#Preview {
    NotchContentView(controller: NotchPanelController())
        .frame(width: 560, height: 200)
        .background(Color.gray.opacity(0.3))
}

// MARK: - Media Player Widget
struct MediaPlayerWidget: View {
    @ObservedObject private var mediaManager = SystemMediaManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Artwork
            if let artwork = mediaManager.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                }
                .frame(width: 40, height: 40)
                .cornerRadius(8)
            }
            
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(mediaManager.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let bundleId = mediaManager.clientBundleId,
                       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                        let icon = NSWorkspace.shared.icon(forFile: url.path)
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 10, height: 10)
                            .cornerRadius(2)
                    }
                    
                    Text(mediaManager.artist)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 12)
            
            // Progress details (if duration > 0)
            if mediaManager.duration > 0 {
                Text(formatTime(mediaManager.currentProgress) + " / " + formatTime(mediaManager.duration))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Controls
            HStack(spacing: 8) {
                Button(action: { mediaManager.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button(action: { mediaManager.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 26, height: 26)
                        Image(systemName: mediaManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: { mediaManager.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                
                // Thin progress track at the bottom
                if mediaManager.duration > 0 {
                    let progressFraction = CGFloat(mediaManager.currentProgress / mediaManager.duration)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue.opacity(0.85))
                            .frame(width: max(0, min(geometry.size.width, geometry.size.width * progressFraction)), height: 2)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 1)
                }
            }
        )
        .padding(.horizontal, 20)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds > 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
