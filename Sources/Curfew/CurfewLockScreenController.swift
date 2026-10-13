import Cocoa

// MARK: - Refactored Keyable Lock Window
public final class KeyableLockWindow: NSWindow {
    public var isPrimaryScreen: Bool = true
    public weak var primaryWindow: NSWindow?
    
    public override var canBecomeKey: Bool {
        // Only the primary window can become key to prevent secondary screens from stealing input focus
        return isPrimaryScreen
    }
    public override var canBecomeMain: Bool {
        return isPrimaryScreen
    }
    
    public var onEscapePressed: (() -> Void)?
    public var onCommandQPressed: (() -> Void)?
    
    // Intercept standard Cocoa cancel operation (sent by text fields on Escape)
    public override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }
    
    // Intercept keyboard equivalents BEFORE text views or controls consume them
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Escape key (keyCode 53)
        if event.keyCode == 53 {
            onEscapePressed?()
            return true
        }
        // Cmd+Q
        if event.keyCode == 12 && event.modifierFlags.contains(.command) {
            onCommandQPressed?()
            return true
        }
        // Cmd+W
        if event.keyCode == 13 && event.modifierFlags.contains(.command) {
            onEscapePressed?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscapePressed?()
            return
        }
        if event.keyCode == 12 && event.modifierFlags.contains(.command) {
            onCommandQPressed?()
            return
        }
        super.keyDown(with: event)
    }
    
    // Redirect clicks on secondary display to primary interactive window
    public override func mouseDown(with event: NSEvent) {
        if !isPrimaryScreen {
            primaryWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            super.mouseDown(with: event)
        }
    }
}

// MARK: - Keyboard Navigable Controls
public final class KeyboardNavigableSegmentedControl: NSSegmentedControl {
    public weak var previousKeyTarget: NSResponder?
    public weak var nextKeyTarget: NSResponder?
    public var onReturnPressed: (() -> Void)?
    
    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.focusRingType = .none
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.focusRingType = .none
    }
    
    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            wantsLayer = true
            layer?.borderColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 1.0).cgColor
            layer?.borderWidth = 2.0
            layer?.cornerRadius = 10
            layer?.shadowColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 0.6).cgColor
            layer?.shadowRadius = 8
            layer?.shadowOpacity = 0.8
            layer?.shadowOffset = .zero
        }
        return ok
    }
    
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
            layer?.borderWidth = 1.0
            layer?.shadowOpacity = 0.0
            layer?.shadowRadius = 0
        }
        return ok
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { // Tab
            if event.modifierFlags.contains(.shift) {
                if let prev = previousKeyTarget, let win = window {
                    win.makeFirstResponder(prev)
                    return
                }
            } else {
                if let next = nextKeyTarget, let win = window {
                    win.makeFirstResponder(next)
                    return
                }
            }
        } else if event.keyCode == 123 || event.keyCode == 126 { // Left or Up Arrow
            selectedSegment = max(0, selectedSegment - 1)
            sendAction(action, to: target)
            return
        } else if event.keyCode == 124 || event.keyCode == 125 { // Right or Down Arrow
            selectedSegment = min(segmentCount - 1, selectedSegment + 1)
            sendAction(action, to: target)
            return
        } else if let chars = event.characters, chars == "1" {
            if segmentCount > 0 { selectedSegment = 0; sendAction(action, to: target) }
            return
        } else if let chars = event.characters, chars == "2" {
            if segmentCount > 1 { selectedSegment = 1; sendAction(action, to: target) }
            return
        } else if let chars = event.characters, chars == "3" {
            if segmentCount > 2 { selectedSegment = 2; sendAction(action, to: target) }
            return
        } else if let chars = event.characters, chars == "4" {
            if segmentCount > 3 { selectedSegment = 3; sendAction(action, to: target) }
            return
        } else if event.keyCode == 36 { // Return
            onReturnPressed?()
            return
        }
        super.keyDown(with: event)
    }
}

public final class KeyboardNavigableButton: NSButton {
    public weak var previousKeyTarget: NSResponder?
    public weak var nextKeyTarget: NSResponder?
    public var customAction: (() -> Void)?
    
    public var normalBorderColor: CGColor?
    public var normalBorderWidth: CGFloat = 1.0
    
    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.focusRingType = .none
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.focusRingType = .none
    }
    
    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            updateFocusVisuals(isFocused: true)
        }
        return ok
    }
    
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            updateFocusVisuals(isFocused: false)
        }
        return ok
    }
    
    public func updateFocusVisuals(isFocused: Bool) {
        wantsLayer = true
        if isFocused {
            if normalBorderColor == nil {
                normalBorderColor = layer?.borderColor
                normalBorderWidth = layer?.borderWidth ?? 1.0
            }
            layer?.borderColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 1.0).cgColor
            layer?.borderWidth = 2.0
            layer?.shadowColor = NSColor(calibratedRed: 0.38, green: 0.85, blue: 0.98, alpha: 0.6).cgColor
            layer?.shadowRadius = 8
            layer?.shadowOpacity = 0.8
            layer?.shadowOffset = .zero
        } else {
            layer?.borderColor = normalBorderColor ?? NSColor.white.withAlphaComponent(0.20).cgColor
            layer?.borderWidth = normalBorderWidth
            layer?.shadowOpacity = 0.0
            layer?.shadowRadius = 0
        }
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { // Tab
            if event.modifierFlags.contains(.shift) {
                if let prev = previousKeyTarget, let win = window {
                    win.makeFirstResponder(prev)
                    return
                }
            } else {
                if let next = nextKeyTarget, let win = window {
                    win.makeFirstResponder(next)
                    return
                }
            }
        } else if event.keyCode == 36 || event.keyCode == 49 { // Return or Space
            if let custom = customAction {
                custom()
            } else if let target = target, let action = action {
                NSApp.sendAction(action, to: target, from: self)
            }
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Curfew Lock Screen Controller
@MainActor
public final class CurfewLockScreenController: NSObject, NSTextFieldDelegate {
    public static let shared = CurfewLockScreenController()
    
    // Window references
    private var lockWindows: [KeyableLockWindow] = []
    private var previewWindow: KeyableLockWindow?
    private weak var primaryWindowRef: KeyableLockWindow?
    
    // Mode States
    public private(set) var isLocked: Bool = false
    public private(set) var isTestMode: Bool = false
    public private(set) var isPreviewMode: Bool = false
    
    // Card Navigation State
    private enum CardState {
        case overview
        case requestTask(task: String, consequence: String, requestedMinutes: Int)
        case evaluatingAI(task: String, consequence: String, requestedMinutes: Int, concession: String?, round: Int)
        case aiDecision(result: ArbitrationResult, originalTask: String, originalConsequence: String, requestedMinutes: Int)
        case negotiationConcession(previousResult: ArbitrationResult, originalTask: String, originalConsequence: String, requestedMinutes: Int)
        case smartNoResult(ArbitrationResult)
        case emergencyOverride
    }
    
    private var currentCardState: CardState = .overview
    private weak var primaryCardView: NSView?
    
    // Form Inputs & Buttons (Weak references to currently active card views)
    private weak var taskField: NSTextField?
    private weak var consequenceField: NSTextField?
    private weak var minutesSegmentedControl: KeyboardNavigableSegmentedControl?
    private weak var concessionField: NSTextField?
    private weak var emergencyReasonField: NSTextField?
    private weak var submitProposalButton: KeyboardNavigableButton?
    private weak var cancelProposalButton: KeyboardNavigableButton?
    private weak var submitConcessionButton: KeyboardNavigableButton?
    private weak var submitEmergencyButton: KeyboardNavigableButton?
    
    // Test Mode Auto-Dismiss Timer (runs on RunLoop .common mode; nil = untimed)
    private var testModeTimer: Timer?
    private var testModeSecondsRemaining: Int? = nil
    private weak var testModeLabel: NSTextField?
    
    // Callbacks
    public var onRequestApproved: ((_ result: ArbitrationResult) -> Void)?
    public var onEmergencyApproved: ((_ reason: String) -> Void)?
    public var onExitTestModeRequested: (() -> Void)?
    
    // MARK: - Glassmorphic Aesthetic Styling Helpers
    public static func styleCard(_ card: NSView) {
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 0.98).cgColor
        card.layer?.cornerRadius = 24
        card.layer?.cornerCurve = .continuous
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        card.layer?.borderWidth = 1.5
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.65
        card.layer?.shadowRadius = 36
    }
    
    public static func styleInputField(_ field: NSTextField) {
        field.wantsLayer = true
        field.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 0.95).cgColor
        field.layer?.cornerRadius = 10
        field.layer?.cornerCurve = .continuous
        field.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        field.layer?.borderWidth = 1.2
        field.textColor = .white
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
    }
    
    public static func stylePrimaryButton(_ button: NSButton, title: String? = nil) {
        button.wantsLayer = true
        button.focusRingType = .none
        let borderColor = NSColor.systemTeal.withAlphaComponent(0.65).cgColor
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.52, alpha: 0.50).cgColor
        button.layer?.cornerRadius = 12
        button.layer?.cornerCurve = .continuous
        button.layer?.borderColor = borderColor
        button.layer?.borderWidth = 1.5
        button.isBordered = false
        if let kb = button as? KeyboardNavigableButton {
            kb.normalBorderColor = borderColor
            kb.normalBorderWidth = 1.5
        }
        
        let t = title ?? button.title
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attr = NSAttributedString(string: t, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .paragraphStyle: pStyle
        ])
        button.attributedTitle = attr
    }
    
    public static func styleSecondaryButton(_ button: NSButton, title: String? = nil) {
        button.wantsLayer = true
        button.focusRingType = .none
        let borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        button.layer?.cornerRadius = 12
        button.layer?.cornerCurve = .continuous
        button.layer?.borderColor = borderColor
        button.layer?.borderWidth = 1.0
        button.isBordered = false
        if let kb = button as? KeyboardNavigableButton {
            kb.normalBorderColor = borderColor
            kb.normalBorderWidth = 1.0
        }
        
        let t = title ?? button.title
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attr = NSAttributedString(string: t, attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.88, alpha: 1.0),
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .paragraphStyle: pStyle
        ])
        button.attributedTitle = attr
    }
    
    public static func styleEmergencyButton(_ button: NSButton, title: String? = nil) {
        button.wantsLayer = true
        button.focusRingType = .none
        let borderColor = NSColor.systemRed.withAlphaComponent(0.70).cgColor
        button.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.22, alpha: 0.18).cgColor
        button.layer?.cornerRadius = 12
        button.layer?.cornerCurve = .continuous
        button.layer?.borderColor = borderColor
        button.layer?.borderWidth = 1.5
        button.isBordered = false
        if let kb = button as? KeyboardNavigableButton {
            kb.normalBorderColor = borderColor
            kb.normalBorderWidth = 1.5
        }
        
        let t = title ?? button.title
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attr = NSAttributedString(string: t, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .paragraphStyle: pStyle
        ])
        button.attributedTitle = attr
    }
    
    private override init() {
        super.init()
        observeScreenChanges()
    }
    
    // MARK: - Multi-Display Configuration Observer
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isLocked else { return }
                print("[CurfewLockScreenController] Screen configuration changed. Re-laying out lock windows.")
                self.relayoutLockWindows()
            }
        }
    }
    
    // MARK: - Mode 1: Windowed Preview Mode (100% Zero-Risk Sandbox)
    public func showWindowedPreview() {
        if isLocked { unlockAllScreens() }
        closePreview()
        
        isPreviewMode = true
        self.currentCardState = .overview
        
        let cardWidth: CGFloat = 580
        let cardHeight: CGFloat = 510
        let winWidth: CGFloat = 660
        let winHeight: CGFloat = 590
        
        let win = KeyableLockWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.isPrimaryScreen = true
        win.title = "Curfew Preview (Zero-Risk Safe Sandbox)"
        win.center()
        win.isReleasedWhenClosed = false
        win.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
        
        win.onEscapePressed = { [weak self] in
            guard let self = self else { return }
            self.handleWindowEscape()
        }
        
        win.onCommandQPressed = {
            NSApplication.shared.terminate(nil)
        }
        
        let container = NSView(frame: win.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(container)
        
        let card = NSView(frame: NSRect(x: (winWidth - cardWidth) / 2, y: (winHeight - cardHeight) / 2, width: cardWidth, height: cardHeight))
        Self.styleCard(card)
        container.addSubview(card)
        
        self.primaryCardView = card
        renderCurrentCardState()
        
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.previewWindow = win
    }
    
    public func closePreview() {
        isPreviewMode = false
        previewWindow?.close()
        previewWindow = nil
    }
    
    // MARK: - Mode 2 & 3: Full Screen Lock Mode
    public func lockAllScreens(isTestMode: Bool = false, autoDismissSeconds: Int? = nil) {
        guard !isLocked else { return }
        closePreview()
        
        self.isLocked = true
        self.isTestMode = isTestMode
        self.testModeSecondsRemaining = autoDismissSeconds
        self.currentCardState = .overview
        
        dismissAllWindows()
        buildLockWindows()
        
        NSApp.activate(ignoringOtherApps: true)
        
        if isTestMode {
            startTestModeSafetyTimer(autoDismissSeconds: autoDismissSeconds)
            SafetyBypassManager.shared.startActiveOverlayMonitoring()
        }
    }
    
    public func unlockAllScreens() {
        guard isLocked || isPreviewMode else { return }
        self.isLocked = false
        self.isTestMode = false
        closePreview()
        stopTestModeSafetyTimer()
        SafetyBypassManager.shared.stopActiveOverlayMonitoring()
        dismissAllWindows()
    }
    
    public func emergencyUnlock() {
        print("[CurfewLockScreenController] Emergency unlock executing.")
        unlockAllScreens()
        onExitTestModeRequested?()
    }
    
    private func relayoutLockWindows() {
        let currentTestMode = self.isTestMode
        let currentAutoDismiss = self.testModeSecondsRemaining
        let currentState = self.currentCardState
        dismissAllWindows()
        self.isTestMode = currentTestMode
        self.testModeSecondsRemaining = currentAutoDismiss
        self.currentCardState = currentState
        buildLockWindows()
        if currentTestMode {
            startTestModeSafetyTimer(autoDismissSeconds: currentAutoDismiss)
        }
    }
    
    private func buildLockWindows() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // Find primary screen (containing origin 0,0 or first screen)
        let primaryScreen = screens.first(where: { $0.frame.origin == .zero }) ?? screens[0]
        
        // First create primary window
        let primaryWin = createLockWindow(for: primaryScreen, isPrimary: true)
        lockWindows.append(primaryWin)
        self.primaryWindowRef = primaryWin
        
        // Then create secondary backdrop windows
        for screen in screens where screen != primaryScreen {
            let secWin = createLockWindow(for: screen, isPrimary: false)
            secWin.primaryWindow = primaryWin
            lockWindows.append(secWin)
        }
        
        // Order windows
        for win in lockWindows {
            win.orderFrontRegardless()
        }
        primaryWin.makeKeyAndOrderFront(nil)
    }
    
    private func dismissAllWindows() {
        stopTestModeSafetyTimer()
        for win in lockWindows {
            win.orderOut(nil)
        }
        lockWindows.removeAll()
        primaryWindowRef = nil
        primaryCardView = nil
    }
    
    // MARK: - Test Mode Auto-Dismiss Timer (.common RunLoop Mode)
    private func startTestModeSafetyTimer(autoDismissSeconds: Int?) {
        stopTestModeSafetyTimer()
        testModeSecondsRemaining = autoDismissSeconds
        updateTestModeLabelText()
        
        guard let seconds = autoDismissSeconds, seconds > 0 else {
            // Untimed test mode: No auto-dismiss timer! Stays active until user exits manually
            return
        }
        
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let remaining = self.testModeSecondsRemaining else { return }
                let next = remaining - 1
                self.testModeSecondsRemaining = next
                self.updateTestModeLabelText()
                if next <= 0 {
                    print("[CurfewLockScreenController] Test mode auto-dismiss safety timer expired. Unlocking.")
                    self.stopTestModeSafetyTimer()
                    self.unlockAllScreens()
                    self.onExitTestModeRequested?()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.testModeTimer = timer
    }
    
    private func stopTestModeSafetyTimer() {
        testModeTimer?.invalidate()
        testModeTimer = nil
    }
    
    private func updateTestModeLabelText() {
        guard isTestMode else { return }
        if let remaining = testModeSecondsRemaining {
            testModeLabel?.stringValue = "Test Mode (Auto-unlocks in \(remaining)s) • Esc to Exit"
        } else {
            testModeLabel?.stringValue = "Test Mode (Untimed) • Press Esc or Click to Exit"
        }
    }
    
    // MARK: - Window Creation Factory
    private func createLockWindow(for screen: NSScreen, isPrimary: Bool) -> KeyableLockWindow {
        let frame = screen.frame
        let window = KeyableLockWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.isPrimaryScreen = isPrimary
        window.level = isTestMode ? .floating : .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        
        window.onEscapePressed = { [weak self] in
            guard let self = self else { return }
            self.handleWindowEscape()
        }
        
        window.onCommandQPressed = {
            NSApplication.shared.terminate(nil)
        }
        
        // Visual Backdrop Effect
        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        
        let bgAlpha: CGFloat = isTestMode ? 0.75 : 0.96
        visualEffect.layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: bgAlpha).cgColor
        window.contentView?.addSubview(visualEffect)
        
        if isPrimary {
            let cardWidth: CGFloat = 580
            let cardHeight: CGFloat = 510
            let cardX = (frame.width - cardWidth) / 2
            let cardY = (frame.height - cardHeight) / 2
            
            let card = NSView(frame: NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight))
            Self.styleCard(card)
            visualEffect.addSubview(card)
            
            self.primaryCardView = card
            renderCurrentCardState()
            
            // Test Mode Safety Banner
            if isTestMode {
                let bannerWidth: CGFloat = 580
                let banner = NSView(frame: NSRect(x: (frame.width - bannerWidth) / 2, y: cardY + cardHeight + 16, width: bannerWidth, height: 42))
                banner.wantsLayer = true
                banner.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
                banner.layer?.cornerRadius = 21
                banner.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.6).cgColor
                banner.layer?.borderWidth = 1.2
                
                let bannerText: String
                if let remaining = testModeSecondsRemaining {
                    bannerText = "Test Mode (Auto-unlocks in \(remaining)s) • Esc to Exit"
                } else {
                    bannerText = "Test Mode (Untimed) • Press Esc or Click to Exit"
                }
                
                let label = NSTextField(labelWithString: bannerText)
                label.frame = NSRect(x: 18, y: 11, width: 440, height: 20)
                label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                label.textColor = NSColor.systemYellow
                banner.addSubview(label)
                self.testModeLabel = label
                
                let exitBtn = KeyboardNavigableButton(title: "Exit Test", target: self, action: #selector(handleExitTestClicked))
                exitBtn.frame = NSRect(x: 460, y: 7, width: 105, height: 28)
                exitBtn.bezelStyle = .rounded
                exitBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
                banner.addSubview(exitBtn)
                
                visualEffect.addSubview(banner)
            }
        }
        
        return window
    }
    
    // MARK: - Escape Key Router
    private func handleWindowEscape() {
        switch currentCardState {
        case .overview:
            if isPreviewMode {
                closePreview()
            } else if isTestMode {
                unlockAllScreens()
                onExitTestModeRequested?()
            }
        case .requestTask, .smartNoResult, .emergencyOverride, .aiDecision:
            switchCardState(.overview)
        case .negotiationConcession(let prev, let task, let cons, let mins):
            switchCardState(.aiDecision(result: prev, originalTask: task, originalConsequence: cons, requestedMinutes: mins))
        case .evaluatingAI:
            // Do not interrupt active AI evaluation on escape
            break
        }
    }
    
    // MARK: - Card State Views Rendering
    private func switchCardState(_ state: CardState) {
        self.currentCardState = state
        renderCurrentCardState()
    }
    
    private func renderCurrentCardState() {
        guard let card = primaryCardView else { return }
        card.subviews.forEach { $0.removeFromSuperview() }
        
        // Reset cached form references
        taskField = nil
        consequenceField = nil
        minutesSegmentedControl = nil
        concessionField = nil
        emergencyReasonField = nil
        submitProposalButton = nil
        submitConcessionButton = nil
        submitEmergencyButton = nil
        
        let cardWidth = card.bounds.width
        let cardHeight = card.bounds.height
        
        switch currentCardState {
        case .overview:
            renderOverviewView(in: card, width: cardWidth, height: cardHeight)
        case .requestTask(let task, let consequence, let requestedMinutes):
            renderRequestTaskView(in: card, width: cardWidth, height: cardHeight, task: task, consequence: consequence, requestedMinutes: requestedMinutes)
        case .evaluatingAI(let task, let consequence, let requestedMinutes, let concession, let round):
            renderEvaluatingAIView(in: card, width: cardWidth, height: cardHeight, task: task, consequence: consequence, requestedMinutes: requestedMinutes, concession: concession, round: round)
        case .aiDecision(let result, let task, let consequence, let requestedMinutes):
            renderAIDecisionView(in: card, width: cardWidth, height: cardHeight, result: result, originalTask: task, originalConsequence: consequence, requestedMinutes: requestedMinutes)
        case .negotiationConcession(let prev, let task, let consequence, let requestedMinutes):
            renderNegotiationConcessionView(in: card, width: cardWidth, height: cardHeight, previousResult: prev, originalTask: task, originalConsequence: consequence, requestedMinutes: requestedMinutes)
        case .smartNoResult(let result):
            renderSmartNoView(in: card, width: cardWidth, height: cardHeight, result: result)
        case .emergencyOverride:
            renderEmergencyView(in: card, width: cardWidth, height: cardHeight)
        }
    }
    
    // MARK: 1. Overview View
    private func renderOverviewView(in card: NSView, width: CGFloat, height: CGFloat) {
        let sleep = HealthContextBridge.shared.fetchSleepMetrics()
        
        // Status Badge Header
        let badgeText = isPreviewMode ? "SANDBOX PREVIEW" : (isTestMode ? "DRY RUN TEST MODE" : "BEDTIME CURFEW ACTIVE")
        let badgeColor = isPreviewMode ? NSColor.systemTeal : (isTestMode ? NSColor.systemYellow : NSColor.systemOrange)
        
        let badge = NSTextField(labelWithString: badgeText)
        badge.frame = NSRect(x: (width - 320) / 2, y: height - 50, width: 320, height: 18)
        badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        badge.textColor = badgeColor
        badge.alignment = .center
        card.addSubview(badge)
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Locked for Sleep Recovery")
        titleLabel.frame = NSRect(x: 20, y: height - 96, width: width - 40, height: 32)
        titleLabel.font = NSFont.systemFont(ofSize: 25, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        // Subtitle
        let subLabel = NSTextField(labelWithString: "Screen time is locked until 5:00 AM. Work state remains saved in memory.")
        subLabel.frame = NSRect(x: 30, y: height - 134, width: width - 60, height: 24)
        subLabel.font = NSFont.systemFont(ofSize: 13)
        subLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1.0)
        subLabel.alignment = .center
        card.addSubview(subLabel)
        
        // Sleep Context Capsule Pill
        let pillContainer = NSView(frame: NSRect(x: 40, y: height - 180, width: width - 80, height: 32))
        pillContainer.wantsLayer = true
        pillContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        pillContainer.layer?.cornerRadius = 16
        pillContainer.layer?.cornerCurve = .continuous
        pillContainer.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        pillContainer.layer?.borderWidth = 1.0
        
        let sleepPill = NSTextField(labelWithString: "Last Night: \(sleep.lastNightHours)h  •  7-Day Cumulative Debt: \(sleep.cumulativeSleepDebtHours)h")
        sleepPill.frame = NSRect(x: 10, y: 6, width: pillContainer.frame.width - 20, height: 20)
        sleepPill.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sleepPill.textColor = NSColor(calibratedRed: 0.65, green: 0.82, blue: 1.0, alpha: 1.0)
        sleepPill.alignment = .center
        pillContainer.addSubview(sleepPill)
        card.addSubview(pillContainer)
        
        // Hero Primary Button: Sleep Mac (Return triggers sleep)
        let sleepMacBtn = KeyboardNavigableButton(title: "Sleep Mac (Return)", target: self, action: #selector(handleSleepMacClicked))
        sleepMacBtn.frame = NSRect(x: 40, y: height - 265, width: width - 80, height: 56)
        Self.stylePrimaryButton(sleepMacBtn, title: "Sleep Mac (Return)")
        sleepMacBtn.keyEquivalent = "\r"
        card.addSubview(sleepMacBtn)
        
        // Secondary Action Buttons Row
        let btnWidth = (width - 96) / 2
        let reqBtn = KeyboardNavigableButton(title: "Request Late-Night Task", target: self, action: #selector(handleRequestClicked))
        reqBtn.frame = NSRect(x: 40, y: height - 340, width: btnWidth, height: 48)
        Self.styleSecondaryButton(reqBtn, title: "Request Late-Night Task")
        card.addSubview(reqBtn)
        
        // Emergency Override Button (RED STYLING)
        let emerBtn = KeyboardNavigableButton(title: "Emergency Override", target: self, action: #selector(handleEmergencyClicked))
        emerBtn.frame = NSRect(x: 56 + btnWidth, y: height - 340, width: btnWidth, height: 48)
        Self.styleEmergencyButton(emerBtn, title: "Emergency Override")
        card.addSubview(emerBtn)
        
        // Keyboard navigation loop for Overview
        sleepMacBtn.previousKeyTarget = emerBtn
        sleepMacBtn.nextKeyTarget = reqBtn
        reqBtn.previousKeyTarget = sleepMacBtn
        reqBtn.nextKeyTarget = emerBtn
        emerBtn.previousKeyTarget = reqBtn
        emerBtn.nextKeyTarget = sleepMacBtn
        
        // Footer Note
        let footnote = NSTextField(labelWithString: "Emergency override dispatches an accountability SMS alert.")
        footnote.frame = NSRect(x: 20, y: 28, width: width - 40, height: 20)
        footnote.font = NSFont.systemFont(ofSize: 11)
        footnote.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        footnote.alignment = .center
        card.addSubview(footnote)
        
        DispatchQueue.main.async { [weak sleepMacBtn] in
            guard let sm = sleepMacBtn, let win = sm.window else { return }
            win.makeFirstResponder(sm)
        }
    }
    
    // MARK: 2. Structured Guided Request Task View (3 Fields + Chips)
    private func renderRequestTaskView(in card: NSView, width: CGFloat, height: CGFloat, task: String, consequence: String, requestedMinutes: Int) {
        // Header Badge
        let badge = NSTextField(labelWithString: "LATE-NIGHT TASK ARBITRATION")
        badge.frame = NSRect(x: (width - 320) / 2, y: height - 42, width: 320, height: 16)
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        badge.textColor = NSColor.systemTeal
        badge.alignment = .center
        card.addSubview(badge)
        
        let titleLabel = NSTextField(labelWithString: "Request Work Window")
        titleLabel.frame = NSRect(x: 20, y: height - 76, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Curfew AI reasons over deliverable clarity, urgency, and sleep debt.")
        subLabel.frame = NSRect(x: 30, y: height - 104, width: width - 60, height: 20)
        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1.0)
        subLabel.alignment = .center
        card.addSubview(subLabel)
        
        let fieldWidth = width - 80
        
        // Field 1: Task & Deliverable
        let label1 = NSTextField(labelWithString: "1. TASK & DELIVERABLE")
        label1.frame = NSRect(x: 40, y: height - 142, width: fieldWidth, height: 16)
        label1.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label1.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        card.addSubview(label1)
        
        let tField = NSTextField(frame: NSRect(x: 40, y: height - 182, width: fieldWidth, height: 38))
        Self.styleInputField(tField)
        tField.font = NSFont.systemFont(ofSize: 13)
        tField.placeholderString = "e.g. Finish writing auth migration section 3"
        tField.stringValue = task
        tField.delegate = self
        card.addSubview(tField)
        self.taskField = tField
        
        // Field 2: Impact If Delayed
        let label2 = NSTextField(labelWithString: "2. IMPACT IF DELAYED")
        label2.frame = NSRect(x: 40, y: height - 228, width: fieldWidth, height: 16)
        label2.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label2.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        card.addSubview(label2)
        
        let cField = NSTextField(frame: NSRect(x: 40, y: height - 268, width: fieldWidth, height: 38))
        Self.styleInputField(cField)
        cField.font = NSFont.systemFont(ofSize: 13)
        cField.placeholderString = "e.g. Blocks team morning deploy review at 9:00 AM"
        cField.stringValue = consequence
        cField.delegate = self
        card.addSubview(cField)
        self.consequenceField = cField
        
        // Field 3: Requested Duration (Segmented Chips: 5m, 10m, 15m, 20m)
        let label3 = NSTextField(labelWithString: "3. REQUESTED TIME (Use Arrow Keys or 1-4)")
        label3.frame = NSRect(x: 40, y: height - 314, width: fieldWidth, height: 16)
        label3.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label3.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        card.addSubview(label3)
        
        let segControl = KeyboardNavigableSegmentedControl(labels: ["5 mins", "10 mins", "15 mins", "20 mins"], trackingMode: .selectOne, target: nil, action: nil)
        segControl.frame = NSRect(x: 40, y: height - 354, width: fieldWidth, height: 36)
        segControl.segmentDistribution = .fillEqually
        let segIndex: Int
        switch requestedMinutes {
        case 5: segIndex = 0
        case 15: segIndex = 2
        case 20: segIndex = 3
        default: segIndex = 1 // 10 mins default
        }
        segControl.selectedSegment = segIndex
        card.addSubview(segControl)
        self.minutesSegmentedControl = segControl
        
        // Sleep Context Footnote
        let sleep = HealthContextBridge.shared.fetchSleepMetrics()
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        var minsPast = 0
        if hour >= 22 { minsPast = (hour - 22) * 60 + minute }
        else if hour < 5 { minsPast = (hour + 2) * 60 + minute }
        
        let foot = NSTextField(labelWithString: "Sleep Debt: \(sleep.cumulativeSleepDebtHours)h  •  Last Night: \(sleep.lastNightHours)h  •  Curfew: +\(minsPast)m")
        foot.frame = NSRect(x: 40, y: height - 396, width: fieldWidth, height: 20)
        foot.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        foot.textColor = NSColor(calibratedRed: 0.65, green: 0.82, blue: 1.0, alpha: 0.85)
        foot.alignment = .center
        card.addSubview(foot)
        
        // Action Buttons Row
        let btnWidth = (width - 96) / 2
        let submitBtn = KeyboardNavigableButton(title: "Reason with Curfew AI (Return)", target: self, action: #selector(handleSubmitProposalClicked))
        submitBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
        Self.stylePrimaryButton(submitBtn, title: "Reason with Curfew AI (Return)")
        submitBtn.keyEquivalent = "\r"
        card.addSubview(submitBtn)
        self.submitProposalButton = submitBtn
        
        let cancelBtn = KeyboardNavigableButton(title: "Back (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
        cancelBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
        Self.styleSecondaryButton(cancelBtn, title: "Back (Esc)")
        card.addSubview(cancelBtn)
        self.cancelProposalButton = cancelBtn
        
        // Explicit Bidirectional Keyboard Navigation Loop:
        // Field 1 <-> Field 2 <-> segControl <-> submitBtn <-> cancelBtn <-> Field 1
        tField.nextKeyView = cField
        cField.nextKeyView = segControl
        segControl.previousKeyTarget = cField
        segControl.nextKeyTarget = submitBtn
        segControl.onReturnPressed = { [weak self] in
            self?.handleSubmitProposalClicked()
        }
        submitBtn.previousKeyTarget = segControl
        submitBtn.nextKeyTarget = cancelBtn
        cancelBtn.previousKeyTarget = submitBtn
        cancelBtn.nextKeyTarget = tField
        
        // Auto-focus first field
        DispatchQueue.main.async { [weak tField] in
            guard let tf = tField, let window = tf.window else { return }
            window.makeFirstResponder(tf)
        }
    }
    
    // MARK: 3. Evaluating AI View (Spinner + Async Ollama Dispatch)
    private func renderEvaluatingAIView(
        in card: NSView,
        width: CGFloat,
        height: CGFloat,
        task: String,
        consequence: String,
        requestedMinutes: Int,
        concession: String?,
        round: Int
    ) {
        let badgeText = round > 1 ? "ROUND 2 OF 2: EVALUATING CONCESSION" : "ARBITRATING WITH LOCAL AI"
        let badge = NSTextField(labelWithString: badgeText)
        badge.frame = NSRect(x: (width - 340) / 2, y: height - 42, width: 340, height: 16)
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        badge.textColor = NSColor.systemTeal
        badge.alignment = .center
        card.addSubview(badge)
        
        let titleLabel = NSTextField(labelWithString: "Reasoning Over Proposal")
        titleLabel.frame = NSRect(x: 20, y: height - 76, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let subText = round > 1 ? "Evaluating scope concession against sleep deficit..." : "Analyzing deliverable urgency and sleep debt against llama3.1:8b..."
        let subLabel = NSTextField(labelWithString: subText)
        subLabel.frame = NSRect(x: 30, y: height - 104, width: width - 60, height: 20)
        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = NSColor(calibratedWhite: 0.72, alpha: 1.0)
        subLabel.alignment = .center
        card.addSubview(subLabel)
        
        // Progress Spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: (width - 40) / 2, y: height - 165, width: 40, height: 40))
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        card.addSubview(spinner)
        
        let status = NSTextField(labelWithString: "Connecting to local Ollama (llama3.1:8b)...")
        status.frame = NSRect(x: 40, y: height - 198, width: width - 80, height: 20)
        status.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        status.textColor = NSColor.systemTeal
        status.alignment = .center
        card.addSubview(status)
        
        // Proposal Snapshot Card
        let box = NSView(frame: NSRect(x: 40, y: 44, width: width - 80, height: 180))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 0.92).cgColor
        box.layer?.cornerRadius = 10
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        box.layer?.borderWidth = 1.0
        
        let boxTitle = NSTextField(labelWithString: "SUBMITTED PROPOSAL")
        boxTitle.frame = NSRect(x: 16, y: 150, width: 200, height: 16)
        boxTitle.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        boxTitle.textColor = NSColor(calibratedWhite: 0.5, alpha: 1.0)
        box.addSubview(boxTitle)
        
        let taskText = NSTextField(labelWithString: "Task: \(task)")
        taskText.frame = NSRect(x: 16, y: 118, width: width - 112, height: 24)
        taskText.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        taskText.textColor = NSColor.white
        box.addSubview(taskText)
        
        let impactText = NSTextField(labelWithString: "Impact: \(consequence)")
        impactText.frame = NSRect(x: 16, y: 88, width: width - 112, height: 24)
        impactText.font = NSFont.systemFont(ofSize: 12)
        impactText.textColor = NSColor(calibratedWhite: 0.8, alpha: 1.0)
        box.addSubview(impactText)
        
        let timeText = NSTextField(labelWithString: "Requested: \(requestedMinutes) minutes")
        timeText.frame = NSRect(x: 16, y: 58, width: width - 112, height: 24)
        timeText.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        timeText.textColor = NSColor(calibratedRed: 0.65, green: 0.82, blue: 1.0, alpha: 1.0)
        box.addSubview(timeText)
        
        if let conc = concession, !conc.isEmpty {
            let concText = NSTextField(labelWithString: "Concession: \(conc)")
            concText.frame = NSRect(x: 16, y: 24, width: width - 112, height: 24)
            concText.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            concText.textColor = NSColor.systemYellow
            box.addSubview(concText)
        }
        
        card.addSubview(box)
        
        // Dispatch Asynchronous AI Evaluation
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let result = await IntentArbitrator.shared.evaluateWithAI(
                task: task,
                consequence: consequence,
                requestedMinutes: requestedMinutes,
                concession: concession,
                round: round
            )
            self.switchCardState(.aiDecision(
                result: result,
                originalTask: task,
                originalConsequence: consequence,
                requestedMinutes: requestedMinutes
            ))
        }
    }
    
    // MARK: 4. AI Decision & Counter-Offer View
    private func renderAIDecisionView(
        in card: NSView,
        width: CGFloat,
        height: CGFloat,
        result: ArbitrationResult,
        originalTask: String,
        originalConsequence: String,
        requestedMinutes: Int
    ) {
        let isApproved = result.isApproved
        let isCounter = result.isCounterOffer
        
        // Badge
        let badgeText: String
        let badgeColor: NSColor
        if isApproved && !isCounter {
            badgeText = "DECISION: APPROVED"
            badgeColor = NSColor.systemGreen
        } else if isApproved && isCounter {
            badgeText = "DECISION: COUNTER-OFFER"
            badgeColor = NSColor.systemOrange
        } else {
            badgeText = "DECISION: DECLINED"
            badgeColor = NSColor.systemRed
        }
        
        let badge = NSTextField(labelWithString: badgeText)
        badge.frame = NSRect(x: (width - 320) / 2, y: height - 38, width: 320, height: 16)
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        badge.textColor = badgeColor
        badge.alignment = .center
        card.addSubview(badge)
        
        // Title
        let titleString: String
        if isCounter {
            titleString = "Counter-Offer: \(result.grantedMinutes)m Window"
        } else if isApproved {
            titleString = "Approved: \(result.grantedMinutes)m Window"
        } else {
            titleString = "Sleep Recovery Priority"
        }
        
        let titleLabel = NSTextField(labelWithString: titleString)
        titleLabel.frame = NSRect(x: 20, y: height - 70, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        // Details Box
        let box = NSView(frame: NSRect(x: 40, y: 94, width: width - 80, height: 260))
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 0.94).cgColor
        box.layer?.cornerRadius = 12
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        box.layer?.borderWidth = 1.0
        
        // Summary Row
        let timeRow: String
        let timeColor: NSColor
        if isCounter {
            timeRow = "Requested: \(requestedMinutes)m  →  AI Offered: \(result.grantedMinutes)m"
            timeColor = NSColor.systemOrange
        } else if isApproved {
            timeRow = "Requested: \(requestedMinutes)m  •  Granted: \(result.grantedMinutes)m"
            timeColor = NSColor.systemGreen
        } else {
            timeRow = "Requested: \(requestedMinutes)m  •  Granted: 0m (Preserve sleep)"
            timeColor = NSColor.systemRed
        }
        
        let timeSummary = NSTextField(labelWithString: timeRow)
        timeSummary.frame = NSRect(x: 16, y: 226, width: width - 112, height: 22)
        timeSummary.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        timeSummary.textColor = timeColor
        box.addSubview(timeSummary)
        
        // Allowed Scope
        if !result.suggestedScope.isEmpty {
            let scopeLabel = NSTextField(labelWithString: "Allowed Scope: \"\(result.suggestedScope)\"")
            scopeLabel.frame = NSRect(x: 16, y: 198, width: width - 112, height: 22)
            scopeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            scopeLabel.textColor = NSColor(calibratedRed: 0.65, green: 0.85, blue: 1.0, alpha: 1.0)
            box.addSubview(scopeLabel)
        }
        
        // Sleep Context Metric
        let sleep = HealthContextBridge.shared.fetchSleepMetrics()
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        var minsPast = 0
        if hour >= Config.weeknightBedtimeStartHour {
            minsPast = (hour - Config.weeknightBedtimeStartHour) * 60 + minute
        } else if hour < Config.weeknightBedtimeEndHour {
            minsPast = (hour + (24 - Config.weeknightBedtimeStartHour)) * 60 + minute
        }
        
        let sleepLabelText = sleep.isStale
            ? "Context: HealthKit Sync Inactive (\(sleep.daysSinceLastSync)d ago)  •  Curfew +\(minsPast)m"
            : "Context: Sleep Debt \(sleep.cumulativeSleepDebtHours)h  •  Curfew +\(minsPast)m"
        let sleepMetrics = NSTextField(labelWithString: sleepLabelText)
        sleepMetrics.frame = NSRect(x: 16, y: 172, width: width - 112, height: 18)
        sleepMetrics.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sleepMetrics.textColor = NSColor(calibratedWhite: 0.65, alpha: 1.0)
        box.addSubview(sleepMetrics)
        
        // AI Reasoning Text Area
        let reasonHeader = NSTextField(labelWithString: "CURFEW AI REASONING:")
        reasonHeader.frame = NSRect(x: 16, y: 142, width: width - 112, height: 16)
        reasonHeader.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        reasonHeader.textColor = NSColor(calibratedWhite: 0.45, alpha: 1.0)
        box.addSubview(reasonHeader)
        
        let reasonBody = NSTextField(wrappingLabelWithString: result.reasoning)
        reasonBody.frame = NSRect(x: 16, y: 16, width: width - 112, height: 120)
        reasonBody.font = NSFont.systemFont(ofSize: 12)
        reasonBody.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        box.addSubview(reasonBody)
        
        card.addSubview(box)
        
        // Action Buttons
        let btnWidth = (width - 96) / 2
        let triBtnWidth = (width - 104) / 3
        if isApproved {
            let acceptBtn = KeyboardNavigableButton(title: "Accept & Start (\(result.grantedMinutes)m)", target: self, action: #selector(handleAcceptAIDecisionClicked))
            Self.stylePrimaryButton(acceptBtn, title: "Accept & Start (\(result.grantedMinutes)m)")
            acceptBtn.keyEquivalent = "\r"
            
            if isCounter && result.round < 2 {
                // Counter-Offer Round 1: [Accept] [Negotiate (Round 2)] [Decline]
                acceptBtn.frame = NSRect(x: 40, y: 34, width: triBtnWidth, height: 48)
                card.addSubview(acceptBtn)
                
                let negBtn = KeyboardNavigableButton(title: "Negotiate (Round 2)", target: self, action: #selector(handleStartNegotiationClicked))
                negBtn.frame = NSRect(x: 48 + triBtnWidth, y: 34, width: triBtnWidth, height: 48)
                Self.styleSecondaryButton(negBtn, title: "Negotiate (Round 2)")
                card.addSubview(negBtn)
                
                let declineBtn = KeyboardNavigableButton(title: "Decline (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
                declineBtn.frame = NSRect(x: 56 + triBtnWidth * 2, y: 34, width: triBtnWidth, height: 48)
                Self.styleSecondaryButton(declineBtn, title: "Decline (Esc)")
                card.addSubview(declineBtn)
                
                acceptBtn.previousKeyTarget = declineBtn
                acceptBtn.nextKeyTarget = negBtn
                negBtn.previousKeyTarget = acceptBtn
                negBtn.nextKeyTarget = declineBtn
                declineBtn.previousKeyTarget = negBtn
                declineBtn.nextKeyTarget = acceptBtn
                
                DispatchQueue.main.async { [weak acceptBtn] in
                    acceptBtn?.window?.makeFirstResponder(acceptBtn)
                }
            } else {
                // Approved directly or Final Round 2
                acceptBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
                card.addSubview(acceptBtn)
                
                let cancelBtn = KeyboardNavigableButton(title: "Cancel (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
                cancelBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
                Self.styleSecondaryButton(cancelBtn, title: "Cancel (Esc)")
                card.addSubview(cancelBtn)
                
                acceptBtn.previousKeyTarget = cancelBtn
                acceptBtn.nextKeyTarget = cancelBtn
                cancelBtn.previousKeyTarget = acceptBtn
                cancelBtn.nextKeyTarget = acceptBtn
                
                DispatchQueue.main.async { [weak acceptBtn] in
                    acceptBtn?.window?.makeFirstResponder(acceptBtn)
                }
            }
        } else {
            // Declined
            if result.round < 2 {
                let negBtn = KeyboardNavigableButton(title: "Negotiate (Round 2)", target: self, action: #selector(handleStartNegotiationClicked))
                negBtn.frame = NSRect(x: 40, y: 34, width: triBtnWidth, height: 48)
                Self.stylePrimaryButton(negBtn, title: "Negotiate (Round 2)")
                card.addSubview(negBtn)
                
                let remBtn = KeyboardNavigableButton(title: "Save Reminder (6 PM)", target: self, action: #selector(handleAddReminderFromDecisionClicked(_:)))
                remBtn.frame = NSRect(x: 48 + triBtnWidth, y: 34, width: triBtnWidth, height: 48)
                Self.styleSecondaryButton(remBtn, title: "Save Reminder (6 PM)")
                card.addSubview(remBtn)
                
                let backBtn = KeyboardNavigableButton(title: "Back (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
                backBtn.frame = NSRect(x: 56 + triBtnWidth * 2, y: 34, width: triBtnWidth, height: 48)
                Self.styleSecondaryButton(backBtn, title: "Back (Esc)")
                card.addSubview(backBtn)
                
                negBtn.previousKeyTarget = backBtn
                negBtn.nextKeyTarget = remBtn
                remBtn.previousKeyTarget = negBtn
                remBtn.nextKeyTarget = backBtn
                backBtn.previousKeyTarget = remBtn
                backBtn.nextKeyTarget = negBtn
                
                DispatchQueue.main.async { [weak negBtn] in
                    negBtn?.window?.makeFirstResponder(negBtn)
                }
            } else {
                let remBtn = KeyboardNavigableButton(title: "Save Reminder (Tomorrow 6 PM)", target: self, action: #selector(handleAddReminderFromDecisionClicked(_:)))
                remBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
                Self.stylePrimaryButton(remBtn, title: "Save Reminder (Tomorrow 6 PM)")
                card.addSubview(remBtn)
                
                let backBtn = KeyboardNavigableButton(title: "Return to Curfew (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
                backBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
                Self.styleSecondaryButton(backBtn, title: "Return to Curfew (Esc)")
                card.addSubview(backBtn)
                
                remBtn.previousKeyTarget = backBtn
                remBtn.nextKeyTarget = backBtn
                backBtn.previousKeyTarget = remBtn
                backBtn.nextKeyTarget = remBtn
                
                DispatchQueue.main.async { [weak remBtn] in
                    remBtn?.window?.makeFirstResponder(remBtn)
                }
            }
        }
    }
    
    // MARK: 5. Negotiation Concession View (Round 2 of 2)
    private func renderNegotiationConcessionView(
        in card: NSView,
        width: CGFloat,
        height: CGFloat,
        previousResult: ArbitrationResult,
        originalTask: String,
        originalConsequence: String,
        requestedMinutes: Int
    ) {
        let badge = NSTextField(labelWithString: "ROUND 2 OF 2: SCOPE CONCESSION")
        badge.frame = NSRect(x: (width - 320) / 2, y: height - 42, width: 320, height: 16)
        badge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .heavy)
        badge.textColor = NSColor.systemYellow
        badge.alignment = .center
        card.addSubview(badge)
        
        let titleLabel = NSTextField(labelWithString: "Negotiate with Curfew AI")
        titleLabel.frame = NSRect(x: 20, y: height - 76, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let offeredTime = previousResult.grantedMinutes > 0 ? previousResult.grantedMinutes : requestedMinutes
        let subText = "The model offered \(offeredTime)m for a reduced deliverable.\nWhat scope will you cut so you can sleep faster?"
        let subLabel = NSTextField(wrappingLabelWithString: subText)
        subLabel.frame = NSRect(x: 30, y: height - 132, width: width - 60, height: 44)
        subLabel.font = NSFont.systemFont(ofSize: 13)
        subLabel.textColor = NSColor(calibratedWhite: 0.80, alpha: 1.0)
        subLabel.alignment = .center
        card.addSubview(subLabel)
        
        let fieldWidth = width - 80
        
        // Scope Concession Input Field
        let label1 = NSTextField(labelWithString: "YOUR SCOPE CONCESSION")
        label1.frame = NSRect(x: 40, y: height - 188, width: fieldWidth, height: 16)
        label1.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        label1.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        card.addSubview(label1)
        
        let cField = NSTextField(frame: NSRect(x: 40, y: height - 240, width: fieldWidth, height: 44))
        Self.styleInputField(cField)
        cField.font = NSFont.systemFont(ofSize: 13)
        cField.placeholderString = "e.g. I will skip formatting and only write the core 2 paragraphs"
        cField.stringValue = ""
        cField.delegate = self
        card.addSubview(cField)
        self.concessionField = cField
        
        let note = NSTextField(wrappingLabelWithString: "Final Round Policy: Conceding non-essential work protects recovery while meeting true deadlines. Model sets the final verdict.")
        note.frame = NSRect(x: 40, y: height - 325, width: fieldWidth, height: 48)
        note.font = NSFont.systemFont(ofSize: 12)
        note.textColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
        note.alignment = .center
        card.addSubview(note)
        
        // Action Buttons Row
        let btnWidth = (width - 96) / 2
        let submitBtn = KeyboardNavigableButton(title: "Submit Concession (Return)", target: self, action: #selector(handleSubmitConcessionClicked))
        submitBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
        Self.stylePrimaryButton(submitBtn, title: "Submit Concession (Return)")
        submitBtn.keyEquivalent = "\r"
        card.addSubview(submitBtn)
        self.submitConcessionButton = submitBtn
        
        let backBtn = KeyboardNavigableButton(title: "Back to Offer (Esc)", target: self, action: #selector(handleBackToAIDecisionClicked))
        backBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
        Self.styleSecondaryButton(backBtn, title: "Back to Offer (Esc)")
        card.addSubview(backBtn)
        
        cField.nextKeyView = submitBtn
        submitBtn.previousKeyTarget = cField
        submitBtn.nextKeyTarget = backBtn
        backBtn.previousKeyTarget = submitBtn
        backBtn.nextKeyTarget = cField
        
        DispatchQueue.main.async { [weak cField] in
            guard let cf = cField, let window = cf.window else { return }
            window.makeFirstResponder(cf)
        }
    }
    
    // MARK: 6. Embedded Smart No Result View
    private func renderSmartNoView(in card: NSView, width: CGFloat, height: CGFloat, result: ArbitrationResult) {
        let badge = NSTextField(labelWithString: "REQUEST NOT GRANTED")
        badge.frame = NSRect(x: (width - 240) / 2, y: height - 44, width: 240, height: 18)
        badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        badge.textColor = NSColor.systemOrange
        badge.alignment = .center
        card.addSubview(badge)
        
        let titleLabel = NSTextField(labelWithString: result.decisionSummary)
        titleLabel.frame = NSRect(x: 20, y: height - 84, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let reasonLabel = NSTextField(wrappingLabelWithString: result.reasoning)
        reasonLabel.frame = NSRect(x: 40, y: height - 250, width: width - 80, height: 150)
        reasonLabel.font = NSFont.systemFont(ofSize: 13)
        reasonLabel.textColor = NSColor(calibratedWhite: 0.85, alpha: 1.0)
        reasonLabel.alignment = .center
        card.addSubview(reasonLabel)
        
        let btnWidth = (width - 96) / 2
        let remindersBtn = KeyboardNavigableButton(title: "Open Apple Reminders", target: self, action: #selector(handleOpenRemindersClicked))
        remindersBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
        Self.stylePrimaryButton(remindersBtn, title: "Open Apple Reminders")
        card.addSubview(remindersBtn)
        
        let backBtn = KeyboardNavigableButton(title: "Return to Curfew (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
        backBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
        Self.styleSecondaryButton(backBtn, title: "Return to Curfew (Esc)")
        card.addSubview(backBtn)
        
        remindersBtn.previousKeyTarget = backBtn
        remindersBtn.nextKeyTarget = backBtn
        backBtn.previousKeyTarget = remindersBtn
        backBtn.nextKeyTarget = remindersBtn
        
        DispatchQueue.main.async { [weak remindersBtn] in
            remindersBtn?.window?.makeFirstResponder(remindersBtn)
        }
    }
    
    // MARK: 7. Embedded Emergency Override View
    private func renderEmergencyView(in card: NSView, width: CGFloat, height: CGFloat) {
        let badge = NSTextField(labelWithString: "EMERGENCY OVERRIDE")
        badge.frame = NSRect(x: (width - 260) / 2, y: height - 44, width: 260, height: 18)
        badge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy)
        badge.textColor = NSColor.systemRed
        badge.alignment = .center
        card.addSubview(badge)
        
        let titleLabel = NSTextField(labelWithString: "Accountability Alert")
        titleLabel.frame = NSRect(x: 20, y: height - 80, width: width - 40, height: 28)
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = NSColor.white
        titleLabel.alignment = .center
        card.addSubview(titleLabel)
        
        let subLabel = NSTextField(wrappingLabelWithString: "Dispatches SMS to \(Config.girlfriendContact) with your reason.\nEnter brief description:")
        subLabel.frame = NSRect(x: 30, y: height - 146, width: width - 60, height: 44)
        subLabel.font = NSFont.systemFont(ofSize: 13)
        subLabel.textColor = NSColor(calibratedWhite: 0.8, alpha: 1.0)
        subLabel.alignment = .center
        card.addSubview(subLabel)
        
        let fieldWidth = width - 80
        let field = NSTextField(frame: NSRect(x: 40, y: height - 215, width: fieldWidth, height: 38))
        Self.styleInputField(field)
        field.placeholderString = "Reason for emergency unlock"
        field.font = NSFont.systemFont(ofSize: 13)
        field.delegate = self
        card.addSubview(field)
        self.emergencyReasonField = field
        
        let btnWidth = (width - 96) / 2
        let sendBtn = KeyboardNavigableButton(title: "Send Alert & Unlock", target: self, action: #selector(handleSubmitEmergencyClicked))
        sendBtn.frame = NSRect(x: 40, y: 34, width: btnWidth, height: 48)
        Self.styleEmergencyButton(sendBtn, title: "Send Alert & Unlock")
        card.addSubview(sendBtn)
        self.submitEmergencyButton = sendBtn
        
        let cancelBtn = KeyboardNavigableButton(title: "Cancel (Esc)", target: self, action: #selector(handleBackToOverviewClicked))
        cancelBtn.frame = NSRect(x: 56 + btnWidth, y: 34, width: btnWidth, height: 48)
        Self.styleSecondaryButton(cancelBtn, title: "Cancel (Esc)")
        card.addSubview(cancelBtn)
        
        field.nextKeyView = sendBtn
        sendBtn.previousKeyTarget = field
        sendBtn.nextKeyTarget = cancelBtn
        cancelBtn.previousKeyTarget = sendBtn
        cancelBtn.nextKeyTarget = field
        
        DispatchQueue.main.async { [weak field] in
            guard let f = field, let window = f.window else { return }
            window.makeFirstResponder(f)
        }
    }
    
    // MARK: - Action Handlers
    @objc private func handleRequestClicked() {
        switchCardState(.requestTask(task: "", consequence: "", requestedMinutes: 10))
    }
    
    @objc private func handleEmergencyClicked() {
        switchCardState(.emergencyOverride)
    }
    
    @objc private func handleBackToOverviewClicked() {
        switchCardState(.overview)
    }
    
    @objc private func handleExitTestClicked() {
        unlockAllScreens()
        onExitTestModeRequested?()
    }
    
    @objc private func handleSleepMacClicked() {
        if isTestMode || isPreviewMode {
            let alert = NSAlert()
            alert.messageText = "Sleep Mac Simulation"
            alert.informativeText = "In production curfew, this button immediately puts your Mac to sleep for recovery.\n\nWould you like to put your Mac to sleep now to test it?"
            alert.addButton(withTitle: "Put Mac to Sleep")
            alert.addButton(withTitle: "Stay Awake (Cancel)")
            if alert.runModal() == .alertFirstButtonReturn {
                triggerMacSleep()
            }
            return
        }
        triggerMacSleep()
    }
    
    @objc private func handleAddReminderFromDecisionClicked(_ sender: NSButton) {
        guard case .aiDecision(_, let originalTask, let originalConsequence, _) = currentCardState else {
            RemindersBridge.shared.openRemindersApp()
            return
        }
        
        let notes = "Created by Curfew past bedtime.\nConsequence noted: \(originalConsequence)"
        RemindersBridge.shared.createSmartNoReminder(
            taskTitle: originalTask,
            notes: notes,
            dueHour: 18,
            dueMinute: 0
        )
        
        Self.styleSecondaryButton(sender, title: "✅ Saved for 6 PM")
        sender.layer?.borderColor = NSColor.systemGreen.cgColor
        sender.layer?.borderWidth = 1.5
        if let kb = sender as? KeyboardNavigableButton {
            kb.normalBorderColor = NSColor.systemGreen.cgColor
            kb.normalBorderWidth = 1.5
        }
        sender.isEnabled = false
    }
    
    @objc private func handleOpenRemindersClicked() {
        RemindersBridge.shared.openRemindersApp()
        switchCardState(.overview)
    }
    
    @objc private func handleSubmitProposalClicked() {
        let task = taskField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let consequence = consequenceField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard !task.isEmpty else {
            taskField?.focusRingType = .exterior
            taskField?.window?.makeFirstResponder(taskField)
            return
        }
        
        let segIdx = minutesSegmentedControl?.selectedSegment ?? 1
        let minutes: Int
        switch segIdx {
        case 0: minutes = 5
        case 1: minutes = 10
        case 2: minutes = 15
        case 3: minutes = 20
        default: minutes = 10
        }
        
        switchCardState(.evaluatingAI(
            task: task,
            consequence: consequence.isEmpty ? "Deferring deliverable to morning" : consequence,
            requestedMinutes: minutes,
            concession: nil,
            round: 1
        ))
    }
    
    @objc private func handleAcceptAIDecisionClicked() {
        guard case .aiDecision(let result, _, _, _) = currentCardState else { return }
        unlockAllScreens()
        onRequestApproved?(result)
    }
    
    @objc private func handleStartNegotiationClicked() {
        guard case .aiDecision(let result, let task, let consequence, let minutes) = currentCardState else { return }
        switchCardState(.negotiationConcession(
            previousResult: result,
            originalTask: task,
            originalConsequence: consequence,
            requestedMinutes: minutes
        ))
    }
    
    @objc private func handleSubmitConcessionClicked() {
        guard case .negotiationConcession(let prev, let task, let consequence, let minutes) = currentCardState else { return }
        let concession = concessionField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard !concession.isEmpty else {
            concessionField?.focusRingType = .exterior
            concessionField?.window?.makeFirstResponder(concessionField)
            return
        }
        
        let reqMins = prev.grantedMinutes > 0 ? prev.grantedMinutes : minutes
        switchCardState(.evaluatingAI(
            task: task,
            consequence: consequence,
            requestedMinutes: reqMins,
            concession: concession,
            round: 2
        ))
    }
    
    @objc private func handleBackToAIDecisionClicked() {
        guard case .negotiationConcession(let prev, let task, let consequence, let minutes) = currentCardState else { return }
        switchCardState(.aiDecision(
            result: prev,
            originalTask: task,
            originalConsequence: consequence,
            requestedMinutes: minutes
        ))
    }
    
    @objc private func handleSubmitEmergencyClicked() {
        let reason = emergencyReasonField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Emergency"
        unlockAllScreens()
        onEmergencyApproved?(reason)
    }
    
    // MARK: - Safe Mac Sleep Action
    public func triggerMacSleep() {
        let script = "tell application \"Finder\" to sleep"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}

// MARK: - NSTextFieldDelegate (Tab & Return Key Navigation, Reactive Focus Glow)
extension CurfewLockScreenController {
    public func controlTextDidBeginEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            field.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.85).cgColor
            field.layer?.borderWidth = 1.5
        }
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            field.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            field.layer?.borderWidth = 1.2
        }
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Tab key navigation: Jump down to next field
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if control == taskField {
                if let next = consequenceField {
                    next.window?.makeFirstResponder(next)
                    return true
                }
            } else if control == consequenceField {
                if let next = minutesSegmentedControl {
                    next.window?.makeFirstResponder(next)
                    return true
                } else if let btn = submitProposalButton {
                    btn.window?.makeFirstResponder(btn)
                    return true
                }
            } else if control == concessionField {
                if let btn = submitConcessionButton {
                    btn.window?.makeFirstResponder(btn)
                    return true
                }
            } else if control == emergencyReasonField {
                if let btn = submitEmergencyButton {
                    btn.window?.makeFirstResponder(btn)
                    return true
                }
            }
        } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            // Shift + Tab navigation: Jump back up to previous field
            if control == consequenceField {
                if let prev = taskField {
                    prev.window?.makeFirstResponder(prev)
                    return true
                }
            } else if control == taskField {
                if let cancel = cancelProposalButton {
                    cancel.window?.makeFirstResponder(cancel)
                    return true
                }
            }
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Return key: If user is on task field and consequence is empty, jump to consequence; otherwise submit
            if control == taskField {
                let taskText = taskField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let consText = consequenceField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !taskText.isEmpty && consText.isEmpty {
                    consequenceField?.window?.makeFirstResponder(consequenceField)
                    return true
                } else if !taskText.isEmpty {
                    handleSubmitProposalClicked()
                    return true
                }
            } else if control == consequenceField {
                handleSubmitProposalClicked()
                return true
            } else if control == concessionField {
                handleSubmitConcessionClicked()
                return true
            } else if control == emergencyReasonField {
                handleSubmitEmergencyClicked()
                return true
            }
        }
        return false
    }
}
