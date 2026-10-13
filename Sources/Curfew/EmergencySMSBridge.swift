import Foundation

public final class EmergencySMSBridge: @unchecked Sendable {
    public static let shared = EmergencySMSBridge()
    
    private init() {}
    
    /// Triggers an accountability iMessage / SMS to the configured emergency contact via Messages.app.
    public func sendEmergencyAlert(reason: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        let recipient = Config.girlfriendContact
        let timeStr = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        
        let messageText = "[Emergency Alert] Curfew Override triggered at \(timeStr). Reason: \"\(reason)\"."
        let escapedMessage = messageText.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedRecipient = recipient.replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = """
        tell application "Messages"
            set sentSuccessfully to false
            try
                set targetChat to (first chat whose id contains "\(escapedRecipient)")
                send "\(escapedMessage)" to targetChat
                set sentSuccessfully to true
            end try
            
            if not sentSuccessfully then
                try
                    set targetBuddy to buddy "\(escapedRecipient)" of (1st service whose service type is iMessage)
                    send "\(escapedMessage)" to targetBuddy
                    set sentSuccessfully to true
                end try
            end if
            
            if not sentSuccessfully then
                try
                    send "\(escapedMessage)" to buddy "\(escapedRecipient)"
                    set sentSuccessfully to true
                end try
            end if
            
            return sentSuccessfully
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: scriptSource) {
                let result = script.executeAndReturnError(&error)
                if let err = error {
                    print("[EmergencySMSBridge] Error sending SMS: \(err)")
                } else {
                    print("[EmergencySMSBridge] Dispatched to \(recipient): \(result.stringValue ?? "sent")")
                }
            }
            completion?(error == nil)
        }
    }
}
