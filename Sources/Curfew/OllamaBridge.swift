import Foundation

public struct OllamaDecisionResponse: Codable, Sendable {
    public let decision: String // "approved", "counter_offer", "denied"
    public let granted_minutes: Int
    public let reasoning: String
    public let suggested_scope: String?
    public let task_title: String?
}

public final class OllamaBridge: @unchecked Sendable {
    public static let shared = OllamaBridge()
    
    private let endpoint = URL(string: "http://localhost:11434/api/chat")!
    private let tagsEndpoint = URL(string: "http://localhost:11434/api/tags")!
    public let preferredModel = "llama3.1:8b"
    
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
    
    /// Evaluates late-night intent with llama3.1:8b, taking sleep debt and urgency into account
    public func evaluateIntent(
        task: String,
        consequence: String,
        requestedMinutes: Int,
        concession: String? = nil,
        round: Int = 1,
        sleepDebtHours: Double,
        lastNightSleepHours: Double,
        minutesPastCurfew: Int
    ) async throws -> OllamaDecisionResponse {
        let systemPrompt = """
You are Curfew's Late-Night Task Arbiter for macOS.
Your goal is to enforce strict bedtime boundaries (10:00 PM - 5:00 AM) to preserve deep sleep recovery, while reasonably accommodating truly critical, urgent deliverables.

USER'S BIOLOGICAL CONTEXT:
- Last night sleep: \(String(format: "%.1f", lastNightSleepHours))h (Target baseline: 8.0h, critical floor: 7.0h)
- 7-day cumulative sleep debt: \(String(format: "%.1f", sleepDebtHours))h
- Minutes past 10:00 PM curfew: \(minutesPastCurfew)m
- Negotiation Round: \(round) of 2

ARBITRATION PRINCIPLES:
1. HIGH URGENCY & IMPACT: If the deliverable is a genuine client emergency, production outage, or imminent morning release deadline, you may approve or counter-offer with a minimal, strictly capped window (usually 10 to 20 minutes, maximum 30m).
2. LOW URGENCY / HABITUAL DELAY: If the task is open-ended exploration, learning, reading, browsing, video watching, or routine organizational chores that can wait until tomorrow, DENY the request ("denied"). Provide a supportive "Smart No" explaining the sleep recovery debt.
3. COUNTER-OFFER: If the task is valid but the requested duration is too long given the sleep debt (e.g. asking for 30m when debt is >4h), counter-offer with a shorter, focused duration (e.g. 10m or 15m) and a specific scoped deliverable ("counter_offer").
4. CONCESSION: If round 2 includes a genuine scope concession, reward the focus by granting a tightly bounded window.
5. NEVER grant more than 30 minutes under any circumstance past curfew.

Output MUST be valid JSON with this exact schema:
{
  "decision": "approved" | "counter_offer" | "denied",
  "granted_minutes": <number between 0 and 30>,
  "reasoning": "<clear, compassionate, direct 1-3 sentence explanation referencing sleep debt and urgency>",
  "suggested_scope": "<brief 3-7 word scope to focus on>",
  "task_title": "<concise 2-5 word task title>"
}
"""

        var userMessage = """
TASK PROPOSAL:
- Task / Deliverable: \(task)
- Consequence if delayed: \(consequence)
- Requested Minutes: \(requestedMinutes)m
"""
        if let concession = concession, !concession.isEmpty {
            userMessage += "\n- Scope Concession (Round \(round)): \(concession)"
        }

        let payload: [String: Any] = [
            "model": preferredModel,
            "stream": false,
            "format": "json",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "options": [
                "temperature": 0.2,
                "num_predict": 256
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
            throw NSError(domain: "OllamaBridge", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Ollama returned error"])
        }

        struct ChatResponse: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }

        let chatResp = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let contentData = chatResp.message.content.data(using: .utf8) else {
            throw NSError(domain: "OllamaBridge", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid content string"])
        }

        let decision = try JSONDecoder().decode(OllamaDecisionResponse.self, from: contentData)
        return decision
    }
}
