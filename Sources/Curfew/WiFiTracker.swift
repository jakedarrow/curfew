import Foundation
import CoreWLAN

public enum WiFiStrategyProfile: String, Sendable {
    case work = "Work Focus"
    case home = "Home Creative"
    case girlfriend = "Partner Sanctuary"
    case standard = "Standard"
}

public final class WiFiTracker: @unchecked Sendable {
    public static let shared = WiFiTracker()
    
    public private(set) var currentSSID: String = "Unknown"
    public private(set) var currentProfile: WiFiStrategyProfile = .standard
    
    private init() {
        refresh()
    }
    
    public func refresh() {
        if let iface = CWWiFiClient.shared().interface() {
            let ssid = iface.ssid() ?? ""
            self.currentSSID = ssid.isEmpty ? "Unknown" : ssid
            
            if Config.workWifiSSIDs.contains(where: { ssid.localizedCaseInsensitiveContains($0) }) {
                self.currentProfile = .work
            } else if Config.homeWifiSSIDs.contains(where: { ssid.localizedCaseInsensitiveContains($0) }) {
                self.currentProfile = .home
            } else if Config.girlfriendWifiSSIDs.contains(where: { ssid.localizedCaseInsensitiveContains($0) }) {
                self.currentProfile = .girlfriend
            } else {
                self.currentProfile = .standard
            }
        }
    }
}
