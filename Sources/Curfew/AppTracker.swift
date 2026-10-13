import Cocoa
import CoreGraphics

@MainActor
public final class AppTracker {
    public static let shared = AppTracker()
    
    public private(set) var activeAppName: String = "Finder"
    public private(set) var activeAppBundleId: String = ""
    public private(set) var isUserActive: Bool = true
    public private(set) var idleSeconds: Double = 0.0
    
    // Callbacks
    public var onAppChanged: ((String) -> Void)?
    public var onActiveTimeTick: ((_ todayMinutes: Int, _ isQuotaExceeded: Bool) -> Void)?
    public var onPreLockWarning: ((_ minutesUntilCurfew: Int) -> Void)?
    public var onSystemWoke: (() -> Void)?
    
    private var trackingTimer: Timer?
    private var isTrackingPaused: Bool = false
    private var issuedWarningsForTonight: Set<Int> = []
    
    private init() {}
    
    public func start() {
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            handleAppActivated(frontmost)
        }
        
        let notifCenter = NSWorkspace.shared.notificationCenter
        notifCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        notifCenter.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notifCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        startTrackingTimer()
    }
    
    public func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    private func startTrackingTimer() {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.timerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.trackingTimer = timer
    }
    
    private func timerTick() {
        guard !isTrackingPaused else { return }
        
        // 1. Check system idle time using CoreGraphics event source
        if let eventType = CGEventType(rawValue: ~0) {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
            self.idleSeconds = seconds
            self.isUserActive = seconds < Config.idleThresholdSeconds
        } else {
            self.isUserActive = true
            self.idleSeconds = 0.0
        }
        
        // 2. Accumulate active screen time only if user is actively interacting
        if isUserActive {
            StorageManager.shared.addActiveSeconds(1)
            let state = StorageManager.shared.state
            onActiveTimeTick?(state.todayMinutesSpent, state.isQuotaExceeded)
        }
        
        // 3. Pre-Curfew Warning Check
        checkPreCurfewWarnings()
    }
    
    private func checkPreCurfewWarnings() {
        let calendar = Calendar.current
        let now = Date()
        guard !calendar.isDateInWeekend(now) else { return }
        
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        
        // Target is 10:00 PM (hour 22, minute 0)
        let curfewHour = Config.weeknightBedtimeStartHour
        if hour == (curfewHour - 1) {
            let minutesLeft = 60 - minute
            for warningMinute in Config.preLockWarningMinutes {
                if minutesLeft == warningMinute && !issuedWarningsForTonight.contains(warningMinute) {
                    issuedWarningsForTonight.insert(warningMinute)
                    print("[AppTracker] ⚠️ Curfew Warning: \(minutesLeft) minutes until bedtime curfew!")
                    onPreLockWarning?(minutesLeft)
                }
            }
        } else if hour < (curfewHour - 1) || hour >= Config.weeknightBedtimeEndHour {
            // Reset issued warnings for the next cycle
            if !issuedWarningsForTonight.isEmpty && hour >= 6 && hour < 20 {
                issuedWarningsForTonight.removeAll()
            }
        }
    }
    
    // MARK: - Notifications
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        handleAppActivated(app)
    }
    
    private func handleAppActivated(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "Unknown"
        let bundleId = app.bundleIdentifier ?? ""
        
        self.activeAppName = name
        self.activeAppBundleId = bundleId
        
        self.onAppChanged?(name)
    }
    
    @objc private func systemWillSleep(_ notification: Notification) {
        print("[AppTracker] System going to sleep. Pausing active tracking.")
        isTrackingPaused = true
    }
    
    @objc private func systemDidWake(_ notification: Notification) {
        print("[AppTracker] System woke up. Resuming active tracking and checking rollover.")
        isTrackingPaused = false
        StorageManager.shared.checkDayRollover()
        onSystemWoke?()
    }
}
