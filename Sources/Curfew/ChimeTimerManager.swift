import AppKit
import Foundation

@MainActor
public final class ChimeTimerManager {
    public static let shared = ChimeTimerManager()
    
    private var countdownTimer: Timer?
    private var chimeTimer: Timer?
    
    public private(set) var isSessionActive: Bool = false
    public private(set) var secondsRemaining: Int = 0
    public private(set) var currentTaskName: String = ""
    
    public var onTick: ((Int) -> Void)?
    public var onSessionEnded: (() -> Void)?
    public var onSessionExpired: ((String) -> Void)?
    
    private init() {}
    
    public func startSession(minutes: Int, taskName: String) {
        startSession(seconds: minutes * 60, taskName: taskName)
    }
    
    public func startSession(seconds: Int, taskName: String) {
        stopSession()
        
        self.isSessionActive = true
        self.secondsRemaining = max(1, seconds)
        self.currentTaskName = taskName
        
        // Initial soft chime
        playChime()
        
        // Countdown timer (every 1 second)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.secondsRemaining -= 1
                self.onTick?(self.secondsRemaining)
                
                if self.secondsRemaining <= 0 {
                    let task = self.currentTaskName
                    self.finishSession(reason: "Time Expired")
                    self.onSessionExpired?(task)
                }
            }
        }
        
        // Periodic ambient chime (every 60 seconds)
        chimeTimer = Timer.scheduledTimer(withTimeInterval: Config.chimeIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSessionActive else { return }
                self.playChime()
            }
        }
    }
    
    public func markDoneEarly() {
        finishSession(reason: "Done Early")
    }
    
    public func stopSession() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        chimeTimer?.invalidate()
        chimeTimer = nil
        isSessionActive = false
        secondsRemaining = 0
        currentTaskName = ""
    }
    
    private func finishSession(reason: String) {
        print("[ChimeTimer] Session finished: \(reason)")
        stopSession()
        
        // Sound completion chime
        NSSound(named: "Glass")?.play()
        
        onSessionEnded?()
    }
    
    private func playChime() {
        // Soft ambient tick/chime
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.5
            sound.play()
        }
    }
}
