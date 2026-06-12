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

// MARK: - Mascot

// The menu bar icon is the little Claude Code pixel critter, with an
// expression that tracks how hard you're working it. Drawn entirely in
// code — no image assets.
enum MascotState {
    case happy      // low usage: smiling
    case working    // mid usage: concentrating, one sweat drop
    case stressed   // high usage: worried, two sweat drops
    case critical   // near limit: X-eyes, red-shifted
    case sleeping   // error / not logged in: gray, eyes closed
}

// The mascot is the Claude Code pixel critter, drawn on a 12x12 logical
// pixel grid. Coordinate space: standard AppKit (y-up, origin bottom-left).
func drawMascot(_ state: MascotState, in rect: NSRect) {
    func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1.0)
    }
    let terracotta  = col(217, 119, 87)     // Claude brand #D97757
    let ink         = col(31, 30, 29)       // #1F1E1D
    let sweatBlue   = col(96, 160, 214)
    let flameOrange = col(226, 88, 34)
    let flameYellow = col(245, 166, 35)

    func blend(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        NSColor(calibratedRed: a.redComponent   + (b.redComponent   - a.redComponent)   * t,
                green:         a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                blue:          a.blueComponent  + (b.blueComponent  - a.blueComponent)  * t,
                alpha: 1.0)
    }

    let body: NSColor
    switch state {
    case .critical: body = blend(terracotta, col(200, 76, 76), 0.75)
    case .sleeping: body = col(160, 150, 142)
    default:        body = terracotta
    }

    let grid: CGFloat = 12
    let u  = min(rect.width, rect.height) / grid
    let ox = rect.minX + (rect.width  - u * grid) / 2
    let oy = rect.minY + (rect.height - u * grid) / 2
    func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1) {
        NSRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u).fill()
    }

    // the critter: four stubby legs, wide body with side nubs, head on top
    body.setFill()
    px(2, 0, 1, 2); px(4, 0, 1, 2); px(7, 0, 1, 2); px(9, 0, 1, 2)
    px(1, 2, 10, 3)
    px(0, 3, 1, 2); px(11, 3, 1, 2)
    px(2, 5, 8, 4)

    ink.setFill()
    switch state {

    case .happy:
        px(4, 6, 1, 2); px(7, 6, 1, 2)                      // open eyes
        px(4, 4); px(5, 3); px(6, 3); px(7, 4)              // smile

    case .working:
        px(4, 6); px(7, 6)                                  // focused squint
        px(5, 4, 2, 1)                                      // flat mouth
        sweatBlue.setFill()
        px(10, 7, 1, 2)                                     // one sweat drop
        ink.setFill()

    case .stressed:
        px(4, 6, 1, 2); px(7, 6, 1, 2)                      // wide eyes
        px(4, 4); px(5, 5); px(6, 5); px(7, 4)              // frown
        sweatBlue.setFill()
        px(1, 7, 1, 2); px(10, 7, 1, 2)                     // two sweat drops
        ink.setFill()

    case .critical:
        for ex: CGFloat in [2, 7] {                          // X eyes
            px(ex, 5); px(ex + 2, 5); px(ex + 1, 6); px(ex, 7); px(ex + 2, 7)
        }
        px(5, 3, 2, 2)                                      // open mouth
        flameOrange.setFill()                               // on fire
        px(3, 9, 6, 1); px(4, 10); px(7, 10)
        flameYellow.setFill()
        px(5, 10, 2, 1); px(6, 11)
        ink.setFill()

    case .sleeping:
        px(3, 6, 2, 1); px(7, 6, 2, 1)                      // closed eyes
        px(5, 4, 2, 1)                                      // tiny mouth
        px(8, 11, 4, 1); px(10, 10); px(9, 9); px(8, 8, 4, 1)   // Z
    }
}

func mascotIcon(_ state: MascotState) -> NSImage {
    // Rasterize once at 2x (36px, an exact 3px per grid cell) and let 1x
    // displays downsample with antialiasing — rendering directly at 18px
    // puts grid cells on half-pixel boundaries and muddies the face.
    let px = 36
    let pt: CGFloat = 18
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep)
    else { return NSImage(size: NSSize(width: pt, height: pt)) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.clear(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.shouldAntialias = false   // crisp pixel-art edges
    drawMascot(state, in: NSRect(x: 0, y: 0, width: px, height: px))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: pt, height: pt)
    let img = NSImage(size: NSSize(width: pt, height: pt))
    img.addRepresentation(rep)
    return img
}

func mascotState(forPeak peak: Double) -> MascotState {
    if peak >= 90 { return .critical }
    if peak >= 75 { return .stressed }
    if peak >= 40 { return .working }
    return .happy
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
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            button.imagePosition = .imageLeft
        }
        setStatus(.sleeping, " …")
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
                self.setStatus(.sleeping, " ⚠")
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
                        self.setStatus(.sleeping, " ⚠")
                        self.rebuildMenu(usage: nil, error: msg.message)
                    }
                }
            }
        }
    }

    func setStatus(_ state: MascotState, _ title: String) {
        statusItem.button?.image = mascotIcon(state)
        statusItem.button?.title = title
        statusItem.button?.contentTintColor = nil
    }

    func update(_ usage: Usage) {
        // Headline = the most-consumed of the primary limits. Threshold on the
        // same rounded value we display so the mascot/tint never contradict
        // the number next to them.
        let candidates = [usage.fiveHour?.utilization, usage.sevenDay?.utilization].compactMap { $0 }
        let peak = (candidates.max() ?? 0).rounded()
        setStatus(mascotState(forPeak: peak), " \(Int(peak))%")
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
        // Explicit colors: disabled menu items dim any text without them.
        let attr = NSMutableAttributedString(
            string: "\(label)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: NSColor.labelColor])
        attr.append(NSAttributedString(
            string: "\(line)" + (reset.isEmpty ? "" : "   ·   \(reset)"),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8)]))
        item.attributedTitle = attr
        menu.addItem(item)
    }

    func rebuildMenu(usage: Usage?, error: String?) {
        let menu = statusItem.menu!
        menu.removeAllItems()

        let header = NSMenuItem(title: "Claude Usage", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "Claude Usage",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                         .foregroundColor: NSColor.labelColor])
        menu.addItem(header)
        menu.addItem(.separator())

        if let error = error {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: error,
                attributes: [.foregroundColor: NSColor.labelColor])
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
