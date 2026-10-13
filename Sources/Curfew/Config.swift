import Foundation

/// Central configuration for Curfew.
/// Automatically loads custom user settings from `~/.config/curfew/config.json` if available,
/// falling back to safe generic defaults.
public struct Config: Sendable {
    private struct UserConfig: Codable {
        var weeknightBedtimeStartHour: Int?
        var weeknightBedtimeEndHour: Int?
        var targetSleepHours: Double?
        var minimumAcceptableSleepHours: Double?
        var weekendAllowedApps: [String]?
        var weekendAlwaysBlockedDomains: [String]?
        var girlfriendContact: String?
        var chimeIntervalSeconds: Double?
        var healthDbPath: String?
        var workWifiSSIDs: [String]?
        var homeWifiSSIDs: [String]?
        var girlfriendWifiSSIDs: [String]?
        var debugForceCurfewActive: Bool?
        var testModeAutoDismissSeconds: Int?
        var idleThresholdSeconds: Double?
        var preLockWarningMinutes: [Int]?
        var defaultDailyLimitMinutes: Int?
        var fileBypassPath: String?
        var hotCornerBypassEnabled: Bool?
    }
    
    private static let loadedUserConfig: UserConfig? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configPath = home.appendingPathComponent(".config/curfew/config.json")
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(UserConfig.self, from: data) else {
            return nil
        }
        return config
    }()
    
    // MARK: - Bedtime & Curfew Rules
    public static let weeknightBedtimeStartHour: Int = loadedUserConfig?.weeknightBedtimeStartHour ?? 22
    public static let weeknightBedtimeEndHour: Int = loadedUserConfig?.weeknightBedtimeEndHour ?? 5
    
    // Optimal sleep baseline (8.0h for recovery, critical floor 7.0h)
    public static let targetSleepHours: Double = loadedUserConfig?.targetSleepHours ?? 8.0
    public static let minimumAcceptableSleepHours: Double = loadedUserConfig?.minimumAcceptableSleepHours ?? 7.0
    
    // MARK: - Weekend Rules
    public static let weekendAllowedApps: [String] = loadedUserConfig?.weekendAllowedApps ?? [
        "Logic Pro", "Xcode", "Visual Studio Code", "Terminal", "Finder", "Ableton Live"
    ]
    public static let weekendAlwaysBlockedDomains: [String] = loadedUserConfig?.weekendAlwaysBlockedDomains ?? [
        "youtube.com", "instagram.com", "reddit.com", "twitter.com", "x.com", "tiktok.com"
    ]
    
    // MARK: - Social Stake / Emergency Contact
    public static let girlfriendContact: String = loadedUserConfig?.girlfriendContact ?? "+10000000000"
    
    // MARK: - Ambient Chime
    public static let chimeIntervalSeconds: TimeInterval = loadedUserConfig?.chimeIntervalSeconds ?? 60.0
    
    // MARK: - HealthKit DB Path
    public static let healthDbPath: String = loadedUserConfig?.healthDbPath ?? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/Developer/PersonalTrainer/data/healthkit_history.db"
    }()
    
    // MARK: - Key Wi-Fi Networks
    public static let workWifiSSIDs: [String] = loadedUserConfig?.workWifiSSIDs ?? ["WorkWiFi"]
    public static let homeWifiSSIDs: [String] = loadedUserConfig?.homeWifiSSIDs ?? ["HomeWiFi"]
    public static let girlfriendWifiSSIDs: [String] = loadedUserConfig?.girlfriendWifiSSIDs ?? ["PartnerWiFi"]
    
    // MARK: - Developer / Testing Mode Safeguards
    public static let debugForceCurfewActive: Bool = loadedUserConfig?.debugForceCurfewActive ?? false
    public static let testModeAutoDismissSeconds: Int = loadedUserConfig?.testModeAutoDismissSeconds ?? 20
    public static let idleThresholdSeconds: Double = loadedUserConfig?.idleThresholdSeconds ?? 300.0
    public static let preLockWarningMinutes: [Int] = loadedUserConfig?.preLockWarningMinutes ?? [15, 5, 1]
    public static let defaultDailyLimitMinutes: Int = loadedUserConfig?.defaultDailyLimitMinutes ?? 45
    public static let fileBypassPath: String = loadedUserConfig?.fileBypassPath ?? "/tmp/sst_unlock"
    public static let hotCornerBypassEnabled: Bool = loadedUserConfig?.hotCornerBypassEnabled ?? true
}
