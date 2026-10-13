import Cocoa

@MainActor
public final class FloatingHUDController: NSObject {
    public static let shared = FloatingHUDController()
    
    private var window: NSPanel?
    private var visualEffect: NSVisualEffectView?
    private var primaryLabel: NSTextField?
    private var secondaryLabel: NSTextField?
    private var actionButton: NSButton?
    
    public var onTaskCompleteClicked: (() -> Void)?
    public var onEmergencyResolveClicked: (() -> Void)?
    
    private var isEmergencyMode: Bool = false
    private var isWarningMode: Bool = false
    private var warningDismissTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    public func show(taskName: String, suggestedScope: String? = nil, initialSeconds: Int) {
        isEmergencyMode = false
        isWarningMode = false
        warningDismissTimer?.invalidate()
        if window == nil {
            createWindow()
        }
        
        configureForTask(taskName: taskName, suggestedScope: suggestedScope, seconds: initialSeconds)
        presentWindow()
    }
    
    public func showEmergency(reason: String) {
        isEmergencyMode = true
        isWarningMode = false
        warningDismissTimer?.invalidate()
        if window == nil {
            createWindow()
        }
        
        configureForEmergency(reason: reason)
        presentWindow()
    }
    
    public func showPreLockWarning(minutesRemaining: Int) {
        isEmergencyMode = false
        isWarningMode = true
        warningDismissTimer?.invalidate()
        if window == nil {
            createWindow()
        }
        
        configureForPreLockWarning(minutesRemaining: minutesRemaining)
        presentWindow()
        
        let timer = Timer(timeInterval: 15.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.isWarningMode == true {
                    self?.hide()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.warningDismissTimer = timer
    }
    
    public func hide() {
        warningDismissTimer?.invalidate()
        warningDismissTimer = nil
        isWarningMode = false
        window?.orderOut(nil)
    }
    
    public func updateTime(seconds: Int) {
        guard !isEmergencyMode && !isWarningMode else { return }
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        primaryLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
    }
    
    private func presentWindow() {
        guard let win = window else { return }
        
        // Position at top center of primary display
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (win.frame.width / 2)
            let y = screenRect.maxY - win.frame.height - 12
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        win.orderFrontRegardless()
        win.makeKeyAndOrderFront(nil)
    }
    
    private func configureForTask(taskName: String, suggestedScope: String?, seconds: Int) {
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        primaryLabel?.stringValue = String(format: "%02d:%02d", mins, secs)
        primaryLabel?.textColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 1.0)
        
        var displayTitle = taskName
        if let scope = suggestedScope?.trimmingCharacters(in: .whitespacesAndNewlines),
           !scope.isEmpty, scope.lowercased() != taskName.lowercased() {
            displayTitle = "\(taskName) • \(scope)"
        }
        
        secondaryLabel?.stringValue = displayTitle
        secondaryLabel?.toolTip = displayTitle
        secondaryLabel?.textColor = NSColor.white
        
        actionButton?.title = "Task Complete"
        actionButton?.target = self
        actionButton?.action = #selector(handleActionClicked)
        
        visualEffect?.layer?.borderColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 0.3).cgColor
    }
    
    private func configureForEmergency(reason: String) {
        primaryLabel?.stringValue = "EMERGENCY"
        primaryLabel?.textColor = NSColor(calibratedRed: 1.0, green: 0.28, blue: 0.34, alpha: 1.0)
        
        secondaryLabel?.stringValue = reason.isEmpty ? "Override Active" : reason
        secondaryLabel?.textColor = NSColor.white
        
        actionButton?.title = "Resolve Emergency"
        actionButton?.target = self
        actionButton?.action = #selector(handleActionClicked)
        
        visualEffect?.layer?.borderColor = NSColor(calibratedRed: 1.0, green: 0.28, blue: 0.34, alpha: 0.5).cgColor
    }
    
    private func configureForPreLockWarning(minutesRemaining: Int) {
        primaryLabel?.stringValue = "10:00 PM"
        primaryLabel?.textColor = NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.35, alpha: 1.0)
        
        secondaryLabel?.stringValue = "Curfew in \(minutesRemaining)m • Wrap up work"
        secondaryLabel?.textColor = NSColor.labelColor
        
        actionButton?.title = "Got It"
        actionButton?.target = self
        actionButton?.action = #selector(handleWarningDismissClicked)
        
        visualEffect?.layer?.borderColor = NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.35, alpha: 0.45).cgColor
        visualEffect?.layer?.shadowColor = NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.35, alpha: 1.0).cgColor
        visualEffect?.layer?.shadowRadius = 14
        visualEffect?.layer?.shadowOpacity = 0.35
    }
    
    private func createWindow() {
        let panelWidth: CGFloat = 460
        let panelHeight: CGFloat = 46
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        
        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 23
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        effect.layer?.borderWidth = 1.2
        panel.contentView?.addSubview(effect)
        self.visualEffect = effect
        
        // Primary Badge / Time Label
        let pLabel = NSTextField(labelWithString: "15:00")
        pLabel.frame = NSRect(x: 16, y: 12, width: 75, height: 22)
        pLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        pLabel.textColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 1.0)
        effect.addSubview(pLabel)
        self.primaryLabel = pLabel
        
        // Secondary Title / Negotiated Scope Label
        let sLabel = NSTextField(labelWithString: "Active Task")
        sLabel.frame = NSRect(x: 96, y: 12, width: 226, height: 22)
        sLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        sLabel.textColor = NSColor.white
        sLabel.lineBreakMode = .byTruncatingTail
        effect.addSubview(sLabel)
        self.secondaryLabel = sLabel
        
        // Action Button
        let btn = NSButton(title: "Task Complete", target: self, action: #selector(handleActionClicked))
        btn.frame = NSRect(x: 326, y: 8, width: 122, height: 30)
        btn.bezelStyle = .rounded
        btn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        effect.addSubview(btn)
        self.actionButton = btn
        
        self.window = panel
    }
    
    @objc private func handleActionClicked() {
        if isEmergencyMode {
            onEmergencyResolveClicked?()
        } else {
            onTaskCompleteClicked?()
        }
    }
    
    @objc private func handleWarningDismissClicked() {
        hide()
    }
}
