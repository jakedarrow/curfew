import Foundation

public struct OllamaDecisionResponse: Codable, Sendable {
    public let internal_critique: String?
    public let decision: String // "approved", "counter_offer", "denied"
    public let granted_minutes: Int
    public let reasoning: String
    public let suggested_scope: String?
    public let task_title: String?
    
    public init(
        internal_critique: String? = nil,
        decision: String,
        granted_minutes: Int,
        reasoning: String,
        suggested_scope: String? = nil,
        task_title: String? = nil
    ) {
        self.internal_critique = internal_critique
        self.decision = decision
        self.granted_minutes = granted_minutes
        self.reasoning = reasoning
        self.suggested_scope = suggested_scope
        self.task_title = task_title
    }
}

public final class OllamaBridge: @unchecked Sendable {
    public static let shared = OllamaBridge()
    
    private let endpoint = URL(string: "http://localhost:11434/api/chat")!
    private let tagsEndpoint = URL(string: "http://localhost:11434/api/tags")!
    public let preferredModel = "llama3.1:8b"
    
    // MARK: - 100% Static System Prompt (Optimization A: GPU Prefix Caching)
    // By keeping this string completely invariant across all requests, Ollama's KV cache
    // reuses attention tensors from VRAM, dropping prompt eval duration from 1.7s to <80ms.
    public static let staticSystemPrompt = """
    You are Curfew's Late-Night Task Arbiter for macOS.
    Your goal is to enforce strict bedtime boundaries (10:00 PM - 5:00 AM) to preserve deep sleep and biological recovery, while reasonably accommodating truly critical, urgent deliverables.

    ARBITRATION PRINCIPLES:
    1. TONIGHT'S SESSION HISTORY: Pay close attention to previous messages in this conversation. If the user was already granted extensions earlier tonight and is asking for more time, or is stalling on the same task, treat this as bedtime procrastination. Be much firmer.
    2. HIGH URGENCY & IMPACT: If the deliverable is a genuine client emergency, production outage, or urgent hard deadline, you may approve or counter-offer with a minimal, strictly capped window (usually 10 to 15 minutes, absolute maximum 25m).
    3. LOW URGENCY / HABITUAL DELAY: If the task is open-ended exploration, refactoring, learning, browsing, reading, or chores that can wait until tomorrow, DENY the request ("denied"). Provide a clear, supportive rationale highlighting tomorrow's commitments and recovery.
    4. COUNTER-OFFER: If the task is valid but the requested duration is too long given the hour and schedule, counter-offer with a shorter, tightly bounded duration (e.g. 10m) and a specific scoped stopping point ("counter_offer").
    5. SCOPE CONCESSION: If the user provides a genuine, meaningful scope concession in response to a counter-offer, reward the focus by approving the proposed bounded window.
    6. MAXIMUM CEILING: Never grant more than 30 minutes in a single request under any circumstance past curfew.

    CHAIN-OF-THOUGHT INSTRUCTION:
    In your "internal_critique" field, evaluate the user's request honestly:
    - Assess: How many extensions have they already had tonight? What time is it past curfew?
    - Analyze: What app are they using? Is this real emergency work or late-night rabbit-holing?
    - Consider: When is their first morning event tomorrow? Will staying up compromise their critical sleep floor?
    Then formulate your final decision, granted minutes, and public message.

    Output MUST be valid JSON with this exact schema:
    {
      "internal_critique": "<private model scratchpad: analyze past requests tonight, time past curfew, wake constraints, and urgency>",
      "decision": "approved" | "counter_offer" | "denied",
      "granted_minutes": <number between 0 and 30>,
      "suggested_scope": "<brief 3-7 word scope to focus on>",
      "reasoning": "<supportive, clear, firm 1-3 sentence message to user explaining the decision>",
      "task_title": "<concise 2-5 word task title>"
    }
    """
    
    private init() {}
    
    /// Checks if local Ollama server is responding
    public func isOllamaAvailable() async -> Bool {
        var request = URLRequest(url: tagsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Evaluates late-night intent with llama3.1:8b using native multi-turn conversation history.
    public func evaluateIntent(
        task: String,
        consequence: String,
        requestedMinutes: Int,
        concession: String? = nil,
        round: Int = 1,
        activeAppName: String? = nil
    ) async throws -> OllamaDecisionResponse {
        let sleepMetrics = HealthContextBridge.shared.fetchSleepMetrics()
        let tomorrowSchedule = CalendarBridge.shared.fetchTomorrowMorningSchedule()
        
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
        
        let appName: String
        if let active = activeAppName {
            appName = active
        } else {
            appName = await MainActor.run { AppTracker.shared.activeAppName }
        }
        
        // 1. Build or record turn into tonight's continuous session ledger
        let ledger = SessionLedgerManager.shared
        
        if round == 1 {
            let contextPayload = """
            - Current Time: \(String(format: "%02d:%02d", hour, minute)) (\(minutesPastCurfew)m past curfew)
            - Active App at Lock: \(appName)
            \(tomorrowSchedule.promptDescription)
            \(sleepMetrics.promptDescription)
            """
            ledger.recordUserRequest(
                task: task,
                consequence: consequence,
                requestedMinutes: requestedMinutes,
                contextInfo: contextPayload
            )
        } else if let concessionText = concession, !concessionText.isEmpty {
            ledger.recordUserConcession(concession: concessionText)
        }
        
        // 2. Assemble native multi-turn message array
        var messages: [[String: String]] = [
            ["role": "system", "content": OllamaBridge.staticSystemPrompt]
        ]
        messages.append(contentsOf: ledger.getMessagesForOllama())
        
        // 3. Build Ollama API Payload with keep_alive to keep model warm in VRAM
        let payload: [String: Any] = [
            "model": preferredModel,
            "stream": false,
            "format": "json",
            "keep_alive": "60m",
            "messages": messages,
            "options": [
                "temperature": 0.2,
                "num_predict": 350
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 25.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "OllamaBridge",
                code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP error"]
            )
        }
        
        struct ChatResponse: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        
        let chatResp = try JSONDecoder().decode(ChatResponse.self, from: data)
        let rawContent = chatResp.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip markdown code fences if model enclosed JSON
        var cleanedJson = rawContent
        if cleanedJson.hasPrefix("```json") {
            cleanedJson = String(cleanedJson.dropFirst(7))
        } else if cleanedJson.hasPrefix("```") {
            cleanedJson = String(cleanedJson.dropFirst(3))
        }
        if cleanedJson.hasSuffix("```") {
            cleanedJson = String(cleanedJson.dropLast(3))
        }
        cleanedJson = cleanedJson.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let contentData = cleanedJson.data(using: .utf8) else {
            throw NSError(domain: "OllamaBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid content string"])
        }
        
        let decision = try JSONDecoder().decode(OllamaDecisionResponse.self, from: contentData)
        
        // 4. Record assistant's decision in tonight's ledger
        ledger.recordAssistantResponse(rawJsonContent: cleanedJson, grantedMinutes: decision.granted_minutes)
        
        return decision
    }
}
