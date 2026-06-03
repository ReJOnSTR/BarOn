import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var notchPanelController: NotchPanelController?
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - this is a utility/overlay app
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar item
        setupStatusBarItem()
        
        // Initialize the notch panel
        notchPanelController = NotchPanelController()
        notchPanelController?.showPanel()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        notchPanelController?.closePanel()
    }
    
    // MARK: - Status Bar
    
    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "BarOn")
            button.image?.size = NSSize(width: 18, height: 18)
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "BarOn", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
