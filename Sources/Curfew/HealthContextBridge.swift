import Foundation
import SQLite3

public struct SleepMetrics: Sendable {
    public let lastNightHours: Double
    public let sevenDayAvgHours: Double
    public let cumulativeSleepDebtHours: Double
    public let acuteSleepDebtHours: Double
    public let consecutiveUnderSleptDays: Int
    public let sleepEfficiencyPct: Double
    public let isStale: Bool
    public let daysSinceLastSync: Int
    public let lastSyncDateString: String
    public let deepSleepHours: Double
    public let remSleepHours: Double
    public let promptDescription: String
    
    public static var fallback: SleepMetrics {
        SleepMetrics(
            lastNightHours: 7.5,
            sevenDayAvgHours: 7.5,
            cumulativeSleepDebtHours: 0.0,
            acuteSleepDebtHours: 0.0,
            consecutiveUnderSleptDays: 0,
            sleepEfficiencyPct: 95.0,
            isStale: true,
            daysSinceLastSync: 0,
            lastSyncDateString: "None",
            deepSleepHours: 1.2,
            remSleepHours: 1.4,
            promptDescription: "- Sleep Tracking Status: No local database found. Baseline recovery need is \(Config.targetSleepHours)h."
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
        
        // Fetch last 10 nights to analyze streak and stages
        let query = """
            SELECT sleep_date, total_sleep_hours, deep_hours, rem_hours, sleep_efficiency_pct
            FROM nightly_sleep
            ORDER BY sleep_date DESC
            LIMIT 10;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return .fallback
        }
        defer { sqlite3_finalize(stmt) }
        
        struct NightRecord {
            let dateStr: String
            let date: Date?
            let hours: Double
            let deep: Double
            let rem: Double
            let efficiency: Double
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Calendar.current.timeZone
        
        var records: [NightRecord] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dateStr = String(cString: sqlite3_column_text(stmt, 0))
            let hours = sqlite3_column_double(stmt, 1)
            let deep = sqlite3_column_double(stmt, 2)
            let rem = sqlite3_column_double(stmt, 3)
            let efficiency = sqlite3_column_double(stmt, 4)
            let parsedDate = formatter.date(from: dateStr)
            records.append(NightRecord(dateStr: dateStr, date: parsedDate, hours: hours, deep: deep, rem: rem, efficiency: efficiency))
        }
        
        guard let latest = records.first, let latestDate = latest.date else {
            return .fallback
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Compute difference between today and the latest recorded sleep date
        let startOfToday = calendar.startOfDay(for: now)
        let startOfLatest = calendar.startOfDay(for: latestDate)
        let components = calendar.dateComponents([.day], from: startOfLatest, to: startOfToday)
        let daysAgo = components.day ?? 0
        
        // Freshness Gate: If latest record is older than 1 day (or > 36 hours), data is stale
        let isStale = daysAgo > 1
        
        if isStale {
            // Do not invent active sleep debt from stale data. State the exact facts.
            let historicalAvg = records.prefix(7).reduce(0.0) { $0 + $1.hours } / Double(min(records.count, 7))
            let promptText = """
            - Sleep Tracking Status: Inactive / Not Synced Recently (Last sync was \(latest.dateStr), \(daysAgo) days ago).
            - Historical 7-day baseline from that period: \(String(format: "%.1f", historicalAvg))h/night.
            - Note: Do NOT assume month-old data represents last night. Rely on standard 8.0h baseline recovery need, current time past curfew, session history tonight, and tomorrow's calendar.
            """
            
            return SleepMetrics(
                lastNightHours: latest.hours,
                sevenDayAvgHours: (historicalAvg * 10).rounded() / 10,
                cumulativeSleepDebtHours: 0.0,
                acuteSleepDebtHours: 0.0,
                consecutiveUnderSleptDays: 0,
                sleepEfficiencyPct: latest.efficiency,
                isStale: true,
                daysSinceLastSync: daysAgo,
                lastSyncDateString: latest.dateStr,
                deepSleepHours: latest.deep,
                remSleepHours: latest.rem,
                promptDescription: promptText
            )
        }
        
        // --- Fresh Data Branch ---
        // Find consecutive unbroken days backwards from last night
        var consecutiveStreak: [NightRecord] = [latest]
        var prevDate = latestDate
        
        for record in records.dropFirst() {
            guard let rDate = record.date else { break }
            let dayDiff = calendar.dateComponents([.day], from: calendar.startOfDay(for: rDate), to: calendar.startOfDay(for: prevDate)).day ?? 0
            if dayDiff == 1 {
                consecutiveStreak.append(record)
                prevDate = rDate
            } else {
                break // Gap detected in consecutive streak
            }
            if consecutiveStreak.count >= 7 { break }
        }
        
        let streakCount = consecutiveStreak.count
        let totalHours = consecutiveStreak.reduce(0.0) { $0 + $1.hours }
        let avgHours = totalHours / Double(streakCount)
        
        // Count consecutive days below minimum acceptable threshold
        var consecutiveUnderSlept = 0
        for item in consecutiveStreak {
            if item.hours < Config.minimumAcceptableSleepHours {
                consecutiveUnderSlept += 1
            } else {
                break
            }
        }
        
        let acuteDebt = max(0.0, Config.targetSleepHours - latest.hours)
        let cumulativeDebt = consecutiveStreak.reduce(0.0) { sum, item in
            sum + max(0.0, Config.targetSleepHours - item.hours)
        }
        
        let promptText = """
        - Sleep Tracking Status: Fresh (Last night: \(latest.dateStr)).
        - Last Night: \(String(format: "%.1f", latest.hours))h (Deep: \(String(format: "%.1f", latest.deep))h, REM: \(String(format: "%.1f", latest.rem))h, Efficiency: \(String(format: "%.1f", latest.efficiency))%).
        - Consecutive Tracked Streak: \(streakCount) nights (Average: \(String(format: "%.1f", avgHours))h/night).
        - Cumulative Sleep Debt: \(String(format: "%.1f", cumulativeDebt))h (Acute last night: \(String(format: "%.1f", acuteDebt))h).
        """
        
        return SleepMetrics(
            lastNightHours: (latest.hours * 10).rounded() / 10,
            sevenDayAvgHours: (avgHours * 10).rounded() / 10,
            cumulativeSleepDebtHours: (cumulativeDebt * 10).rounded() / 10,
            acuteSleepDebtHours: (acuteDebt * 10).rounded() / 10,
            consecutiveUnderSleptDays: consecutiveUnderSlept,
            sleepEfficiencyPct: (latest.efficiency * 10).rounded() / 10,
            isStale: false,
            daysSinceLastSync: daysAgo,
            lastSyncDateString: latest.dateStr,
            deepSleepHours: (latest.deep * 10).rounded() / 10,
            remSleepHours: (latest.rem * 10).rounded() / 10,
            promptDescription: promptText
        )
    }
}
