import Foundation
import EventKit

public struct TomorrowSchedule: Sendable {
    public let hasMorningEvent: Bool
    public let eventTitle: String?
    public let startTimeFormatted: String?
    public let promptDescription: String
    
    public static var clearMorning: TomorrowSchedule {
        TomorrowSchedule(
            hasMorningEvent: false,
            eventTitle: nil,
            startTimeFormatted: nil,
            promptDescription: "- Tomorrow's Schedule: Clear — no early morning commitments scheduled before 1:00 PM."
        )
    }
}

/// Queries Apple Calendar via native EventKit (with AppleScript fallback)
/// to find tomorrow morning's earliest scheduled non-all-day event before 1:00 PM.
public final class CalendarBridge: @unchecked Sendable {
    public static let shared = CalendarBridge()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    /// Synchronously fetches tomorrow morning's schedule for prompt context.
    public func fetchTomorrowMorningSchedule() -> TomorrowSchedule {
        let calendar = Calendar.current
        let now = Date()
        
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return .clearMorning
        }
        
        // Window: Tomorrow 5:00 AM to 1:00 PM (13:00)
        var startComps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        startComps.hour = 5
        startComps.minute = 0
        startComps.second = 0
        
        var endComps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        endComps.hour = 13
        endComps.minute = 0
        endComps.second = 0
        
        guard let windowStart = calendar.date(from: startComps),
              let windowEnd = calendar.date(from: endComps) else {
            return .clearMorning
        }
        
        // 1. Try Native EventKit
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status.rawValue == 3 {
            let predicate = eventStore.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
            let events = eventStore.events(matching: predicate)
                .filter { !$0.isAllDay && $0.startDate >= windowStart }
                .sorted { $0.startDate < $1.startDate }
            
            if let firstEvent = events.first {
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                let timeStr = formatter.string(from: firstEvent.startDate)
                let title = firstEvent.title ?? "Scheduled Event"
                
                return TomorrowSchedule(
                    hasMorningEvent: true,
                    eventTitle: title,
                    startTimeFormatted: timeStr,
                    promptDescription: "- Tomorrow's Schedule: Earliest commitment is '\(title)' at \(timeStr)."
                )
            } else {
                return .clearMorning
            }
        }
        
        // 2. Try AppleScript Fallback if EventKit not authorized
        if let scriptResult = fetchEarliestEventViaAppleScript() {
            return scriptResult
        }
        
        return .clearMorning
    }
    
    /// Asynchronously requests access to Apple Calendar if not yet determined.
    public func requestCalendarAccessIfNeeded() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { _, _ in }
            } else {
                eventStore.requestAccess(to: .event) { _, _ in }
            }
        }
    }
    
    private func fetchEarliestEventViaAppleScript() -> TomorrowSchedule? {
        let scriptSource = """
        tell application "Calendar"
            set tomorrowStart to (current date) + 1 * days
            set hours of tomorrowStart to 5
            set minutes of tomorrowStart to 0
            set seconds of tomorrowStart to 0
            
            set tomorrowEnd to (current date) + 1 * days
            set hours of tomorrowEnd to 13
            set minutes of tomorrowEnd to 0
            set seconds of tomorrowEnd to 0
            
            set foundTitle to ""
            set foundTime to ""
            set earliestDate to tomorrowEnd
            
            repeat with c in calendars
                set evs to (events of c whose start date >= tomorrowStart and start date < tomorrowEnd and allday event is false)
                repeat with ev in evs
                    if (start date of ev) < earliestDate then
                        set earliestDate to (start date of ev)
                        set foundTitle to (summary of ev)
                        set foundTime to time string of (start date of ev)
                    end if
                end repeat
            end repeat
            
            if foundTitle is not "" then
                return foundTitle & "||" & foundTime
            else
                return "NONE"
            end if
        end tell
        """
        
        var error: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource),
              let output = script.executeAndReturnError(&error).stringValue else {
            return nil
        }
        
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "NONE" || trimmed.isEmpty {
            return .clearMorning
        }
        
        let parts = trimmed.components(separatedBy: "||")
        if parts.count >= 2 {
            let title = parts[0]
            let timeStr = parts[1]
            return TomorrowSchedule(
                hasMorningEvent: true,
                eventTitle: title,
                startTimeFormatted: timeStr,
                promptDescription: "- Tomorrow's Schedule: Earliest commitment is '\(title)' at \(timeStr)."
            )
        }
        
        return nil
    }
}
