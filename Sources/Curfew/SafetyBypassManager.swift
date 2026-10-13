import Cocoa
import Carbon

public extension Notification.Name {
    static let sstEmergencyUnlockTriggered = Notification.Name("sstEmergencyUnlockTriggered")
}

/// Foolproof developer safety architecture providing multiple redundant fail-safe bypasses
/// to ensure the lock overlay can NEVER trap or lock out the machine.
@MainActor
public final class SafetyBypassManager: NSObject {
    public static let shared = SafetyBypassManager()
    
    public var onEmergencyUnlock: ((_ source: String) -> Void)?
    
    // Carbon OS-Level Global Hotkeys (work without Accessibility permissions)
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    
    // Mouse Hot Corner Detection
    private var hotCornerTimer: Timer?
    private var hotCornerDwellSeconds: Double = 0.0
    private let hotCornerThresholdSeconds: Double = 1.5
    
    // File-based Lifeline Watcher (/tmp/sst_unlock)
    private var fileWatchTimer: Timer?
    public let bypassFilePath = "/tmp/sst_unlock"
    
    // Local Key Monitor
    private var localKeyMonitor: Any?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Lifecycle
    public func start() {
        registerCarbonGlobalHotkeys()
        setupNotificationObserver()
        startFileWatchTimer()
        setupLocalKeyMonitor()
    }
    
    public func stop() {
        unregisterCarbonGlobalHotkeys()
        stopHotCornerMonitor()
        stopFileWatchTimer()
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    // MARK: - Active Monitoring for Overlays
    /// Call when an overlay window is presented to engage high-frequency hot corner monitoring.
    public func startActiveOverlayMonitoring() {
        startHotCornerMonitor()
        // Ensure file watcher is running actively
        checkFileBypass()
    }
    
    /// Call when overlay is dismissed to conserve resources.
    public func stopActiveOverlayMonitoring() {
        stopHotCornerMonitor()
        hotCornerDwellSeconds = 0.0
    }
    
    // MARK: - 1. Carbon Global Hotkeys (Bypasses TCC / Accessibility)
    private func registerCarbonGlobalHotkeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, theEvent, _) -> OSStatus in
                // Dispatches safely to main runloop
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .sstEmergencyUnlockTriggered,
                        object: "Carbon Global Hotkey (Cmd+Shift+Esc / Ctrl+Opt+Cmd+Esc)"
                    )
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        
        if status != noErr {
            print("[SafetyBypassManager] Warning: InstallEventHandler failed with status \(status)")
        }
        
        // Hotkey 1: Cmd + Shift + Escape (Universal Developer Bypass)
        var hotKey1: EventHotKeyRef?
        let id1 = EventHotKeyID(signature: OSType(0x53535431), id: 1) // SST1
        let reg1 = RegisterEventHotKey(
            UInt32(kVK_Escape),
            UInt32(cmdKey | shiftKey),
            id1,
            GetApplicationEventTarget(),
            0,
            &hotKey1
        )
        if reg1 == noErr, let ref = hotKey1 {
            hotKeyRefs.append(ref)
            print("[SafetyBypassManager] Registered Carbon Hotkey: Cmd + Shift + Esc")
        }
        
        // Hotkey 2: Ctrl + Opt + Cmd + Escape (Nuclear Safety Override)
        var hotKey2: EventHotKeyRef?
        let id2 = EventHotKeyID(signature: OSType(0x53535432), id: 2) // SST2
        let reg2 = RegisterEventHotKey(
            UInt32(kVK_Escape),
            UInt32(controlKey | optionKey | cmdKey),
            id2,
            GetApplicationEventTarget(),
            0,
            &hotKey2
        )
        if reg2 == noErr, let ref = hotKey2 {
            hotKeyRefs.append(ref)
            print("[SafetyBypassManager] Registered Carbon Hotkey: Ctrl + Opt + Cmd + Esc")
        }
    }
    
    private func unregisterCarbonGlobalHotkeys() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
    
    // MARK: - 2. Mouse Hot Corner Trigger
    /// Holding cursor in the top-left corner of the primary display for 1.5 seconds triggers failsafe unlock.
    private func startHotCornerMonitor() {
        stopHotCornerMonitor()
        hotCornerDwellSeconds = 0.0
        
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.checkHotCorner()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.hotCornerTimer = timer
    }
    
    private func stopHotCornerMonitor() {
        hotCornerTimer?.invalidate()
        hotCornerTimer = nil
    }
    
    private func checkHotCorner() {
        guard let screen = NSScreen.screens.first else { return }
        let mouseLoc = NSEvent.mouseLocation
        let frame = screen.frame
        
        // Top-left corner box (15x15 pt)
        let isTopLeft = (mouseLoc.x <= frame.minX + 15) && (mouseLoc.y >= frame.maxY - 15)
        // Top-right corner box (15x15 pt)
        let isTopRight = (mouseLoc.x >= frame.maxX - 15) && (mouseLoc.y >= frame.maxY - 15)
        
        if isTopLeft || isTopRight {
            hotCornerDwellSeconds += 0.2
            if hotCornerDwellSeconds >= hotCornerThresholdSeconds {
                hotCornerDwellSeconds = 0.0
                triggerEmergencyUnlock(source: "Mouse Hot Corner (Top-\(isTopLeft ? "Left" : "Right") Corner Dwell)")
            }
        } else {
            hotCornerDwellSeconds = 0.0
        }
    }
    
    // MARK: - 3. File Watcher Lifeline (/tmp/sst_unlock)
    /// Touching /tmp/sst_unlock via terminal or script instantly unlocks the system.
    private func startFileWatchTimer() {
        stopFileWatchTimer()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFileBypass()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.fileWatchTimer = timer
    }
    
    private func stopFileWatchTimer() {
        fileWatchTimer?.invalidate()
        fileWatchTimer = nil
    }
    
    public func checkFileBypass() {
        if FileManager.default.fileExists(atPath: bypassFilePath) {
            try? FileManager.default.removeItem(atPath: bypassFilePath)
            triggerEmergencyUnlock(source: "File Lifeline (\(bypassFilePath))")
        }
    }
    
    // MARK: - 4. Local Key Event Monitor
    private func setupLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Cmd+Shift+Esc or Ctrl+Opt+Cmd+Esc
            if event.keyCode == 53 {
                let flags = event.modifierFlags
                let isCmdShift = flags.contains(.command) && flags.contains(.shift)
                let isCtrlOptCmd = flags.contains(.control) && flags.contains(.option) && flags.contains(.command)
                
                if isCmdShift || isCtrlOptCmd {
                    self.triggerEmergencyUnlock(source: "Local Key Monitor (\(isCmdShift ? "Cmd+Shift+Esc" : "Ctrl+Opt+Cmd+Esc"))")
                    return nil
                }
            }
            return event
        }
    }
    
    // MARK: - 5. Notification Dispatch
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .sstEmergencyUnlockTriggered,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let source = notification.object as? String ?? "Notification"
            Task { @MainActor [weak self] in
                self?.triggerEmergencyUnlock(source: source)
            }
        }
    }
    
    public func triggerEmergencyUnlock(source: String) {
        print("[SafetyBypassManager] 🚨 Emergency bypass triggered via: \(source)")
        onEmergencyUnlock?(source)
    }
}
