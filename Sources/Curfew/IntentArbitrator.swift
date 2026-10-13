import Foundation

public struct ArbitrationResult: Sendable {
    public let isApproved: Bool
    public let grantedMinutes: Int
    public let grantedSeconds: Int
    public let decisionSummary: String
    public let reasoning: String
    public let taskTitle: String
    public let isDivertedToReminders: Bool
    public let isCounterOffer: Bool
    public let suggestedScope: String
    public let round: Int
    
    public init(
        isApproved: Bool,
        grantedMinutes: Int,
        grantedSeconds: Int,
        decisionSummary: String,
        reasoning: String,
        taskTitle: String,
        isDivertedToReminders: Bool,
        isCounterOffer: Bool = false,
        suggestedScope: String = "",
        round: Int = 1
    ) {
        self.isApproved = isApproved
        self.grantedMinutes = grantedMinutes
        self.grantedSeconds = grantedSeconds
        self.decisionSummary = decisionSummary
        self.reasoning = reasoning
        self.taskTitle = taskTitle
        self.isDivertedToReminders = isDivertedToReminders
        self.isCounterOffer = isCounterOffer
        self.suggestedScope = suggestedScope
        self.round = round
    }
}

public final class IntentArbitrator: @unchecked Sendable {
    public static let shared = IntentArbitrator()
    
    private init() {}
    
    /// Evaluates spoken or typed intent based on the Agency Template (Offline Heuristic Fallback):
    /// "I am going to go to bed [X] minutes past my bedtime so that I can [Action]. If I don't do this now, [Impact], and doing it now will [Value]."
    public func evaluate(spokenText: String, followUpHour: Int = 18, followUpMinute: Int = 0) -> ArbitrationResult {
        let sleepMetrics = HealthContextBridge.shared.fetchSleepMetrics()
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        
        var minutesPastCurfew = 0
        if hour >= Config.weeknightBedtimeStartHour {
            minutesPastCurfew = (hour - Config.weeknightBedtimeStartHour) * 60 + minute
        } else if hour < Config.weeknightBedtimeEndHour {
            minutesPastCurfew = (hour + (24 - Config.weeknightBedtimeStartHour)) * 60 + minute
        }
        
        let textLower = spokenText.lowercased()
        
        // 1. Extract requested duration (support seconds for rapid testing)
        var requestedSeconds = 10 * 60
        var isSecondsTest = false
        
        let secRegex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:seconds|second|secs|sec|s)\b"#, options: .caseInsensitive)
        let minRegex = try? NSRegularExpression(pattern: #"(\d+)\s*(?:minutes|mins|min|m)\b"#, options: .caseInsensitive)
        
        if let match = secRegex?.firstMatch(in: spokenText, range: NSRange(spokenText.startIndex..., in: spokenText)),
           let range = Range(match.range(at: 1), in: spokenText), let val = Int(spokenText[range]) {
            requestedSeconds = min(val, 300)
            isSecondsTest = true
        } else if let match = minRegex?.firstMatch(in: spokenText, range: NSRange(spokenText.startIndex..., in: spokenText)),
                  let range = Range(match.range(at: 1), in: spokenText), let val = Int(spokenText[range]) {
            requestedSeconds = min(val, 30) * 60
        }
        
        // 2. Extract Action / Task Title
        var extractedAction = "Late Night Task"
        let markers = ["so that i can", "so that I can", "so i can", "so I can", "in order to", "need to", "want to"]
        for marker in markers {
            if let range = spokenText.range(of: marker, options: .caseInsensitive) {
                let after = spokenText[range.upperBound...]
                let firstSentence = after.components(separatedBy: CharacterSet(charactersIn: ".!\n"))[0]
                let clean = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty && clean.count > 3 {
                    extractedAction = clean
                    break
                }
            }
        }
        
        // 3. Classify Urgency & Consequence
        let highUrgencyKeywords = [
            "deadline", "client", "emergency", "release", "mix", "send", "joe",
            "handoff", "upload", "broken", "fix", "deploy", "server", "bounce", "master", "deliver", "test"
        ]
        let lowUrgencyKeywords = [
            "look at", "explore", "learn", "browse", "tweak", "scroll", "watch",
            "read", "organize", "research", "youtube", "check"
        ]
        
        var urgencyScore = 3.0 // baseline (1-5)
        for kw in highUrgencyKeywords {
            if textLower.contains(kw) {
                urgencyScore += 1.0
            }
        }
        for kw in lowUrgencyKeywords {
            if textLower.contains(kw) {
                urgencyScore -= 1.0
            }
        }
        urgencyScore = max(1.0, min(5.0, urgencyScore))
        
        // 4. Multi-Factor Scoring Math
        var netScore = urgencyScore * 20.0
        
        // Factor in tonight's existing extensions
        let summaryTonight = SessionLedgerManager.shared.summaryForTonight()
        if summaryTonight.totalMinutes > 0 {
            netScore -= Double(summaryTonight.totalMinutes) * 1.5
        }
        if summaryTonight.requests > 1 {
            netScore -= Double(summaryTonight.requests) * 8.0
        }
        
        // Penalty for minutes past curfew
        netScore -= Double(minutesPastCurfew) * 0.4
        
        // Only penalize sleep debt if sleep metrics are fresh
        if !sleepMetrics.isStale {
            netScore -= sleepMetrics.cumulativeSleepDebtHours * 4.0
            if sleepMetrics.lastNightHours < Config.minimumAcceptableSleepHours {
                let deficit = Config.minimumAcceptableSleepHours - sleepMetrics.lastNightHours
                netScore -= (deficit * 18.0)
            }
        }
        
        // 5. Decision Threshold (Passing score: 45.0)
        let isApproved = netScore >= 45.0
        
        if isApproved {
            let grantedSecs = min(requestedSeconds, 15 * 60)
            let grantedMins = max(1, grantedSecs / 60)
            let endObj = calendar.date(byAdding: .second, value: grantedSecs, to: now) ?? now
            let endTimeStr = DateFormatter.localizedString(from: endObj, dateStyle: .none, timeStyle: .short)
            
            let summary = isSecondsTest ? "Approved: \(grantedSecs)s window" : "Approved: \(grantedMins)m window"
            let reasoning = "Granted until \(endTimeStr)."
            
            return ArbitrationResult(
                isApproved: true,
                grantedMinutes: grantedMins,
                grantedSeconds: grantedSecs,
                decisionSummary: summary,
                reasoning: reasoning,
                taskTitle: extractedAction,
                isDivertedToReminders: false
            )
        } else {
            let notes = "Context: \(spokenText)\nCurfew Offset: +\(minutesPastCurfew)m"
            RemindersBridge.shared.createSmartNoReminder(
                taskTitle: extractedAction.capitalized,
                notes: notes,
                dueHour: followUpHour,
                dueMinute: followUpMinute
            )
            
            let timeFmt = followUpHour > 12 ? "\(followUpHour - 12):\(String(format: "%02d", followUpMinute)) PM" : "\(followUpHour):\(String(format: "%02d", followUpMinute)) AM"
            let summary = "Request Denied"
            let reasoning = "Curfew past cutoff. Created follow-up in Reminders for tomorrow \(timeFmt)."
            
            return ArbitrationResult(
                isApproved: false,
                grantedMinutes: 0,
                grantedSeconds: 0,
                decisionSummary: summary,
                reasoning: reasoning,
                taskTitle: extractedAction,
                isDivertedToReminders: true
            )
        }
    }
    
    /// Evaluates late-night intent using local Ollama model (llama3.1:8b) with continuous multi-turn memory
    public func evaluateWithAI(
        task: String,
        consequence: String,
        requestedMinutes: Int,
        concession: String? = nil,
        round: Int = 1,
        followUpHour: Int = 18,
        followUpMinute: Int = 0
    ) async -> ArbitrationResult {
        do {
            let aiResponse = try await OllamaBridge.shared.evaluateIntent(
                task: task,
                consequence: consequence,
                requestedMinutes: requestedMinutes,
                concession: concession,
                round: round
            )
            
            let isApproved = aiResponse.decision.lowercased() == "approved"
            let isCounter = aiResponse.decision.lowercased() == "counter_offer"
            let title = aiResponse.task_title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? aiResponse.task_title! : task
            let scope = aiResponse.suggested_scope?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? aiResponse.suggested_scope! : task
            
            if isApproved || isCounter {
                let grantedMins = max(1, min(30, aiResponse.granted_minutes))
                let summary = isCounter ? "AI Counter-Offer: \(grantedMins)m" : "Approved: \(grantedMins)m window"
                
                return ArbitrationResult(
                    isApproved: true,
                    grantedMinutes: grantedMins,
                    grantedSeconds: grantedMins * 60,
                    decisionSummary: summary,
                    reasoning: aiResponse.reasoning,
                    taskTitle: title,
                    isDivertedToReminders: false,
                    isCounterOffer: isCounter,
                    suggestedScope: scope,
                    round: round
                )
            } else {
                let summary = "Request Denied"
                
                // If denied, create follow-up reminder
                RemindersBridge.shared.createSmartNoReminder(
                    taskTitle: title.capitalized,
                    notes: "Late night task diverted: \(task). Consequence noted: \(consequence).",
                    dueHour: followUpHour,
                    dueMinute: followUpMinute
                )
                
                return ArbitrationResult(
                    isApproved: false,
                    grantedMinutes: 0,
                    grantedSeconds: 0,
                    decisionSummary: summary,
                    reasoning: aiResponse.reasoning,
                    taskTitle: title,
                    isDivertedToReminders: true,
                    isCounterOffer: false,
                    suggestedScope: "",
                    round: round
                )
            }
        } catch {
            print("[IntentArbitrator] Ollama evaluation unavailable (\(error.localizedDescription)). Falling back to heuristic reasoning.")
            let spoken = "I am going to go to bed \(requestedMinutes) minutes past my bedtime so that I can \(task). If I don't do this now, \(consequence)."
            let heuristic = evaluate(spokenText: spoken, followUpHour: followUpHour, followUpMinute: followUpMinute)
            return ArbitrationResult(
                isApproved: heuristic.isApproved,
                grantedMinutes: heuristic.grantedMinutes,
                grantedSeconds: heuristic.grantedSeconds,
                decisionSummary: heuristic.decisionSummary,
                reasoning: heuristic.reasoning,
                taskTitle: heuristic.taskTitle,
                isDivertedToReminders: heuristic.isDivertedToReminders,
                isCounterOffer: heuristic.isCounterOffer,
                suggestedScope: heuristic.suggestedScope,
                round: round
            )
        }
    }
}
