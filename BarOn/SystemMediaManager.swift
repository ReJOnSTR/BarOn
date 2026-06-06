import Foundation
import Cocoa
import Combine

class SystemMediaManager: ObservableObject {
    static let shared = SystemMediaManager()
    
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
    private var helperProcess: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?
    private var outputBuffer = ""
    
    // Helper script string using raw string literal
    private let helperScriptContent = #"""
import Foundation
import Cocoa

let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
guard let bundleURL = URL(string: "file://\(path)"),
      let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL as CFURL) else {
    print("{\"error\":\"Failed to load bundle\"}")
    fflush(stdout)
    exit(1)
}

typealias RegisterFunc = @convention(c) (DispatchQueue) -> Void
typealias GetNowPlayingInfoFunc = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
typealias SendCommandFunc = @convention(c) (Int32, CFDictionary?) -> Bool

guard let regPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString),
      let infoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
      let cmdPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
    print("{\"error\":\"Failed to load symbols\"}")
    fflush(stdout)
    exit(1)
}

let registerForNotifications = unsafeBitCast(regPointer, to: RegisterFunc.self)
let getNowPlayingInfo = unsafeBitCast(infoPointer, to: GetNowPlayingInfoFunc.self)
let sendCommandFunc = unsafeBitCast(cmdPointer, to: SendCommandFunc.self)

func fetchAndPrint() {
    getNowPlayingInfo(DispatchQueue.main) { infoCF in
        guard let info = infoCF as? [String: Any] else {
            print("DATA:{\"status\":\"empty\"}")
            fflush(stdout)
            return
        }
        
        var dict: [String: Any] = [:]
        dict["title"] = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        dict["artist"] = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        dict["album"] = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        dict["duration"] = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
        dict["elapsedTime"] = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
        dict["playbackRate"] = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
        dict["clientBundleId"] = info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? ""
        
        if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            dict["artwork"] = artworkData.base64EncodedString()
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("DATA:\(jsonString)")
            fflush(stdout)
        }
    }
}

if CommandLine.arguments.count > 1 {
    exit(0)
}

FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
        let lines = str.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("CMD:") {
                let cmdStr = trimmed.dropFirst(4)
                if let cmdVal = Int32(cmdStr) {
                    _ = sendCommandFunc(cmdVal, nil)
                }
            }
        }
    }
}

registerForNotifications(DispatchQueue.main)

NotificationCenter.default.addObserver(forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"), object: nil, queue: .main) { _ in
    fetchAndPrint()
}

NotificationCenter.default.addObserver(forName: NSNotification.Name("kMRMediaRemotePlaybackStateDidChangeNotification"), object: nil, queue: .main) { _ in
    fetchAndPrint()
}

fetchAndPrint()

let runLoop = RunLoop.current
while runLoop.run(mode: .default, before: Date.distantFuture) {
}
"""#

    private init() {
        startHelperProcess()
        setupAppLifecycleObservers()
    }
    
    deinit {
        stopHelperProcess()
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stopHelperProcess()
        }
    }
    
    private func startHelperProcess() {
        stopHelperProcess()
        
        let tempPath = NSTemporaryDirectory() + "BarOn_media_helper.swift"
        do {
            try helperScriptContent.write(toFile: tempPath, atomically: true, encoding: .utf8)
        } catch {
            print("MediaRemote: Failed to write script: \(error)"); fflush(stdout)
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [tempPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        
        self.helperProcess = process
        self.stdoutPipe = pipe
        self.stdinPipe = stdinPipe
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let str = String(data: data, encoding: .utf8) {
                self?.parseHelperOutput(str)
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            print("MediaRemote: Helper process terminated with status \(proc.terminationStatus)"); fflush(stdout)
            // Restart after 2 seconds if still running
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self?.startHelperProcess()
            }
        }
        
        do {
            try process.run()
            print("MediaRemote: Helper process started successfully"); fflush(stdout)
        } catch {
            print("MediaRemote: Failed to run helper process: \(error)"); fflush(stdout)
        }
    }
    
    private func stopHelperProcess() {
        if let process = helperProcess {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
            helperProcess = nil
        }
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stdinPipe = nil
    }
    
    private func parseHelperOutput(_ str: String) {
        outputBuffer += str
        while let newlineIndex = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            outputBuffer = String(outputBuffer[outputBuffer.index(after: newlineIndex)...])
            
            if line.hasPrefix("DATA:") {
                let jsonStr = String(line.dropFirst(5))
                if let data = jsonStr.data(using: .utf8) {
                    self.parseJSON(data)
                }
            }
        }
    }
    
    private struct MediaInfo: Codable {
        let status: String?
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let playbackRate: Double?
        let clientBundleId: String?
        let artwork: String? // base64
    }
    
    private func parseJSON(_ data: Data) {
        guard let info = try? JSONDecoder().decode(MediaInfo.self, from: data) else {
            print("MediaRemote: Failed to decode media JSON"); fflush(stdout)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if info.status == "empty" || (info.title?.isEmpty == true && info.artist?.isEmpty == true) {
                self.clearMediaInfo()
                return
            }
            
            self.title = info.title ?? ""
            self.artist = info.artist ?? ""
            self.album = info.album ?? ""
            self.duration = info.duration ?? 0
            self.lastElapsedTime = info.elapsedTime ?? 0
            self.playbackRate = info.playbackRate ?? 0
            self.isPlaying = self.playbackRate > 0
            self.lastProgressUpdated = Date()
            
            if let clientBundleId = info.clientBundleId, !clientBundleId.isEmpty {
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
            
            if let artworkBase64 = info.artwork,
               let artworkData = Data(base64Encoded: artworkBase64) {
                self.artwork = NSImage(data: artworkData)
            } else {
                self.artwork = nil
            }
            
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
        self.isPlaying.toggle()
        if self.isPlaying {
            self.startRefreshTimer()
        } else {
            self.stopRefreshTimer()
        }
        // Toggle command: 2
        sendCommand(2)
    }
    
    func play() {
        self.isPlaying = true
        self.startRefreshTimer()
        // Play command: 0
        sendCommand(0)
    }
    
    func pause() {
        self.isPlaying = false
        self.stopRefreshTimer()
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
        guard let stdinPipe = stdinPipe else {
            print("MediaRemote: Cannot send command \(command) because helper stdinPipe is nil"); fflush(stdout)
            return
        }
        let cmdStr = "CMD:\(command)\n"
        if let data = cmdStr.data(using: .utf8) {
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: data)
                print("MediaRemote: Sent command \(command) to helper stdin successfully"); fflush(stdout)
            } catch {
                print("MediaRemote: Failed to write command \(command) to helper stdin: \(error)"); fflush(stdout)
            }
        }
    }
}
