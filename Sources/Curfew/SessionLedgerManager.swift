import Foundation

public struct SessionTurn: Codable, Sendable {
    public let role: String // "user" or "assistant"
    public let content: String
    public let timestamp: String
    
    public init(role: String, content: String, timestamp: String = SessionTurn.currentTimestamp()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    public static func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
}

public struct TonightLedger: Codable, Sendable {
    public var sessionNight: String // e.g. "2026-10-12"
    public var turns: [SessionTurn]
    public var totalGrantedMinutes: Int
    public var requestsCount: Int
    public var lastTaskTitle: String?
    
    public static func empty(for night: String) -> TonightLedger {
        TonightLedger(
            sessionNight: night,
            turns: [],
            totalGrantedMinutes: 0,
            requestsCount: 0,
            lastTaskTitle: nil
        )
    }
}

/// Manages tonight's persistent multi-turn conversational session ledger (`~/.config/curfew/session_ledger.json`).
/// Automatically resets at Curfew's end hour (5:00 AM) each day, giving the LLaMA model
/// an unbroken memory of all requests, counter-offers, concessions, and completed work tonight.
public final class SessionLedgerManager: @unchecked Sendable {
    public static let shared = SessionLedgerManager()
    
    private let fileURL: URL
    private let lock = NSLock()
    private var ledger: TonightLedger
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config/curfew", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        self.fileURL = configDir.appendingPathComponent("session_ledger.json")
        
        let currentNight = SessionLedgerManager.currentCurfewNightIdentifier()
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(TonightLedger.self, from: data),
           loaded.sessionNight == currentNight {
            self.ledger = loaded
        } else {
            self.ledger = TonightLedger.empty(for: currentNight)
            // Persist fresh ledger
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let freshData = try? encoder.encode(self.ledger) {
                try? freshData.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    /// Curfew night runs from 10:00 PM (hour 22) through 5:00 AM (hour 5).
    /// If current hour is between 00:00 and 04:59, it belongs to yesterday's curfew night.
    public static func currentCurfewNightIdentifier() -> String {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if hour < Config.weeknightBedtimeEndHour {
            // Early morning hours (e.g. 1:30 AM) belong to the night that started yesterday
            if let yesterday = cal.date(byAdding: .day, value: -1, to: now) {
                return formatter.string(from: yesterday)
            }
        }
        return formatter.string(from: now)
    }
    
    private func checkNightRolloverLocked() {
        let currentNight = SessionLedgerManager.currentCurfewNightIdentifier()
        if ledger.sessionNight != currentNight {
            ledger = TonightLedger.empty(for: currentNight)
            saveLocked()
        }
    }
    
    /// Returns the active message list in OpenAI/Ollama role format `[["role": "...", "content": "..."]]`
    public func getMessagesForOllama() -> [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        return ledger.turns.map { ["role": $0.role, "content": $0.content] }
    }
    
    /// Records a user request into tonight's ledger
    public func recordUserRequest(
        task: String,
        consequence: String,
        requestedMinutes: Int,
        contextInfo: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        
        ledger.requestsCount += 1
        ledger.lastTaskTitle = task
        
        let timeStr = SessionTurn.currentTimestamp()
        let messageText = """
        [\(timeStr)] Late-Night Extension Request:
        - Task: \(task)
        - Consequence if delayed: \(consequence)
        - Requested: \(requestedMinutes) minutes
        \(contextInfo)
        """
        
        ledger.turns.append(SessionTurn(role: "user", content: messageText, timestamp: timeStr))
        saveLocked()
    }
    
    /// Records the assistant's structured decision response into tonight's ledger
    public func recordAssistantResponse(rawJsonContent: String, grantedMinutes: Int) {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        
        if grantedMinutes > 0 {
            ledger.totalGrantedMinutes += grantedMinutes
        }
        
        let timeStr = SessionTurn.currentTimestamp()
        ledger.turns.append(SessionTurn(role: "assistant", content: rawJsonContent, timestamp: timeStr))
        saveLocked()
    }
    
    /// Records a user concession in Round 2 of negotiation
    public func recordUserConcession(concession: String) {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        
        let timeStr = SessionTurn.currentTimestamp()
        let messageText = """
        [\(timeStr)] Scope Concession (Round 2):
        "\(concession)"
        """
        
        ledger.turns.append(SessionTurn(role: "user", content: messageText, timestamp: timeStr))
        saveLocked()
    }
    
    /// Records when an extension completes or user clicks Task Complete
    public func recordExtensionCompleted(taskTitle: String, minutes: Int, early: Bool) {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        
        let timeStr = SessionTurn.currentTimestamp()
        let note = early
            ? "[\(timeStr)] User marked '\(taskTitle)' complete EARLY before timer expired."
            : "[\(timeStr)] Granted window of \(minutes)m for '\(taskTitle)' expired. Lock screen engaged."
            
        // Append as a user-side context observation so the model is aware of the expired window
        ledger.turns.append(SessionTurn(role: "user", content: note, timestamp: timeStr))
        saveLocked()
    }
    
    /// Returns quick metrics for tonight's activity
    public func summaryForTonight() -> (requests: Int, totalMinutes: Int, lastTask: String?) {
        lock.lock()
        defer { lock.unlock() }
        checkNightRolloverLocked()
        return (ledger.requestsCount, ledger.totalGrantedMinutes, ledger.lastTaskTitle)
    }
    
    private func saveLocked() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(ledger) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
