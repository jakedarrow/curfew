# Curfew

A strict, ambient bedtime enforcement and AI-arbitrated sleep recovery agent for macOS.

Curfew eliminates late-night doomscrolling and midnight rabbit holes by locking your screen when bedtime arrives. When you genuinely need an extension for an urgent task, Curfew doesn't rely on willpower—it uses a local LLM to arbitrate your intent, negotiate a minimal scope, or automatically defer the task to Apple Reminders for tomorrow.

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0+-black?style=flat&logo=apple&logoColor=white" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat&logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Ollama-llama3.1%3A8b-purple?style=flat" alt="Ollama llama3.1:8b">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat" alt="License MIT">
</p>

---

### What it does

* **Enforced Bedtime Lock:** When your curfew window starts (default 10:00 PM), Curfew renders a full-screen, system-level lock screen with progressive warning pulses (15 min, 5 min, 1 min) before engagement.
* **AI Task Arbitrator:** Need to request a late-night extension? Curfew queries a local LLM via [Ollama](https://ollama.ai) (`llama3.1:8b`) to rigorously evaluate whether your task is a true emergency or dopamine-seeking rationalization.
* **Two-Round Scope Negotiation:** If your request is potentially valid, the arbitrator negotiates a tightly scoped, minimal sub-task and grants a bounded time window (e.g. 15–30 minutes).
* **"Smart No" with Apple Reminders Deferral:** If your request is rejected, Curfew captures the task title, context, and estimated duration, then automatically creates a priority task in **Apple Reminders** due tomorrow at 6:00 PM—clearing your head so you can sleep.
* **Floating Countdown HUD:** During an approved extension window, a non-intrusive floating pill hovers over full-screen apps displaying your remaining minutes, accompanied by gentle ambient audio chimes.
* **Social Accountability Lifeline:** Bypassing curfew in a true emergency requires entering a reason, which dispatches an automated alert SMS/iMessage to your designated accountability partner.
* **Network & Context Awareness:** Detects your active Wi-Fi profile (Work Focus, Home Creative, Partner Sanctuary) and local HealthKit sleep trends to dynamically calibrate enforcement strictness.
* **Interactive Dry Run / Test Mode:** Full-featured developer test mode (`--test-mode`) with configurable or untimed auto-dismiss options, allowing you to test lock screen interactions and task negotiations safely during the day.
* **100% Local & Private:** Built with native Swift and AppKit. All AI inference runs locally on your Mac; personal preferences and contacts live securely in `~/.config/curfew/config.json`.

---

### Prerequisites

* macOS Sonoma (14.0) or later
* Xcode Command Line Tools (`xcode-select --install`)
* *(Optional, for AI arbitration)* [Ollama](https://ollama.ai) installed with `llama3.1:8b`:
  ```bash
  ollama pull llama3.1:8b
  ```

---

### Quick Start & Installation

Clone this repository and run the automated bundler:

```bash
git clone https://github.com/jakedarrow/curfew.git
cd curfew
./bundle_app.sh
```

`bundle_app.sh` compiles the release binary, generates the high-resolution app icon, packages `/Applications/Curfew.app`, and registers it cleanly with LaunchServices.

To launch Curfew at login, open **System Settings > General > Login Items** and add `/Applications/Curfew.app`.

---

### Configuration

Curfew works out-of-the-box with sensible defaults. To customize your schedule, emergency contact, or allowed apps, create a configuration file at `~/.config/curfew/config.json`:

```json
{
  "weeknightBedtimeStartHour": 22,
  "weeknightBedtimeEndHour": 5,
  "targetSleepHours": 8.0,
  "minimumAcceptableSleepHours": 7.0,
  "girlfriendContact": "+14255550199",
  "chimeIntervalSeconds": 60.0,
  "homeWifiSSIDs": ["MyHomeNetwork"],
  "workWifiSSIDs": ["OfficeWiFi"],
  "girlfriendWifiSSIDs": ["PartnerWiFi"],
  "weekendAllowedApps": [
    "Logic Pro",
    "Xcode",
    "Visual Studio Code",
    "Terminal",
    "Finder"
  ],
  "weekendAlwaysBlockedDomains": [
    "youtube.com",
    "instagram.com",
    "reddit.com",
    "twitter.com",
    "x.com"
  ],
  "hotCornerBypassEnabled": true
}
```

---

### Testing & Dry Run

Curfew includes built-in commands to test the lock UI safely without getting locked out:

```bash
# Launch interactive dry run with 20-second safety timeout
/Applications/Curfew.app/Contents/MacOS/Curfew --test-mode

# Launch interactive dry run without auto-dismiss timeout (test full flows)
/Applications/Curfew.app/Contents/MacOS/Curfew --test-mode --untimed
```

Or click **Curfew** in the macOS menu bar and choose **Dry Run Bedtime Lock**.

---

### Support

If Curfew saved your sleep or helped you reclaim your evenings, feel free to support the project:

[![Support on Ko-fi](https://img.shields.io/badge/Ko--fi-Support%20the%20Project-29abe0?style=flat&logo=kofi&logoColor=white)](https://ko-fi.com/jakedarrow)

---

### License

[MIT](LICENSE) © 2026 Jake Darrow
