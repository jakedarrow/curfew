import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    public static private(set) weak var shared: AppDelegate?
    
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    
    private var statusAndCurfewMenuItem: NSMenuItem!
    private var taskCompleteMenuItem: NSMenuItem!
    private var emergencyResolvedMenuItem: NSMenuItem!
    private var sandboxPreviewMenuItem: NSMenuItem!
    private var untimedDevTestMenuItem: NSMenuItem!
    private var timedDevTestMenuItem: NSMenuItem!
    private var preLockWarningTestMenuItem: NSMenuItem!
    private var fastCountdownTestMenuItem: NSMenuItem!
    private var emergencyUnlockMenuItem: NSMenuItem!
    
    private var isSimulatingCurfew: Bool = false
    private var isCurfewManuallySuppressed: Bool = false
    private var testModeDuration: Int? = nil // nil = untimed
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Curfew")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
        }
        
        isSimulatingCurfew = Config.debugForceCurfewActive
        
        buildMenu()
        setupApplicationMainMenu()
        
        // Start Safety Bypass Manager (Carbon global hotkeys, hot corner, file watcher)
        SafetyBypassManager.shared.start()
        SafetyBypassManager.shared.onEmergencyUnlock = { [weak self] source in
            self?.emergencyUnlockTriggered(source: source)
        }
        
        // Start Tracker & Local Bridge
        AppTracker.shared.start()
        LocalBridgeServer.shared.start()
        WiFiTracker.shared.refresh()
        
        // App Change & Screen-Time Ticks
        AppTracker.shared.onAppChanged = { [weak self] _ in
            self?.updateMenuState()
        }
        
        AppTracker.shared.onActiveTimeTick = { [weak self] _, _ in
            self?.updateMenuState()
        }
        
        // Pre-Lock Warning Event
        AppTracker.shared.onPreLockWarning = { [weak self] minutesLeft in
            FloatingHUDController.shared.showPreLockWarning(minutesRemaining: minutesLeft)
            self?.updateMenuState()
        }
        
        AppTracker.shared.onSystemWoke = { [weak self] in
            // Clear manual suppression on wake-up
            self?.isCurfewManuallySuppressed = false
            WiFiTracker.shared.refresh()
            self?.updateMenuState()
        }
        
        // Timed Focus Chime
        ChimeTimerManager.shared.onTick = { [weak self] seconds in
            FloatingHUDController.shared.updateTime(seconds: seconds)
            self?.updateMenuState()
        }
        
        ChimeTimerManager.shared.onSessionEnded = { [weak self] in
            FloatingHUDController.shared.hide()
            StorageManager.shared.update { state in
                state.focusModeActive = false
            }
            self?.updateMenuState()
        }
        
        ChimeTimerManager.shared.onSessionExpired = { [weak self] _ in
            FloatingHUDController.shared.hide()
            StorageManager.shared.update { state in
                state.focusModeActive = false
            }
            self?.updateMenuState()
        }
        
        // HUD Actions
        FloatingHUDController.shared.onTaskCompleteClicked = { [weak self] in
            self?.taskCompleteAction()
        }
        
        FloatingHUDController.shared.onEmergencyResolveClicked = { [weak self] in
            self?.emergencyResolvedAction()
        }
        
        // Curfew In-Card Callbacks
        CurfewLockScreenController.shared.onRequestApproved = { [weak self] result in
            let secs = result.grantedSeconds > 0 ? result.grantedSeconds : result.grantedMinutes * 60
            CurfewLockScreenController.shared.unlockAllScreens()
            ChimeTimerManager.shared.startSession(seconds: secs, taskName: result.taskTitle)
            FloatingHUDController.shared.show(taskName: result.taskTitle, initialSeconds: secs)
            
            StorageManager.shared.update { s in
                s.focusModeActive = true
                s.currentSessionName = result.taskTitle
                s.consecutiveBypassesTonight += 1
            }
            self?.updateMenuState()
        }
        
        CurfewLockScreenController.shared.onEmergencyApproved = { [weak self] reason in
            EmergencySMSBridge.shared.sendEmergencyAlert(reason: reason)
            CurfewLockScreenController.shared.unlockAllScreens()
            
            FloatingHUDController.shared.showEmergency(reason: reason)
            
            StorageManager.shared.update { s in
                s.focusModeActive = true
                s.currentSessionName = "Emergency Override: \(reason)"
            }
            self?.updateMenuState()
        }
        
        CurfewLockScreenController.shared.onExitTestModeRequested = { [weak self] in
            self?.isSimulatingCurfew = false
            self?.testModeDuration = nil
            self?.isCurfewManuallySuppressed = true
            CurfewLockScreenController.shared.unlockAllScreens()
            self?.updateMenuState()
        }
        
        updateMenuState()
    }
    
    private func buildMenu() {
        statusMenu = NSMenu()
        
        // Unified Status & Curfew Line
        statusAndCurfewMenuItem = NSMenuItem(title: "Unrestricted • Curfew at 10:00 PM", action: nil, keyEquivalent: "")
        statusAndCurfewMenuItem.isEnabled = false
        statusMenu.addItem(statusAndCurfewMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Task Complete (Visible during active timed session)
        taskCompleteMenuItem = NSMenuItem(title: "Task Complete (Lock Screen)", action: #selector(taskCompleteAction), keyEquivalent: "d")
        taskCompleteMenuItem.target = self
        taskCompleteMenuItem.isHidden = true
        statusMenu.addItem(taskCompleteMenuItem)
        
        // Emergency Resolved (Visible when emergency override is active)
        emergencyResolvedMenuItem = NSMenuItem(title: "Resolve Emergency (Lock Screen)", action: #selector(emergencyResolvedAction), keyEquivalent: "e")
        emergencyResolvedMenuItem.target = self
        emergencyResolvedMenuItem.isHidden = true
        statusMenu.addItem(emergencyResolvedMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // 1. Zero-Risk Windowed Sandbox Preview
        sandboxPreviewMenuItem = NSMenuItem(title: "Preview Curfew in Window (Safe Sandbox)", action: #selector(openSandboxPreview), keyEquivalent: "p")
        sandboxPreviewMenuItem.target = self
        statusMenu.addItem(sandboxPreviewMenuItem)
        
        // 2. Developer Full Screen Test Modes (Untimed & 5-Minute)
        untimedDevTestMenuItem = NSMenuItem(title: "Simulate Bedtime Curfew (Untimed Test Mode)", action: #selector(toggleUntimedDevTestMode), keyEquivalent: "t")
        untimedDevTestMenuItem.target = self
        statusMenu.addItem(untimedDevTestMenuItem)
        
        timedDevTestMenuItem = NSMenuItem(title: "Simulate Bedtime Curfew (5-Minute Test Mode)", action: #selector(toggle5MinDevTestMode), keyEquivalent: "T")
        timedDevTestMenuItem.target = self
        statusMenu.addItem(timedDevTestMenuItem)
        
        // 3. Simulate Pre-Lock Warning Banner
        preLockWarningTestMenuItem = NSMenuItem(title: "Simulate Pre-Curfew Warning (1m Banner)", action: #selector(simulatePreLockWarningAction), keyEquivalent: "w")
        preLockWarningTestMenuItem.target = self
        statusMenu.addItem(preLockWarningTestMenuItem)
        
        // 4. Fast 10-Second Countdown Expiry Test
        fastCountdownTestMenuItem = NSMenuItem(title: "Start 10-Second Expiry Test", action: #selector(startFastCountdownTest), keyEquivalent: "")
        fastCountdownTestMenuItem.target = self
        statusMenu.addItem(fastCountdownTestMenuItem)
        
        // 5. Emergency Failsafe Unlock / Reset
        emergencyUnlockMenuItem = NSMenuItem(title: "Emergency Unlock / Safety Reset", action: #selector(manualEmergencyUnlockAction), keyEquivalent: "\u{1b}")
        emergencyUnlockMenuItem.keyEquivalentModifierMask = [.command, .shift]
        emergencyUnlockMenuItem.target = self
        statusMenu.addItem(emergencyUnlockMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Curfew", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
        
        statusItem.menu = statusMenu
    }
    
    private func setupApplicationMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Curfew", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Curfew", action: #selector(quitApp), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit Menu (Essential for standard Cocoa editing: Cmd+A, Cmd+C, Cmd+V, Cmd+X, Cmd+Z)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    func updateMenuState() {
        let chime = ChimeTimerManager.shared
        let state = StorageManager.shared.state
        let isEmergencyActive = state.focusModeActive && state.currentSessionName.starts(with: "Emergency Override")
        
        // Determine Curfew Window (10:00 PM to 5:00 AM on Weeknights)
        let hour = Calendar.current.component(.hour, from: Date())
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        let isWeeknight = !isWeekend
        let realCurfew = isWeeknight && (hour >= Config.weeknightBedtimeStartHour || hour < Config.weeknightBedtimeEndHour)
        
        // Avoid infinite re-lock loop if curfew was manually suppressed by emergency override or test exit
        let isCurfew = (realCurfew && !isCurfewManuallySuppressed) || isSimulatingCurfew
        
        let curfewHourFormatted = Config.weeknightBedtimeStartHour > 12 ? "\(Config.weeknightBedtimeStartHour - 12):00 PM" : "\(Config.weeknightBedtimeStartHour):00 AM"
        
        // Global Lock Screen Overlay Controller
        if isCurfew && !chime.isSessionActive && !isEmergencyActive {
            CurfewLockScreenController.shared.lockAllScreens(isTestMode: isSimulatingCurfew, autoDismissSeconds: testModeDuration)
        } else if !CurfewLockScreenController.shared.isPreviewMode {
            CurfewLockScreenController.shared.unlockAllScreens()
        }
        
        // Top Bar Icon / Text (Native SF Symbols)
        if isEmergencyActive {
            let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Emergency")
            img?.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.title = " Emergency"
        } else if chime.isSessionActive {
            let mins = chime.secondsRemaining / 60
            let secs = chime.secondsRemaining % 60
            let timeStr = String(format: "%02d:%02d", mins, secs)
            let img = NSImage(systemSymbolName: "timer", accessibilityDescription: "Active Focus Task")
            img?.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.title = " \(timeStr)"
        } else if isCurfew {
            let img = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: "Curfew Active")
            img?.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = isSimulatingCurfew ? .imageLeading : .imageOnly
            statusItem.button?.title = isSimulatingCurfew ? " Test" : ""
        } else {
            let img = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Curfew")
            img?.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.title = ""
        }
        

        
        // Attributed Status Line
        if isEmergencyActive {
            let text = "Emergency Override Active"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemRed
            ]
            statusAndCurfewMenuItem.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else if chime.isSessionActive {
            let mins = chime.secondsRemaining / 60
            let secs = chime.secondsRemaining % 60
            let timeStr = String(format: "%02d:%02d", mins, secs)
            let text = "Active Task: \"\(chime.currentTaskName)\" (\(timeStr) left)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.systemBlue
            ]
            statusAndCurfewMenuItem.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else if isCurfew {
            let text = isSimulatingCurfew ? "Bedtime Curfew Active (Dry Run 20s Test)" : "Bedtime Curfew Active (Until 5:00 AM)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: isSimulatingCurfew ? NSColor.systemYellow : NSColor.systemRed
            ]
            statusAndCurfewMenuItem.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else if isWeekend {
            let text = "Weekend Mode (Unrestricted)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
            statusAndCurfewMenuItem.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else {
            let text = isCurfewManuallySuppressed ? "Curfew Manually Unlocked Tonight" : "Unrestricted • Curfew at \(curfewHourFormatted)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: isCurfewManuallySuppressed ? NSColor.systemOrange : NSColor.labelColor
            ]
            statusAndCurfewMenuItem.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        }
        
        untimedDevTestMenuItem.state = (isSimulatingCurfew && testModeDuration == nil) ? .on : .off
        timedDevTestMenuItem.state = (isSimulatingCurfew && testModeDuration != nil) ? .on : .off
        
        // Context-sensitive actions
        emergencyResolvedMenuItem.isHidden = !isEmergencyActive
        taskCompleteMenuItem.isHidden = !chime.isSessionActive
    }
    
    // MARK: - Actions
    @objc private func openSandboxPreview() {
        CurfewLockScreenController.shared.showWindowedPreview()
    }
    
    @objc private func toggleUntimedDevTestMode() {
        isCurfewManuallySuppressed = false
        if isSimulatingCurfew && testModeDuration == nil {
            isSimulatingCurfew = false
            testModeDuration = nil
        } else {
            isSimulatingCurfew = true
            testModeDuration = nil
        }
        updateMenuState()
    }
    
    @objc private func toggle5MinDevTestMode() {
        isCurfewManuallySuppressed = false
        if isSimulatingCurfew && testModeDuration != nil {
            isSimulatingCurfew = false
            testModeDuration = nil
        } else {
            isSimulatingCurfew = true
            testModeDuration = 300 // 5 minutes
        }
        updateMenuState()
    }
    
    @objc private func simulatePreLockWarningAction() {
        FloatingHUDController.shared.showPreLockWarning(minutesRemaining: 1)
    }
    
    @objc private func startFastCountdownTest() {
        let task = "10s Expiry Test"
        CurfewLockScreenController.shared.unlockAllScreens()
        ChimeTimerManager.shared.startSession(seconds: 10, taskName: task)
        FloatingHUDController.shared.show(taskName: task, initialSeconds: 10)
        StorageManager.shared.update { s in
            s.focusModeActive = true
            s.currentSessionName = task
        }
        updateMenuState()
    }
    
    @objc private func manualEmergencyUnlockAction() {
        emergencyUnlockTriggered(source: "Menu Bar Emergency Unlock Action")
    }
    
    private func emergencyUnlockTriggered(source: String) {
        print("[AppDelegate] Emergency unlock handled from: \(source)")
        isSimulatingCurfew = false
        isCurfewManuallySuppressed = true
        CurfewLockScreenController.shared.emergencyUnlock()
        FloatingHUDController.shared.hide()
        updateMenuState()
    }
    
    @objc private func taskCompleteAction() {
        FloatingHUDController.shared.hide()
        ChimeTimerManager.shared.markDoneEarly()
        StorageManager.shared.update { s in
            s.focusModeActive = false
        }
        updateMenuState()
    }
    
    @objc private func emergencyResolvedAction() {
        FloatingHUDController.shared.hide()
        StorageManager.shared.update { s in
            s.focusModeActive = false
            s.currentSessionName = "Deep Focus"
        }
        updateMenuState()
    }
    
    @objc private func quitApp() {
        SafetyBypassManager.shared.stop()
        CurfewLockScreenController.shared.unlockAllScreens()
        NSApplication.shared.terminate(nil)
    }
}

// Entry Point
@MainActor
func runMain() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

runMain()
