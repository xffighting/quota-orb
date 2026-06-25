import AppKit

// MARK: - 配置
let kRefreshInterval: TimeInterval = 120
let kTickInterval: TimeInterval = 20
let kRingAlpha: CGFloat = 0.5   // 圈圈半透明，不抢视线
let kLaunchAgentLabel = "com.quota-orb.app"
let kLaunchAgentPath = NSString(string: "~/Library/LaunchAgents/\(kLaunchAgentLabel).plist").expandingTildeInPath

// 贴边 / 吸附 / 自动隐藏 参数
let kSnapThreshold: CGFloat = 90    // 松手时球心离边多近才吸附
let kEdgeMargin: CGFloat = 6        // 吸附后离屏幕边缘留的缝
let kPeek: CGFloat = 10             // 自动隐藏后露在屏内的一小条宽度
let kHideDelay: TimeInterval = 0.8  // 鼠标移开后多久收起
let kSlideDur: TimeInterval = 0.22  // 滑入 / 滑出动画时长

// 屏幕四边
enum Edge { case left, right, top, bottom }

// 球大小三档
func orbSizeFor(_ scale: String) -> CGFloat {
    switch scale { case "small": return 72; case "large": return 100; default: return 84 }
}

// MARK: - 用户设置（右键菜单可定制，持久化到 ~/.config/quota-orb/settings.json）
final class Settings {
    static let shared = Settings()
    private let url = URL(fileURLWithPath:
        NSString(string: "~/.config/quota-orb/settings.json").expandingTildeInPath)

    var snapToEdge = true             // 拖动松手自动贴最近边
    var autoHide = true               // 贴边后自动收起、鼠标靠近滑出（默认开）
    var orbScale = "medium"           // small / medium / large
    var dimmed = false                // 整体半透明
    var hiddenProviders: Set<String> = []   // 隐藏的 provider id

    private struct Blob: Codable {
        var snapToEdge: Bool; var autoHide: Bool
        var orbScale: String; var dimmed: Bool; var hiddenProviders: [String]
    }

    init() { load() }

    func load() {
        guard let d = try? Data(contentsOf: url),
              let b = try? JSONDecoder().decode(Blob.self, from: d) else { return }
        snapToEdge = b.snapToEdge; autoHide = b.autoHide
        orbScale = b.orbScale; dimmed = b.dimmed
        hiddenProviders = Set(b.hiddenProviders)
    }

    func save() {
        let b = Blob(snapToEdge: snapToEdge, autoHide: autoHide,
                     orbScale: orbScale, dimmed: dimmed,
                     hiddenProviders: Array(hiddenProviders))
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(b) { try? d.write(to: url) }
    }
}

// 当前球径：启动时按设置取档；改大小时整体重建 unit 后更新
var kOrbSize: CGFloat = orbSizeFor(Settings.shared.orbScale)

// 可执行文件与脚本目录：随安装位置自适应（便于分享给朋友）
let kBinaryPath: String = {
    let a = CommandLine.arguments[0]
    let u = a.hasPrefix("/") ? URL(fileURLWithPath: a)
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(a)
    return u.resolvingSymlinksInPath().path
}()
let kScriptDir = (kBinaryPath as NSString).deletingLastPathComponent

// node 路径：优先登录 shell 的 PATH，再退到常见安装位置
let kNodePath: String = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", "command -v node"]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    try? p.run(); p.waitUntilExit()
    let out = (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
    for c in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "\(NSHomeDirectory())/.local/bin/node"] {
        if FileManager.default.isExecutableFile(atPath: c) { return c }
    }
    return "node"
}()

func hexColor(_ hex: UInt32) -> NSColor {
    NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// 按系统语言自动中/英（中文系统→中文，其它→英文）
let kIsZh: Bool = (Locale.preferredLanguages.first?.hasPrefix("zh")) ?? false
func L(_ zh: String, _ en: String) -> String { kIsZh ? zh : en }
let kDateLocale = Locale(identifier: kIsZh ? "zh_CN" : "en_US")
let kWeekdayFmt = kIsZh ? "E HH:mm" : "EEE HH:mm"

// MARK: - Provider 定义
struct Provider {
    let id: String
    let name: String
    let probe: String
    let accent: NSColor      // 5 小时环颜色
    let weekColor: NSColor    // 周环颜色
    let badge: String         // 中心上方字母标识
    let autosaveName: String
    let bundleIDs: [String]   // 点击唤起的桌面应用（按优先级）
    let openURL: String?      // 没有桌面应用时回退打开的网址
}

// 点击悬浮球：唤起/切换到对应应用窗口；没装应用则打开网址
func openProviderApp(_ p: Provider) {
    let ws = NSWorkspace.shared
    for bid in p.bundleIDs {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            app.unhide()
            app.activate(options: [.activateAllWindows])
            return
        }
    }
    for bid in p.bundleIDs {
        if let url = ws.urlForApplication(withBundleIdentifier: bid) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            ws.openApplication(at: url, configuration: cfg, completionHandler: nil)
            return
        }
    }
    if let s = p.openURL, let url = URL(string: s) { ws.open(url) }
}

let kProviders: [Provider] = [
    Provider(id: "claude", name: "Claude",
             probe: "\(kScriptDir)/usage-probe.mjs",
             accent: hexColor(0xD85A30), weekColor: hexColor(0x1D9E75),
             badge: "C", autosaveName: "QuotaOrbClaude",
             bundleIDs: ["com.anthropic.claudefordesktop", "com.anthropic.claude"],
             openURL: "https://claude.ai"),
    Provider(id: "chatgpt", name: "ChatGPT",
             probe: "\(kScriptDir)/codex-probe.mjs",
             accent: hexColor(0x10A37F), weekColor: hexColor(0x9B8AFB),
             badge: "G", autosaveName: "QuotaOrbChatGPT",
             bundleIDs: ["com.openai.codex", "com.openai.chat"],
             openURL: "https://chatgpt.com"),
]

// MARK: - 数据模型
struct WinUsage: Codable {
    let pct: Double
    let resetAt: String?
}
struct Usage: Codable {
    let five: WinUsage
    let week: WinUsage
    let source: String?
    let dataAge: Int?
    let at: String

    var isOfficial: Bool { source == "official" || source == "codex-official" }
    var hasData: Bool { source != "codex-none" }
}

func parseISO(_ s: String?) -> Date? {
    guard let s = s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    return f2.date(from: s)
}

// MARK: - 状态
enum OrbState {
    case idle, healthy, slow, critical

    var color: NSColor {
        switch self {
        case .idle: return hexColor(0x888780)
        case .healthy: return hexColor(0x639922)
        case .slow: return hexColor(0xEF9F27)
        case .critical: return hexColor(0xE24B4A)
        }
    }
}

// MARK: - 数据中心
final class DataStore {
    let provider: Provider
    var usage: Usage?
    var lastError: String?

    init(provider: Provider) { self.provider = provider }

    var resetDate: Date? { parseISO(usage?.five.resetAt) }

    var minutesLeft: Double? {
        guard let r = resetDate else { return nil }
        let m = r.timeIntervalSinceNow / 60
        return m > 0 ? m : nil
    }

    var state: OrbState {
        guard let u = usage, let mins = minutesLeft else { return .idle }
        let remaining = max(0, 100 - u.five.pct) / 100
        let timeFrac = mins / 300
        if remaining > 0.35 && mins < 60 { return .critical }
        if remaining - timeFrac > 0.25 { return .slow }
        return .healthy
    }

    var advice: String {
        switch state {
        case .idle:
            return provider.id == "claude"
                ? L("窗口未开启，发条消息即开新的 5 小时窗口", "No active window — send a message to start a 5h window")
                : L("暂无数据，跑一次 \(provider.name) 即点亮", "No data — run \(provider.name) once to light up")
        case .healthy: return L("消耗节奏健康，放心用", "Healthy pace — go ahead")
        case .slow: return L("用得偏慢，额度别攒着", "Under-using — don't hoard quota")
        case .critical: return L("大量额度即将清零——快用起来", "Lots of quota resets soon — use it!")
        }
    }

    var countdownText: String {
        guard let mins = minutesLeft else { return "—" }
        let m = Int(mins.rounded())
        if m >= 1440 { return "\(m / 1440)d" }
        if m >= 60 { return String(format: "%dh%02d", m / 60, m % 60) }
        return "\(m)m"
    }

    // 周窗口倒计时
    var weekResetDate: Date? { parseISO(usage?.week.resetAt) }
    var weekMinutesLeft: Double? {
        guard let r = weekResetDate else { return nil }
        let m = r.timeIntervalSinceNow / 60
        return m > 0 ? m : nil
    }
    var weekCountdownShort: String {       // 球面用：尽量短
        guard let mins = weekMinutesLeft else { return "—" }
        let m = Int(mins.rounded())
        if m >= 1440 { return "\(m / 1440)d" }
        if m >= 60 { return "\(m / 60)h" }
        return "\(m)m"
    }
    var weekCountdownText: String {         // 卡片用：详细
        guard let mins = weekMinutesLeft else { return "—" }
        let m = Int(mins.rounded())
        if m >= 1440 { let d = m / 1440, h = (m % 1440) / 60
            return h > 0 ? L("\(d)天\(h)h", "\(d)d\(h)h") : L("\(d)天", "\(d)d") }
        if m >= 60 { return String(format: "%dh%02dm", m / 60, m % 60) }
        return "\(m)m"
    }

    func refresh(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", "'\(kNodePath)' '\(self.provider.probe)'"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let u = try JSONDecoder().decode(Usage.self, from: data)
                DispatchQueue.main.async {
                    self.usage = u
                    self.lastError = nil
                    completion()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = "\(error)"
                    completion()
                }
            }
        }
    }
}

// MARK: - 进度条
final class BarView: NSView {
    var pct: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = .systemGray { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.25).setFill()
        track.fill()
        let w = bounds.width * CGFloat(min(100, max(0, pct)) / 100)
        if w > bounds.height {
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height),
                                    xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            color.setFill()
            fill.fill()
        }
    }
}

// MARK: - 悬浮球视图
final class OrbView: NSView {
    let store: DataStore
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private var dragMouseStart: NSPoint?   // 按下时全局鼠标位置
    private var dragWinStart: NSPoint?     // 按下时窗口原点
    private var didDrag = false
    private let haloLayer = CAShapeLayer()
    private var breathing = false

    init(store: DataStore) {
        self.store = store
        super.init(frame: NSRect(x: 0, y: 0, width: kOrbSize, height: kOrbSize))
        wantsLayer = true
        haloLayer.fillColor = NSColor.clear.cgColor
        haloLayer.lineWidth = 2.0
        layer?.addSublayer(haloLayer)
        layoutHalo()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() { super.layout(); layoutHalo() }
    private func layoutHalo() {
        let s = bounds.width, r = s / 2 - 2
        haloLayer.path = CGPath(ellipseIn: CGRect(x: s / 2 - r, y: s / 2 - r, width: r * 2, height: r * 2), transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        dragMouseStart = NSEvent.mouseLocation
        dragWinStart = window?.frame.origin
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let ms = dragMouseStart, let ws = dragWinStart, let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - ms.x, dy = now.y - ms.y
        if !didDrag, abs(dx) > 2 || abs(dy) > 2 { didDrag = true; onDragBegan?() }
        if didDrag { win.setFrameOrigin(NSPoint(x: ws.x + dx, y: ws.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        if didDrag { onDragEnded?() } else { onClick?() }
        dragMouseStart = nil; dragWinStart = nil; didDrag = false
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    func updateAppearance() {
        let state = store.state
        haloLayer.strokeColor = state.color.withAlphaComponent(0.6).cgColor
        if state == .critical && !breathing {
            breathing = true
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0.25
            a.toValue = 1.0
            a.duration = 1.1
            a.autoreverses = true
            a.repeatCount = .infinity
            haloLayer.add(a, forKey: "breathe")
        } else if state != .critical && breathing {
            breathing = false
            haloLayer.removeAnimation(forKey: "breathe")
            haloLayer.opacity = 1
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = NSPoint(x: bounds.midX, y: bounds.midY)

        let bgR = bounds.width / 2 - 6
        let bg = NSBezierPath(ovalIn: NSRect(x: c.x - bgR, y: c.y - bgR, width: bgR * 2, height: bgR * 2))
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        bg.fill()

        // 双环：外=5小时、内=周；半透明、贴外缘，给中心文字留出干净区
        let fivePct = store.usage?.five.pct ?? 0
        let weekPct = store.usage?.week.pct ?? 0
        drawRing(center: c, radius: bgR - 4, width: 5, pct: store.minutesLeft == nil ? 0 : fivePct,
                 color: store.provider.accent.withAlphaComponent(kRingAlpha))
        drawRing(center: c, radius: bgR - 12, width: 4, pct: weekPct,
                 color: store.provider.weekColor.withAlphaComponent(kRingAlpha))

        // 中心：badge + 两个倒计时（颜色对应内外环：外环色=5小时，内环色=周）
        let badge = store.provider.badge
        let bAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: store.provider.accent.withAlphaComponent(0.8),
        ]
        let bSize = badge.size(withAttributes: bAttr)
        badge.draw(at: NSPoint(x: c.x - bSize.width / 2, y: c.y + 12), withAttributes: bAttr)

        // 5 小时倒计时（外环色，醒目）
        let five = store.countdownText
        let fAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: store.provider.accent,
        ]
        let fSize = five.size(withAttributes: fAttr)
        five.draw(at: NSPoint(x: c.x - fSize.width / 2, y: c.y - 1), withAttributes: fAttr)

        // 周倒计时（内环色）
        let wk = store.weekCountdownShort
        let wAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: store.provider.weekColor,
        ]
        let wSize = wk.size(withAttributes: wAttr)
        wk.draw(at: NSPoint(x: c.x - wSize.width / 2, y: c.y - 15), withAttributes: wAttr)
    }

    private func drawRing(center: NSPoint, radius: CGFloat, width: CGFloat, pct: Double, color: NSColor) {
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = width
        NSColor.tertiaryLabelColor.withAlphaComponent(0.18).setStroke()
        track.stroke()

        let frac = min(100, max(0, pct)) / 100
        guard frac > 0.01 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: 90, endAngle: 90 - CGFloat(frac) * 360, clockwise: true)
        arc.lineWidth = width
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }
}

// MARK: - 详情卡片
final class CardController {
    let panel: NSPanel
    let store: DataStore
    private let titleLabel = NSTextField(labelWithString: "")
    private let fiveBar = BarView()
    private let fiveLine1 = NSTextField(labelWithString: "")
    private let fiveLine2 = NSTextField(labelWithString: "")
    private let weekBar = BarView()
    private let weekLine = NSTextField(labelWithString: "")
    private let adviceLabel = NSTextField(labelWithString: "")

    init(store: DataStore) {
        self.store = store
        let w: CGFloat = 296, h: CGFloat = 168
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.material = .popover
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        panel.contentView = root

        func style(_ l: NSTextField, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
            l.font = NSFont.systemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.lineBreakMode = .byTruncatingTail
        }
        style(titleLabel, size: 12, weight: .semibold)
        style(fiveLine1, size: 11, color: .secondaryLabelColor)
        style(fiveLine2, size: 13, weight: .medium, color: store.provider.accent)     // 5小时倒计时：醒目
        style(weekLine, size: 13, weight: .medium, color: store.provider.weekColor)    // 周倒计时：醒目
        style(adviceLabel, size: 11, weight: .medium)

        let pad: CGFloat = 16
        var y = h - 32
        titleLabel.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 16)
        y -= 24
        fiveLine1.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 15)
        y -= 14
        fiveBar.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 7)
        fiveBar.color = store.provider.accent
        y -= 17
        fiveLine2.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 17)
        y -= 28
        weekBar.frame = NSRect(x: pad, y: y + 4, width: w - pad * 2, height: 7)
        weekBar.color = store.provider.weekColor
        y -= 18
        weekLine.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 17)
        y -= 26
        adviceLabel.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 16)

        [titleLabel, fiveLine1, fiveBar, fiveLine2, weekBar, weekLine, adviceLabel].forEach { root.addSubview($0) }
    }

    private func ageText(_ u: Usage) -> String {
        guard let a = u.dataAge else { return "" }
        if a < 1 { return L(" · 刚刷新", " · just now") }
        if a < 60 { return L(" · \(a) 分钟前", " · \(a)m ago") }
        return L(" · \(a / 60)h\(a % 60)m 前", " · \(a / 60)h\(a % 60)m ago")
    }

    func update() {
        let name = store.provider.name
        if let u = store.usage, u.hasData {
            let srcTag = u.isOfficial ? L("官方数据", "official") : L("本地估算", "local estimate")
            titleLabel.stringValue = "\(name) · \(srcTag)\(ageText(u))"
            fiveBar.pct = store.minutesLeft == nil ? 0 : u.five.pct
            weekBar.pct = u.week.pct
            let fp = Int(u.five.pct.rounded()), wp = Int(u.week.pct.rounded())

            if let reset = store.resetDate, store.minutesLeft != nil {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                fiveLine1.stringValue = L("5 小时 · 已用 \(fp)%", "5h window · \(fp)% used")
                fiveLine2.stringValue = L("还剩 \(store.countdownText) → \(f.string(from: reset)) 重置",
                                         "\(store.countdownText) left → resets \(f.string(from: reset))")
            } else {
                fiveLine1.stringValue = L("5 小时窗口 · 暂无数据", "5h window · no data")
                fiveLine2.stringValue = store.provider.id == "chatgpt"
                    ? L("跑一次 \(name) 即刷新", "run \(name) once to refresh")
                    : L("发条消息即开始计时", "send a message to start")
            }

            if let wReset = store.weekResetDate {
                let wf = DateFormatter()
                wf.locale = kDateLocale
                wf.dateFormat = kWeekdayFmt
                weekLine.stringValue = L("周 · 已用 \(wp)% · 还剩 \(store.weekCountdownText) → \(wf.string(from: wReset)) 重置",
                                        "Week · \(wp)% used · \(store.weekCountdownText) left → resets \(wf.string(from: wReset))")
            } else {
                weekLine.stringValue = L("周 · 已用 \(wp)%", "Week · \(wp)% used")
            }
        } else if store.usage != nil {
            titleLabel.stringValue = "\(name) · \(L("未配置", "not set up"))"
            fiveLine1.stringValue = L("还没在本机用过 \(name)", "Haven't used \(name) on this Mac yet")
            fiveLine2.stringValue = L("用一次即点亮", "use it once to light up")
            weekLine.stringValue = ""
        } else {
            titleLabel.stringValue = name
            fiveLine1.stringValue = L("数据加载中…", "Loading…")
            fiveLine2.stringValue = store.lastError ?? ""
            weekLine.stringValue = ""
        }
        adviceLabel.stringValue = store.advice
        adviceLabel.textColor = store.state.color
    }

    func show(near orbFrame: NSRect) {
        update()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(orbFrame) }) ?? NSScreen.main else { return }
        let gap: CGFloat = 10
        var x = orbFrame.maxX + gap
        if x + panel.frame.width > screen.visibleFrame.maxX {
            x = orbFrame.minX - gap - panel.frame.width
        }
        var y = orbFrame.midY - panel.frame.height / 2
        y = min(max(y, screen.visibleFrame.minY + 8), screen.visibleFrame.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}

// MARK: - 单个悬浮球的运行时单元
final class OrbUnit {
    let store: DataStore
    let panel: NSPanel
    let orbView: OrbView
    let card: CardController

    // 贴边 / 自动隐藏 状态
    var edge: Edge?              // 当前贴的边（nil = 自由放置，不参与自动隐藏）
    var anchorFrame: NSRect?     // 贴边后的完整（展开）位置
    private(set) var collapsed = false
    private var hovering = false
    private var hideWork: DispatchWorkItem?

    init(provider: Provider, index: Int) {
        store = DataStore(provider: provider)
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: kOrbSize, height: kOrbSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false   // 改用自定义拖动，便于松手吸附
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        orbView = OrbView(store: store)
        panel.contentView = orbView
        card = CardController(store: store)

        // 悬停：进入即展开（若已收起）+ 弹细节卡片；移开即收卡片并安排自动隐藏
        orbView.onHover = { [weak self] inside in
            guard let self = self else { return }
            self.hovering = inside
            if inside {
                self.hideWork?.cancel()
                let ref = self.collapsed ? (self.anchorFrame ?? self.panel.frame) : self.panel.frame
                self.expand()
                self.card.show(near: ref)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    guard let self = self else { return }
                    let p = self.orbView.window?.mouseLocationOutsideOfEventStream ?? .zero
                    if !self.orbView.bounds.contains(p) {
                        self.card.hide()
                        self.scheduleCollapse()
                    }
                }
            }
        }
        // 单击悬浮球：唤起/切换到对应应用窗口
        orbView.onClick = { [weak self] in
            guard let self = self else { return }
            openProviderApp(self.store.provider)
        }
        // 拖动：开始时收卡片；松手吸附最近边并安排自动隐藏
        orbView.onDragBegan = { [weak self] in
            self?.hideWork?.cancel()
            self?.collapsed = false
            self?.card.hide()
        }
        orbView.onDragEnded = { [weak self] in
            guard let self = self else { return }
            self.snapToNearestEdge(animated: true)
            self.scheduleCollapse()
        }

        // 定位：沿用上次保存的原点，但球径以当前档为准（避免改大小后被旧 frame 覆盖）
        if panel.setFrameUsingName(provider.autosaveName) {
            var f = panel.frame
            f.size = NSSize(width: kOrbSize, height: kOrbSize)
            panel.setFrame(f, display: false)
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.maxX - kOrbSize - 24,
                                         y: vf.maxY - kOrbSize - 24 - CGFloat(index) * (kOrbSize + 12)))
        }
        panel.orderFront(nil)
        applyOpacity()
        applyVisibility()
        if Settings.shared.snapToEdge { snapToNearestEdge(animated: false) }
        if Settings.shared.autoHide { scheduleCollapse() }
    }

    // MARK: 贴边吸附
    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main
    }

    func snapToNearestEdge(animated: Bool) {
        guard let screen = currentScreen() else { return }
        let vf = screen.visibleFrame
        var f = panel.frame
        let cx = f.midX, cy = f.midY
        let dl = cx - vf.minX, dr = vf.maxX - cx, db = cy - vf.minY, dt = vf.maxY - cy
        let m = min(dl, dr, db, dt)
        guard Settings.shared.snapToEdge, m < kSnapThreshold else {
            edge = nil; anchorFrame = nil; collapsed = false; return   // 离边太远：自由放置
        }
        if m == dl { edge = .left;  f.origin.x = vf.minX + kEdgeMargin }
        else if m == dr { edge = .right; f.origin.x = vf.maxX - f.width - kEdgeMargin }
        else if m == db { edge = .bottom; f.origin.y = vf.minY + kEdgeMargin }
        else { edge = .top; f.origin.y = vf.maxY - f.height - kEdgeMargin }
        // 另一方向夹进可视区
        f.origin.x = min(max(f.origin.x, vf.minX + kEdgeMargin), vf.maxX - f.width - kEdgeMargin)
        f.origin.y = min(max(f.origin.y, vf.minY + kEdgeMargin), vf.maxY - f.height - kEdgeMargin)
        anchorFrame = f
        collapsed = false
        setFrame(f, animated: animated)
        panel.saveFrame(usingName: store.provider.autosaveName)
    }

    // MARK: 自动隐藏
    private func collapsedFrame() -> NSRect? {
        guard let e = edge, let a = anchorFrame, let screen = currentScreen() else { return nil }
        let vf = screen.visibleFrame
        var f = a
        switch e {
        case .left:   f.origin.x = vf.minX - f.width + kPeek
        case .right:  f.origin.x = vf.maxX - kPeek
        case .top:    f.origin.y = vf.maxY - kPeek
        case .bottom: f.origin.y = vf.minY - f.height + kPeek
        }
        return f
    }

    func scheduleCollapse() {
        hideWork?.cancel()
        guard Settings.shared.autoHide, edge != nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.collapse() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + kHideDelay, execute: w)
    }

    func collapse() {
        guard Settings.shared.autoHide, !hovering, edge != nil, !collapsed,
              let cf = collapsedFrame() else { return }
        collapsed = true
        setFrame(cf, animated: true)
    }

    func expand() {
        guard collapsed, let a = anchorFrame else { return }
        collapsed = false
        setFrame(a, animated: true)
    }

    private func setFrame(_ f: NSRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = kSlideDur
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(f, display: true)
            }
        } else {
            panel.setFrame(f, display: true)
        }
    }

    // MARK: 设置应用
    func applyOpacity() { panel.alphaValue = Settings.shared.dimmed ? 0.45 : 1.0 }

    func applyVisibility() {
        if Settings.shared.hiddenProviders.contains(store.provider.id) {
            hideWork?.cancel(); card.hide(); panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    // 取消自动隐藏：展开复位，但保留贴边
    func showFully() {
        hideWork?.cancel()
        if collapsed, let a = anchorFrame { collapsed = false; setFrame(a, animated: true) }
    }

    // 关闭贴边后：展开复位并清边
    func releaseEdge() {
        showFully()
        edge = nil; anchorFrame = nil
    }

    func teardown() {
        hideWork?.cancel()
        card.hide()
        panel.orderOut(nil)
        panel.close()
    }

    func refresh(completion: @escaping () -> Void) {
        store.refresh { [weak self] in
            guard let self = self else { return }
            self.orbView.updateAppearance()
            if self.card.panel.isVisible { self.card.update() }
            completion()
        }
    }

    func tick() {
        orbView.updateAppearance()
        if card.panel.isVisible { card.update() }
    }
}

// MARK: - App
final class AppDelegate: NSObject, NSApplicationDelegate {
    var units: [OrbUnit] = []
    var refreshTimer: Timer?
    var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        for (i, provider) in kProviders.enumerated() {
            let unit = OrbUnit(provider: provider, index: i)
            unit.orbView.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
            units.append(unit)
        }

        doRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: kRefreshInterval, repeats: true) { [weak self] _ in
            self?.doRefresh()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: kTickInterval, repeats: true) { [weak self] _ in
            self?.units.forEach { $0.tick() }
        }
    }

    func makeMenu() -> NSMenu {
        let s = Settings.shared
        let menu = NSMenu()

        let refresh = NSMenuItem(title: L("立即刷新", "Refresh now"), action: #selector(doRefresh), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let snap = NSMenuItem(title: L("贴边吸附", "Snap to edge"), action: #selector(toggleSnap), keyEquivalent: "")
        snap.target = self; snap.state = s.snapToEdge ? .on : .off
        menu.addItem(snap)

        let hide = NSMenuItem(title: L("自动隐藏", "Auto-hide"), action: #selector(toggleAutoHide), keyEquivalent: "")
        hide.target = self; hide.state = s.autoHide ? .on : .off
        hide.isEnabled = s.snapToEdge   // 自动隐藏依赖贴边
        menu.addItem(hide)

        // 外观子菜单：球大小 + 半透明
        let look = NSMenuItem(title: L("外观", "Appearance"), action: nil, keyEquivalent: "")
        let lookMenu = NSMenu()
        for (key, zh, en) in [("small", "小", "Small"), ("medium", "中", "Medium"), ("large", "大", "Large")] {
            let it = NSMenuItem(title: L(zh, en), action: #selector(setScale(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = key; it.state = (s.orbScale == key) ? .on : .off
            lookMenu.addItem(it)
        }
        lookMenu.addItem(.separator())
        let dim = NSMenuItem(title: L("半透明", "Dimmed"), action: #selector(toggleDim), keyEquivalent: "")
        dim.target = self; dim.state = s.dimmed ? .on : .off
        lookMenu.addItem(dim)
        look.submenu = lookMenu
        menu.addItem(look)

        // 显示子菜单：各球显隐
        let show = NSMenuItem(title: L("显示", "Show"), action: nil, keyEquivalent: "")
        let showMenu = NSMenu()
        for p in kProviders {
            let it = NSMenuItem(title: p.name, action: #selector(toggleProvider(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = p.id
            it.state = s.hiddenProviders.contains(p.id) ? .off : .on
            showMenu.addItem(it)
        }
        show.submenu = showMenu
        menu.addItem(show)

        menu.addItem(.separator())

        let auto = NSMenuItem(title: L("随登录启动", "Launch at login"), action: #selector(toggleLaunchAgent), keyEquivalent: "")
        auto.target = self
        auto.state = FileManager.default.fileExists(atPath: kLaunchAgentPath) ? .on : .off
        menu.addItem(auto)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc func doRefresh() {
        units.forEach { $0.refresh(completion: {}) }
    }

    @objc func toggleLaunchAgent() {
        let fm = FileManager.default
        if fm.fileExists(atPath: kLaunchAgentPath) {
            _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"), arguments: ["unload", kLaunchAgentPath])
            try? fm.removeItem(atPath: kLaunchAgentPath)
        } else {
            let plist: [String: Any] = [
                "Label": kLaunchAgentLabel,
                "ProgramArguments": [kBinaryPath],
                "RunAtLoad": true,
                "KeepAlive": ["SuccessfulExit": false],  // 崩溃自动拉起；手动退出不拉起
                "ProcessType": "Interactive",
                "StandardOutPath": "\(kScriptDir)/orb.log",
                "StandardErrorPath": "\(kScriptDir)/orb.log",
            ]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: URL(fileURLWithPath: kLaunchAgentPath))
            _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"), arguments: ["load", kLaunchAgentPath])
        }
    }

    // MARK: - 可定制项
    @objc func toggleSnap() {
        let s = Settings.shared
        s.snapToEdge.toggle()
        if !s.snapToEdge { s.autoHide = false }   // 不贴边则自动隐藏一并关
        s.save()
        units.forEach { s.snapToEdge ? $0.snapToNearestEdge(animated: true) : $0.releaseEdge() }
    }

    @objc func toggleAutoHide() {
        let s = Settings.shared
        guard s.snapToEdge else { return }
        s.autoHide.toggle()
        s.save()
        units.forEach { s.autoHide ? $0.scheduleCollapse() : $0.showFully() }
    }

    @objc func setScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, key != Settings.shared.orbScale else { return }
        Settings.shared.orbScale = key
        Settings.shared.save()
        rebuildUnits()
    }

    @objc func toggleDim() {
        Settings.shared.dimmed.toggle()
        Settings.shared.save()
        units.forEach { $0.applyOpacity() }
    }

    @objc func toggleProvider(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let s = Settings.shared
        if s.hiddenProviders.contains(id) {
            s.hiddenProviders.remove(id)
        } else if s.hiddenProviders.count >= kProviders.count - 1 {
            NSSound.beep(); return   // 至少保留一个球可见
        } else {
            s.hiddenProviders.insert(id)
        }
        s.save()
        units.forEach { $0.applyVisibility() }
    }

    // 改球大小后整体重建（旧 panel 尺寸不可原地变更）
    func rebuildUnits() {
        kOrbSize = orbSizeFor(Settings.shared.orbScale)
        units.forEach { $0.teardown() }
        units.removeAll()
        for (i, provider) in kProviders.enumerated() {
            let unit = OrbUnit(provider: provider, index: i)
            unit.orbView.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
            units.append(unit)
        }
        doRefresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
