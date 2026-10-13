import Foundation

public struct AppState: Codable, Sendable {
    public var focusModeActive: Bool
    public var currentSessionName: String
    public var dailyLimitMinutes: Int
    public var todayMinutesSpent: Int
    public var todayActiveSeconds: Int
    public var lastDateString: String
    public var consecutiveBypassesTonight: Int
    public var allowedApps: [String]
    public var blockedApps: [String]
    
    public var isQuotaExceeded: Bool {
        return todayMinutesSpent >= dailyLimitMinutes
    }
    
    public static var `default`: AppState {
        AppState(
            focusModeActive: false,
            currentSessionName: "Deep Focus",
            dailyLimitMinutes: Config.defaultDailyLimitMinutes,
            todayMinutesSpent: 0,
            todayActiveSeconds: 0,
            lastDateString: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none),
            consecutiveBypassesTonight: 0,
            allowedApps: Config.weekendAllowedApps,
            blockedApps: ["YouTube", "Twitter", "X", "TikTok", "Instagram"]
        )
    }
}

public final class StorageManager: @unchecked Sendable {
    public static let shared = StorageManager()
    
    private let fileURL: URL
    private let lock = NSLock()
    public private(set) var state: AppState
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Curfew", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("state.json")
        
        // Migrate legacy state if present
        let oldFile = appSupport.appendingPathComponent("SmartScreenTime/state.json")
        if !FileManager.default.fileExists(atPath: fileURL.path) && FileManager.default.fileExists(atPath: oldFile.path) {
            try? FileManager.default.copyItem(at: oldFile, to: fileURL)
        }
        
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(AppState.self, from: data) {
            self.state = loaded
        } else {
            self.state = .default
        }
        
        checkDayRollover()
    }
    
    public func update(_ block: (inout AppState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        block(&state)
        save()
    }
    
    /// Increments tracked active screen-time seconds and rolls over minutes automatically.
    public func addActiveSeconds(_ seconds: Int) {
        guard seconds > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        
        checkDayRolloverLocked()
        state.todayActiveSeconds += seconds
        state.todayMinutesSpent = state.todayActiveSeconds / 60
        save()
    }
    
    /// Sets a new daily limit quota in minutes.
    public func setDailyLimit(minutes: Int) {
        update { s in
            s.dailyLimitMinutes = max(5, minutes)
        }
    }
    
    /// Checks whether an application is permitted based on weekend rules and blacklists.
    public func isAppAllowed(_ appName: String, isWeekend: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Finder" { return true }
        
        if isWeekend {
            // On weekends, strictly allow creative/work productivity apps if configured
            if !state.allowedApps.isEmpty {
                return state.allowedApps.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
        }
        
        // Check blacklist
        for blocked in state.blockedApps {
            if trimmed.localizedCaseInsensitiveContains(blocked) {
                return false
            }
        }
        return true
    }
    
    public func checkDayRollover() {
        lock.lock()
        defer { lock.unlock() }
        checkDayRolloverLocked()
    }
    
    private func checkDayRolloverLocked() {
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        if state.lastDateString != todayStr {
            state.lastDateString = todayStr
            state.todayMinutesSpent = 0
            state.todayActiveSeconds = 0
            state.consecutiveBypassesTonight = 0
            save()
        }
    }
    
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
