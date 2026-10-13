import Cocoa
import EventKit
import Foundation

public final class RemindersBridge: @unchecked Sendable {
    public static let shared = RemindersBridge()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    /// Creates a high-priority follow-up reminder in Apple Reminders scheduled for tomorrow at the given hour/minute (default 6:00 PM).
    /// Uses native EventKit with seamless AppleScript fallback.
    @discardableResult
    public func createSmartNoReminder(
        taskTitle: String,
        notes: String,
        dueHour: Int = 18,
        dueMinute: Int = 0
    ) -> Bool {
        let cleanTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        if let day = comps.day {
            comps.day = day + 1
        }
        comps.hour = dueHour
        comps.minute = dueMinute
        comps.second = 0
        let dueDateComponents = comps
        
        // 1. Try Native EventKit First
        let saveViaEventKit: @Sendable (Bool) -> Void = { [weak self] granted in
            guard let self = self, granted else {
                print("[RemindersBridge] EventKit permission not granted, using AppleScript fallback.")
                self?.createReminderViaAppleScript(title: cleanTitle, notes: notes, dueHour: dueHour, dueMinute: dueMinute)
                return
            }
            
            guard let defaultList = self.eventStore.defaultCalendarForNewReminders() ?? self.eventStore.calendars(for: .reminder).first else {
                print("[RemindersBridge] No default reminder calendar found, using AppleScript fallback.")
                self.createReminderViaAppleScript(title: cleanTitle, notes: notes, dueHour: dueHour, dueMinute: dueMinute)
                return
            }
            
            let reminder = EKReminder(eventStore: self.eventStore)
            reminder.title = cleanTitle
            reminder.notes = notes
            reminder.calendar = defaultList
            reminder.priority = 1 // High Priority
            reminder.dueDateComponents = dueDateComponents
            
            if let dueDate = calendar.date(from: dueDateComponents) {
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
            
            do {
                try self.eventStore.save(reminder, commit: true)
                print("[RemindersBridge] ✅ Native EventKit created reminder: \"\(cleanTitle)\" for tomorrow at \(dueHour):\(dueMinute)")
            } catch {
                print("[RemindersBridge] EventKit save error: \(error). Falling back to AppleScript.")
                self.createReminderViaAppleScript(title: cleanTitle, notes: notes, dueHour: dueHour, dueMinute: dueMinute)
            }
        }
        
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, _ in
                saveViaEventKit(granted)
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in
                saveViaEventKit(granted)
            }
        }
        
        return true
    }
    
    private func createReminderViaAppleScript(title: String, notes: String, dueHour: Int, dueMinute: Int) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = notes.replacingOccurrences(of: "\"", with: "\\\"")
        let secondsFromMidnight = (dueHour * 3600) + (dueMinute * 60)
        
        let scriptSource = """
        tell application "Reminders"
            set targetList to default list
            set tomorrowDate to (current date) + (1 * days)
            set time of tomorrowDate to \(secondsFromMidnight)
            tell targetList
                make new reminder with properties {name:"\(escapedTitle)", body:"\(escapedNotes)", due date:tomorrowDate, priority:1}
            end tell
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                script.executeAndReturnError(&error)
                if let err = error {
                    print("[RemindersBridge] AppleScript fallback error: \(err)")
                } else {
                    print("[RemindersBridge] AppleScript created reminder: \"\(title)\"")
                }
            }
        }
    }
    
    @MainActor
    public func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
