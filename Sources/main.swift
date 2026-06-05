import AppKit
import Foundation

// MARK: - Models

struct UsageWindow {
    let utilization: Double
    let resetsAt: Date?
}

struct Usage {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let extraUtilization: Double?   // % of extra/credit budget used
    let extraUsedCredits: Double?
    let extraMonthlyLimit: Double?
    let extraCurrency: String?
}

// MARK: - Credentials

struct Credentials {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double          // epoch milliseconds
    var raw: [String: Any]         // full claudeAiOauth dict, for write-back
}

enum CredError: Error { case notFound, parse }

struct UsageError: Error { let message: String }

// Claude Code's public OAuth client id (same one used by the CLI).
let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
let keychainService = "Claude Code-credentials"
let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

func runSecurity(_ args: [String], input: String? = nil) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    var inPipe: Pipe?
    if let input = input {
        inPipe = Pipe()
        p.standardInput = inPipe
    }
    do { try p.run() } catch { return (-1, "") }
    if let input = input, let inPipe = inPipe {
        inPipe.fileHandleForWriting.write(input.data(using: .utf8)!)
        inPipe.fileHandleForWriting.closeFile()
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func readCredentials() throws -> Credentials {
    let (status, output) = runSecurity(["find-generic-password", "-s", keychainService, "-w"])
    guard status == 0,
          let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = json["claudeAiOauth"] as? [String: Any],
          let access = oauth["accessToken"] as? String,
          let refresh = oauth["refreshToken"] as? String
    else { throw CredError.parse }
    let exp = (oauth["expiresAt"] as? Double) ?? 0
    return Credentials(accessToken: access, refreshToken: refresh, expiresAt: exp, raw: oauth)
}

func writeCredentials(_ creds: Credentials) {
    let wrapper = ["claudeAiOauth": creds.raw]
    guard let data = try? JSONSerialization.data(withJSONObject: wrapper),
          let str = String(data: data, encoding: .utf8) else { return }
    // -U updates if the item already exists.
    _ = runSecurity(["add-generic-password", "-U", "-s", keychainService,
                     "-a", keychainService, "-w", str])
}

// MARK: - Token refresh

func refreshIfNeeded(_ creds: Credentials, completion: @escaping (Credentials) -> Void) {
    let nowMs = Date().timeIntervalSince1970 * 1000
    // refresh a couple minutes early
    if creds.expiresAt - nowMs > 120_000 {
        completion(creds)
        return
    }
    var req = URLRequest(url: tokenURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
        "grant_type": "refresh_token",
        "refresh_token": creds.refreshToken,
        "client_id": oauthClientID,
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { data, _, _ in
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            completion(creds)   // fall back to existing token; usage call may still work
            return
        }
        var updated = creds
        var raw = creds.raw
        raw["accessToken"] = access
        updated.accessToken = access
        if let refresh = json["refresh_token"] as? String {
            raw["refreshToken"] = refresh
            updated.refreshToken = refresh
        }
        if let expiresIn = json["expires_in"] as? Double {
            let newExp = (Date().timeIntervalSince1970 + expiresIn) * 1000
            raw["expiresAt"] = newExp
            updated.expiresAt = newExp
        }
        updated.raw = raw
        writeCredentials(updated)
        completion(updated)
    }.resume()
}

// MARK: - Fetch usage

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseWindow(_ dict: Any?) -> UsageWindow? {
    guard let d = dict as? [String: Any],
          let util = d["utilization"] as? Double else { return nil }
    var reset: Date?
    if let s = d["resets_at"] as? String {
        reset = isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    return UsageWindow(utilization: util, resetsAt: reset)
}

func fetchUsage(token: String, completion: @escaping (Result<Usage, UsageError>) -> Void) {
    var req = URLRequest(url: usageURL)
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = 20
    URLSession.shared.dataTask(with: req) { data, resp, err in
        if let err = err { completion(.failure(UsageError(message: err.localizedDescription))); return }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { completion(.failure(UsageError(message: "bad response"))); return }
        if let error = json["error"] as? [String: Any],
           let msg = error["message"] as? String {
            completion(.failure(UsageError(message: msg))); return
        }
        let extra = json["extra_usage"] as? [String: Any]
        let usage = Usage(
            fiveHour: parseWindow(json["five_hour"]),
            sevenDay: parseWindow(json["seven_day"]),
            sevenDayOpus: parseWindow(json["seven_day_opus"]),
            sevenDaySonnet: parseWindow(json["seven_day_sonnet"]),
            extraUtilization: extra?["utilization"] as? Double,
            extraUsedCredits: extra?["used_credits"] as? Double,
            extraMonthlyLimit: extra?["monthly_limit"] as? Double,
            extraCurrency: extra?["currency"] as? String
        )
        completion(.success(usage))
    }.resume()
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    let refreshInterval: TimeInterval = 120  // seconds

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Claude …"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuildMenu(usage: nil, error: "Loading…")
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        guard let creds = try? readCredentials() else {
            DispatchQueue.main.async {
                self.setTitle("Claude ⚠")
                self.rebuildMenu(usage: nil, error: "Not logged in (no Claude Code credentials)")
            }
            return
        }
        refreshIfNeeded(creds) { fresh in
            fetchUsage(token: fresh.accessToken) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let usage): self.update(usage)
                    case .failure(let msg):
                        self.setTitle("Claude ⚠")
                        self.rebuildMenu(usage: nil, error: msg.message)
                    }
                }
            }
        }
    }

    func setTitle(_ s: String) { statusItem.button?.title = s }

    func update(_ usage: Usage) {
        // Headline = the most-consumed of the primary limits.
        let candidates = [usage.fiveHour?.utilization, usage.sevenDay?.utilization].compactMap { $0 }
        let peak = candidates.max() ?? 0
        setTitle("⛁ \(Int(peak.rounded()))%")
        if let button = statusItem.button {
            button.contentTintColor = peak >= 90 ? .systemRed : (peak >= 75 ? .systemOrange : nil)
        }
        rebuildMenu(usage: usage, error: nil)
    }

    func fmtReset(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "resets now" }
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h >= 24 { let d = h / 24; let rh = h % 24; return "resets in \(d)d \(rh)h" }
        if h > 0 { return "resets in \(h)h \(m)m" }
        return "resets in \(m)m"
    }

    func bar(_ pct: Double) -> String {
        let slots = 10
        let filled = min(slots, max(0, Int((pct / 100.0 * Double(slots)).rounded())))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: slots - filled)
    }

    func addRow(_ menu: NSMenu, _ label: String, _ window: UsageWindow?) {
        guard let w = window else { return }
        let pct = Int(w.utilization.rounded())
        let item = NSMenuItem(title: "\(label)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        let line = "\(bar(w.utilization))  \(pct)%"
        let reset = fmtReset(w.resetsAt)
        let attr = NSMutableAttributedString(
            string: "\(label)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)])
        attr.append(NSAttributedString(
            string: "\(line)" + (reset.isEmpty ? "" : "   ·   \(reset)"),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        item.attributedTitle = attr
        menu.addItem(item)
    }

    func rebuildMenu(usage: Usage?, error: String?) {
        let menu = statusItem.menu!
        menu.removeAllItems()

        let header = NSMenuItem(title: "Claude Usage", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if let error = error {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let u = usage {
            addRow(menu, "Current session (5-hour)", u.fiveHour)
            addRow(menu, "Weekly (7-day, all models)", u.sevenDay)
            if let opus = u.sevenDayOpus { addRow(menu, "Weekly · Opus", opus) }
            if let sonnet = u.sevenDaySonnet { addRow(menu, "Weekly · Sonnet", sonnet) }
            if let eu = u.extraUtilization {
                var label = "Extra usage credits"
                if let used = u.extraUsedCredits, let limit = u.extraMonthlyLimit {
                    let cur = u.extraCurrency ?? ""
                    label += String(format: "  (%.0f / %.0f %@)", used, limit, cur)
                }
                addRow(menu, label, UsageWindow(utilization: eu, resetsAt: nil))
            }
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc func refreshNow() { tick() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
