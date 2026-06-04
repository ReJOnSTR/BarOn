import Foundation
import Cocoa
import Combine

class SystemMediaManager: ObservableObject {
    static let shared = SystemMediaManager()
    
    // Function type definitions
    private typealias RegisterFunc = @convention(c) (DispatchQueue) -> Void
    private typealias GetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias SendCommandFunc = @convention(c) (Int32, CFDictionary?) -> Bool
    
    private var registerForNotifications: RegisterFunc?
    private var getNowPlayingInfo: GetNowPlayingInfoFunc?
    private var sendCommandFunc: SendCommandFunc?
    
    // Published properties for UI binding
    @Published var isPlaying: Bool = false
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var duration: Double = 0
    @Published var lastElapsedTime: Double = 0
    @Published var lastProgressUpdated: Date?
    @Published var playbackRate: Double = 0
    @Published var artwork: NSImage?
    @Published var clientBundleId: String?
    @Published var clientName: String?
    
    private var refreshTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadMediaRemote()
        setupNotificationObservers()
        fetchNowPlayingInfo()
    }
    
    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundleURL = URL(string: "file://\(path)"),
              let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) else {
            print("MediaRemote: Failed to load framework bundle")
            return
        }
        
        if let regPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            self.registerForNotifications = unsafeBitCast(regPointer, to: RegisterFunc.self)
        }
        
        if let infoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            self.getNowPlayingInfo = unsafeBitCast(infoPointer, to: GetNowPlayingInfoFunc.self)
        }
        
        if let cmdPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            self.sendCommandFunc = unsafeBitCast(cmdPointer, to: SendCommandFunc.self)
        }
        
        // Register for notification updates
        registerForNotifications?(DispatchQueue.main)
    }
    
    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        
        // Notification for info changes (title, artist, album, artwork, etc.)
        center.publisher(for: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo()
            }
            .store(in: &cancellables)
        
        // Notification for playback state changes (play, pause, stop)
        center.publisher(for: NSNotification.Name("kMRMediaRemotePlaybackStateDidChangeNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchNowPlayingInfo()
            }
            .store(in: &cancellables)
    }
    
    func fetchNowPlayingInfo() {
        guard let getNowPlayingInfo = getNowPlayingInfo else { return }
        
        getNowPlayingInfo(DispatchQueue.main) { [weak self] infoCF in
            guard let self = self else { return }
            guard let info = infoCF as? [String: Any] else {
                // Clear media info if nothing is playing
                self.clearMediaInfo()
                return
            }
            
            // Extract title and artist
            let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let newArtist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let newAlbum = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            
            // If we have no title, we assume nothing active is playing
            if newTitle.isEmpty && newArtist.isEmpty {
                self.clearMediaInfo()
                return
            }
            
            self.title = newTitle
            self.artist = newArtist
            self.album = newAlbum
            
            // Playback duration and elapsed time
            self.duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
            self.lastElapsedTime = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
            self.playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            self.isPlaying = self.playbackRate > 0
            self.lastProgressUpdated = Date()
            
            // Client (App) details
            if let clientBundleId = info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String {
                self.clientBundleId = clientBundleId
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clientBundleId) {
                    let appName = FileManager.default.displayName(atPath: url.path)
                    self.clientName = appName.replacingOccurrences(of: ".app", with: "")
                } else {
                    self.clientName = nil
                }
            } else {
                self.clientBundleId = nil
                self.clientName = nil
            }
            
            // Extract artwork
            if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                self.artwork = NSImage(data: artworkData)
            } else {
                self.artwork = nil
            }
            
            // Start/Stop timer for visual progress bar update
            if self.isPlaying {
                self.startRefreshTimer()
            } else {
                self.stopRefreshTimer()
            }
        }
    }
    
    private func clearMediaInfo() {
        self.isPlaying = false
        self.title = ""
        self.artist = ""
        self.album = ""
        self.duration = 0
        self.lastElapsedTime = 0
        self.lastProgressUpdated = nil
        self.playbackRate = 0
        self.artwork = nil
        self.clientBundleId = nil
        self.clientName = nil
        self.stopRefreshTimer()
    }
    
    // MARK: - Progress Tracker
    
    var currentProgress: Double {
        guard let lastUpdated = lastProgressUpdated, isPlaying && duration > 0 else {
            return lastElapsedTime
        }
        let elapsedSinceUpdate = Date().timeIntervalSince(lastUpdated)
        return min(duration, lastElapsedTime + elapsedSinceUpdate)
    }
    
    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Force UI update trigger
                self?.objectWillChange.send()
            }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }
    
    // MARK: - Playback Control Commands
    
    func togglePlayPause() {
        // Toggle command: 2
        sendCommand(2)
    }
    
    func play() {
        // Play command: 0
        sendCommand(0)
    }
    
    func pause() {
        // Pause command: 1
        sendCommand(1)
    }
    
    func next() {
        // Next track command: 4
        sendCommand(4)
    }
    
    func previous() {
        // Previous track command: 5
        sendCommand(5)
    }
    
    private func sendCommand(_ command: Int32) {
        guard let sendCommandFunc = sendCommandFunc else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = sendCommandFunc(command, nil)
            print("MediaRemote: Sent command \(command), success: \(success)")
            
            // Slight delay then re-fetch info to synchronize UI state immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.fetchNowPlayingInfo()
            }
        }
    }
}
