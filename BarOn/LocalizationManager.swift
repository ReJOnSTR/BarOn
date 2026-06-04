import SwiftUI
import Combine

// MARK: - Supported Languages
enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr"
    case english = "en"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }
    
    var flag: String {
        switch self {
        case .turkish: return "🇹🇷"
        case .english: return "🇬🇧"
        }
    }
}

// MARK: - Localization Keys
enum L10nKey: String {
    // Clipboard alert
    case copied
    
    // Settings
    case clipboardTracking
    case quit
    case settings
    case pin
    case language
    
    // Filters
    case filterAll
    case filterText
    case filterImage
    case filterLink
    case filterColor
    case filterFavorites
    
    // Search
    case searchPlaceholder
    
    // Empty states
    case emptyFavorites
    case emptyHistory
    case noResults
    
    // Card labels
    case imageClipboard
    case colorLabel
    case linkLabel
    case system
    
    // Tooltips
    case openInBrowser
    case addToFavorites
    case removeFromFavorites
    case deleteFromHistory
    
    // Media Player
    case mediaControls
    case noActiveMedia
}

// MARK: - Localization Manager
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }
    
    private let translations: [AppLanguage: [L10nKey: String]] = [
        .turkish: [
            .copied: "Kopyalandı",
            .clipboardTracking: "Pano Takibi",
            .quit: "Çıkış",
            .settings: "Ayarlar",
            .pin: "Sabitle",
            .language: "Dil",
            .filterAll: "Tümü",
            .filterText: "Metin",
            .filterImage: "Görsel",
            .filterLink: "Bağlantı",
            .filterColor: "Renk",
            .filterFavorites: "Favoriler",
            .searchPlaceholder: "Geçmişte ara...",
            .emptyFavorites: "Henüz favori öge yok.",
            .emptyHistory: "Pano geçmişi boş.",
            .noResults: "Sonuç bulunamadı.",
            .imageClipboard: "Görsel Pano",
            .colorLabel: "Renk",
            .linkLabel: "Link",
            .system: "Sistem",
            .openInBrowser: "Tarayıcıda Aç",
            .addToFavorites: "Favorilere Ekle",
            .removeFromFavorites: "Favorilerden Çıkar",
            .deleteFromHistory: "Geçmişten Sil",
            .mediaControls: "Medya Denetimi",
            .noActiveMedia: "Çalan Medya Yok",
        ],
        .english: [
            .copied: "Copied",
            .clipboardTracking: "Clipboard Tracking",
            .quit: "Quit",
            .settings: "Settings",
            .pin: "Pin",
            .language: "Language",
            .filterAll: "All",
            .filterText: "Text",
            .filterImage: "Image",
            .filterLink: "Link",
            .filterColor: "Color",
            .filterFavorites: "Favorites",
            .searchPlaceholder: "Search history...",
            .emptyFavorites: "No favorites yet.",
            .emptyHistory: "Clipboard history is empty.",
            .noResults: "No results found.",
            .imageClipboard: "Image Clipboard",
            .colorLabel: "Color",
            .linkLabel: "Link",
            .system: "System",
            .openInBrowser: "Open in Browser",
            .addToFavorites: "Add to Favorites",
            .removeFromFavorites: "Remove from Favorites",
            .deleteFromHistory: "Delete from History",
            .mediaControls: "Media Controls",
            .noActiveMedia: "No Active Media",
        ]
    ]
    
    private init() {
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "tr"
        self.currentLanguage = AppLanguage(rawValue: savedLang) ?? .turkish
    }
    
    func string(_ key: L10nKey) -> String {
        return translations[currentLanguage]?[key] ?? translations[.turkish]?[key] ?? key.rawValue
    }
    
    /// Shorthand subscript
    subscript(_ key: L10nKey) -> String {
        return string(key)
    }
}
