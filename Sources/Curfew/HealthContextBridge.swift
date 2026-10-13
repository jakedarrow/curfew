import Foundation
import SQLite3

public struct SleepMetrics: Sendable {
    public let lastNightHours: Double
    public let sevenDayAvgHours: Double
    public let cumulativeSleepDebtHours: Double
    public let acuteSleepDebtHours: Double
    public let consecutiveUnderSleptDays: Int
    public let sleepEfficiencyPct: Double
    
    public static var fallback: SleepMetrics {
        SleepMetrics(
            lastNightHours: 7.5,
            sevenDayAvgHours: 7.5,
            cumulativeSleepDebtHours: 0.0,
            acuteSleepDebtHours: 0.0,
            consecutiveUnderSleptDays: 0,
            sleepEfficiencyPct: 95.0
        )
    }
}

public final class HealthContextBridge: @unchecked Sendable {
    public static let shared = HealthContextBridge()
    
    private init() {}
    
    public func fetchSleepMetrics() -> SleepMetrics {
        let dbPath = Config.healthDbPath
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return .fallback
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return .fallback
        }
        defer { sqlite3_close(db) }
        
        let query = """
            SELECT sleep_date, total_sleep_hours, sleep_efficiency_pct
            FROM nightly_sleep
            ORDER BY sleep_date DESC
            LIMIT 7;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return .fallback
        }
        defer { sqlite3_finalize(stmt) }
        
        var sleepHistory: [(date: String, hours: Double, efficiency: Double)] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dateStr = String(cString: sqlite3_column_text(stmt, 0))
            let hours = sqlite3_column_double(stmt, 1)
            let efficiency = sqlite3_column_double(stmt, 2)
            sleepHistory.append((dateStr, hours, efficiency))
        }
        
        guard let latest = sleepHistory.first else {
            return .fallback
        }
        
        let totalHours = sleepHistory.reduce(0.0) { $0 + $1.hours }
        let avgHours = totalHours / Double(sleepHistory.count)
        
        // Count consecutive days below minimum threshold (7.0h)
        var consecutiveUnderSlept = 0
        for item in sleepHistory {
            if item.hours < Config.minimumAcceptableSleepHours {
                consecutiveUnderSlept += 1
            } else {
                break
            }
        }
        
        // Acute single-night debt (difference against 8.0h target)
        let acuteDebt = max(0.0, Config.targetSleepHours - latest.hours)
        
        // Cumulative 7-day sleep debt (Whoop/Oura standard: rolling sum of target - actual)
        let cumulativeDebt = sleepHistory.reduce(0.0) { sum, item in
            sum + (Config.targetSleepHours - item.hours)
        }
        let safeCumulativeDebt = max(0.0, cumulativeDebt)
        
        return SleepMetrics(
            lastNightHours: (latest.hours * 10).rounded() / 10,
            sevenDayAvgHours: (avgHours * 10).rounded() / 10,
            cumulativeSleepDebtHours: (safeCumulativeDebt * 10).rounded() / 10,
            acuteSleepDebtHours: (acuteDebt * 10).rounded() / 10,
            consecutiveUnderSleptDays: consecutiveUnderSlept,
            sleepEfficiencyPct: (latest.efficiency * 10).rounded() / 10
        )
    }
}
