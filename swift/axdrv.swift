// ─────────────────────────────────────────────────────────────────────────────
// Damarseta · Infrastructure with Intent. · Aligned. Reliable.
// Copyright (c) 2026 wid@damarseta.id · https://damarseta.id
// ─────────────────────────────────────────────────────────────────────────────
// Context: swift
// Purpose: Drive a running macOS app through its accessibility tree
//
// Build:  swiftc -O axdrv.swift -o /tmp/axdrv
// Help:   /tmp/axdrv help
//
// Target: --pid <pid>, --app <name or bundle id>, AXDRV_PID, or the frontmost app.
// Select: key=value terms, ANDed. A bare term is a case-insensitive substring match over
//         id, description, title, and value.
import AppKit
import ApplicationServices

// MARK: - Arguments

struct Options {
    var pid: pid_t?
    var app: String?
    var json = false
    var all = false
    var depth = 60
    var timeout: Float = 1.5
    var maxNodes = 20000
    var command = ""
    var operands: [String] = []
    /// Raw screen point for `color`; bypasses the selector.
    var at: CGPoint?
}

func usage() -> Never {
    print(
        """
        usage: axdrv [--pid <pid>|--app <name|bundle>] [--json] [--all] [--depth <n>]
                     [--timeout <seconds>] [--max-nodes <n>] <command> [operand]

        limits:
          --timeout <s>        per-call accessibility timeout, default 1.5
          --max-nodes <n>      stop walking after n nodes, default 20000
          --at <x,y>           raw screen point for the color command

        target:
          --pid <pid>          drive this process
          --app <name|bundle>  drive the first app with this bundle id or name
          (neither)            drive AXDRV_PID when set, else the frontmost app

        commands:
          apps                             list running regular apps with their pid
          windows                          list the target's windows and window ids
          activate                         bring the target app to the front
          dump [selector]                  print the accessibility tree
          texts [selector]                 print static text values
          press <selector>                 AXPress exactly one match
          select <selector>                select the outline row containing one match
          click <selector>                 click the center of one match
          frame <selector>                 print the frame of one match
          type <text>                      activate, then type text
          key <keycode> [cmd|shift|option|control...]  activate, then press a key
          color [selector]                 sample the rendered pixels of one element

        color:
          The accessibility API has no color attribute, so this samples the window
          capture instead. With a selector it reports the element's frame, its most
          common pixel (the background), the strongest minority pixel (the ink), and
          the WCAG contrast between them. With --at x,y it samples one screen point.
          Needs Screen Recording permission for the terminal. Sampling a transient
          state (a selection, a hover) is only valid while it is on screen.

        selector:
          key=value terms, ANDed. keys: id, role, desc, title, value, enabled.
          A bare term matches a substring of id, description, title, or value.
          Examples:
            id=save
            role=AXButton desc=Back
            title=Settings…
            "New note"
        """)
    exit(2)
}

func parseArguments() -> Options {
    var options = Options()
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--pid":
            index += 1
            guard index < arguments.count, let pid = pid_t(arguments[index]) else { usage() }
            options.pid = pid
        case "--app":
            index += 1
            guard index < arguments.count else { usage() }
            options.app = arguments[index]
        case "--json":
            options.json = true
        case "--all":
            options.all = true
        case "--depth":
            index += 1
            guard index < arguments.count, let depth = Int(arguments[index]), depth > 0 else {
                usage()
            }
            options.depth = depth
        case "--timeout":
            index += 1
            guard index < arguments.count, let seconds = Float(arguments[index]), seconds > 0 else {
                usage()
            }
            options.timeout = seconds
        case "--max-nodes":
            index += 1
            guard index < arguments.count, let count = Int(arguments[index]), count > 0 else {
                usage()
            }
            options.maxNodes = count
        case "--at":
            index += 1
            guard index < arguments.count else { usage() }
            let parts = arguments[index].split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { usage() }
            options.at = CGPoint(x: parts[0], y: parts[1])
        case "--help", "-h", "help":
            usage()
        default:
            if argument.hasPrefix("--") { usage() }
            if options.command.isEmpty {
                options.command = argument
            } else {
                options.operands.append(argument)
            }
        }
        index += 1
    }
    if options.command.isEmpty { usage() }
    return options
}

// MARK: - Target

struct Target {
    let pid: pid_t
    let name: String
    let bundle: String
}

func runningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
}

func resolveTarget(_ options: Options) -> Target {
    let application: NSRunningApplication?
    if let pid = options.pid {
        application = NSRunningApplication(processIdentifier: pid)
    } else if let query = options.app {
        application =
            runningApps().first { $0.bundleIdentifier == query }
            ?? runningApps().first {
                ($0.localizedName ?? "").caseInsensitiveCompare(query) == .orderedSame
            }
    } else if let raw = ProcessInfo.processInfo.environment["AXDRV_PID"], let pid = pid_t(raw) {
        // Backward compatibility with the older Chet driver and its documented recipes.
        application = NSRunningApplication(processIdentifier: pid)
    } else {
        application = NSWorkspace.shared.frontmostApplication
    }

    guard let application else {
        FileHandle.standardError.write(Data("target app not found\n".utf8))
        exit(4)
    }
    return Target(
        pid: application.processIdentifier,
        name: application.localizedName ?? "unknown",
        bundle: application.bundleIdentifier ?? "unknown")
}

// MARK: - Accessibility

func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

func str(_ element: AXUIElement, _ name: String) -> String {
    (attr(element, name) as? String) ?? ""
}

func kids(_ element: AXUIElement) -> [AXUIElement] {
    (attr(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return (names as? [String]) ?? []
}

func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
    guard let value = attr(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
}

func size(_ element: AXUIElement) -> CGSize? {
    guard let value = attr(element, kAXSizeAttribute as String),
        CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
}

struct Node {
    let element: AXUIElement
    let role: String
    let id: String
    let desc: String
    let title: String
    let value: String
    let enabled: Bool?
    let actions: [String]
    let window: String
    let depth: Int
    let origin: CGPoint?
    let size: CGSize?

    var frame: CGRect? {
        guard let origin, let size else { return nil }
        return CGRect(origin: origin, size: size)
    }
}

/// Per-run limits, set once in Main before the first walk.
var messagingTimeout: Float = 1.5
var nodeLimit = 20000
var truncated = false
let walkStart = Date()
var slowNoted = false

/// One IPC call for eight attributes. A missing attribute comes back as an AXValue of type
/// axError, which the casts below turn into nil.
let nodeAttributes: [String] = [
    kAXRoleAttribute as String, "AXIdentifier", "AXDescription", kAXTitleAttribute as String,
    kAXValueAttribute as String, "AXEnabled", kAXPositionAttribute as String,
    kAXSizeAttribute as String,
]

func axPoint(_ raw: CFTypeRef?) -> CGPoint? {
    guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var out = CGPoint.zero
    return AXValueGetValue(raw as! AXValue, .cgPoint, &out) ? out : nil
}

func axSize(_ raw: CFTypeRef?) -> CGSize? {
    guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var out = CGSize.zero
    return AXValueGetValue(raw as! AXValue, .cgSize, &out) ? out : nil
}

func makeNode(_ element: AXUIElement, window: String, depth: Int) -> Node {
    var values: CFArray?
    AXUIElementCopyMultipleAttributeValues(
        element, nodeAttributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
    let got = (values as? [CFTypeRef]) ?? []
    func at(_ index: Int) -> CFTypeRef? { index < got.count ? got[index] : nil }
    return Node(
        element: element,
        role: at(0) as? String ?? "",
        id: at(1) as? String ?? "",
        desc: at(2) as? String ?? "",
        title: at(3) as? String ?? "",
        value: at(4) as? String ?? "",
        enabled: at(5) as? Bool,
        actions: actions(element),
        window: window,
        depth: depth,
        origin: axPoint(at(6)),
        size: axSize(at(7)))
}

/// Windows only. The menu bar is excluded on purpose: menu items are better reached with
/// keyboard shortcuts, and including the full menu tree floods every dump.
/// A visited set stops cycles; `nodeLimit` stops runaway lists.
func walk(_ root: AXUIElement, window: String, depthLimit: Int, into nodes: inout [Node]) {
    AXUIElementSetMessagingTimeout(root, messagingTimeout)
    var seen = Set<CFHashCode>()
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (element, depth) = stack.popLast() {
        if nodes.count >= nodeLimit {
            if !truncated {
                truncated = true
                FileHandle.standardError.write(Data("truncated at \(nodeLimit) nodes\n".utf8))
            }
            return
        }
        guard seen.insert(CFHash(element)).inserted else { continue }
        nodes.append(makeNode(element, window: window, depth: depth))
        if !slowNoted, Date().timeIntervalSince(walkStart) > 3 {
            slowNoted = true
            FileHandle.standardError.write(
                Data("slow walk: \(nodes.count) nodes so far, target may be busy\n".utf8))
        }
        if depth < depthLimit {
            for child in kids(element) { stack.append((child, depth + 1)) }
        }
    }
}

func snapshot(_ target: Target, depthLimit: Int) -> [Node] {
    let app = AXUIElementCreateApplication(target.pid)
    AXUIElementSetMessagingTimeout(app, messagingTimeout)
    let windows = (attr(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    var nodes: [Node] = []
    if windows.isEmpty {
        walk(app, window: "", depthLimit: depthLimit, into: &nodes)
    } else {
        for window in windows {
            walk(
                window, window: str(window, kAXTitleAttribute as String), depthLimit: depthLimit,
                into: &nodes)
        }
    }
    return nodes
}

// MARK: - Selector

struct Selector {
    struct Term {
        let key: String
        let value: String
    }

    var terms: [Term] = []

    init(_ operands: [String]) {
        for operand in operands {
            if let separator = operand.firstIndex(of: "=") {
                let key = String(operand[..<separator]).lowercased()
                let value = String(operand[operand.index(after: separator)...])
                terms.append(Term(key: key, value: value))
            } else {
                terms.append(Term(key: "contains", value: operand))
            }
        }
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ node: Node) -> Bool {
        for term in terms {
            switch term.key {
            case "id":
                if node.id != term.value { return false }
            case "role":
                if node.role != term.value { return false }
            case "desc", "description":
                if node.desc != term.value { return false }
            case "title":
                if node.title != term.value { return false }
            case "value":
                if node.value != term.value { return false }
            case "enabled":
                if node.enabled != (term.value == "true") { return false }
            case "contains":
                let haystack = "\(node.id) \(node.desc) \(node.title) \(node.value)".lowercased()
                if !haystack.contains(term.value.lowercased()) { return false }
            default:
                return false
            }
        }
        return true
    }
}

func describe(_ node: Node) -> String {
    var parts = [node.role]
    if !node.id.isEmpty { parts.append("id=\(node.id)") }
    if !node.desc.isEmpty { parts.append("desc=\(node.desc)") }
    if !node.title.isEmpty { parts.append("title=\(node.title)") }
    if let frame = node.frame {
        parts.append(
            "frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
                + "\(Int(frame.width)),\(Int(frame.height))")
    }
    if let enabled = node.enabled { parts.append("enabled=\(enabled)") }
    return parts.joined(separator: " ")
}

func resolve(_ selector: Selector, in nodes: [Node]) -> Node {
    let matches = nodes.filter { selector.matches($0) }
    if matches.count == 1 { return matches[0] }
    if matches.isEmpty {
        FileHandle.standardError.write(Data("no element matches the selector\n".utf8))
        exit(5)
    }
    FileHandle.standardError.write(
        Data("\(matches.count) elements match; narrow the selector:\n".utf8))
    for match in matches.prefix(10) {
        FileHandle.standardError.write(Data("  \(describe(match))\n".utf8))
    }
    exit(6)
}

// MARK: - Actions

func press(_ node: Node) -> Bool {
    AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success
}

func pointIsInsideTargetWindow(_ point: CGPoint, pid: pid_t) -> Bool {
    let list =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in list {
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { continue }
        guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
        let rect = CGRect(
            x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        if rect.contains(point) { return true }
    }
    return false
}

func click(_ node: Node, pid: pid_t) -> Bool {
    guard let frame = node.frame else { return false }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    guard center.y > 26, pointIsInsideTargetWindow(center, pid: pid) else {
        FileHandle.standardError.write(
            Data("refused: point outside the target window\n".utf8))
        return false
    }
    guard
        let down = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center,
            mouseButton: .left),
        let up = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center,
            mouseButton: .left)
    else { return false }
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
    return true
}

func subtree(_ root: AXUIElement, window: String) -> [Node] {
    var nodes: [Node] = []
    walk(root, window: window, depthLimit: 60, into: &nodes)
    return nodes
}

func selectRow(containing selector: Selector, in nodes: [Node]) -> Bool {
    for outline in nodes where outline.role == "AXOutline" {
        for row in subtree(outline.element, window: outline.window) where row.role == "AXRow" {
            if subtree(row.element, window: row.window).contains(where: selector.matches) {
                let set = AXUIElementSetAttributeValue(
                    outline.element, "AXSelectedRows" as CFString, [row.element] as CFArray)
                return set == .success
            }
        }
    }
    return false
}

func activate(_ pid: pid_t) {
    _ = NSRunningApplication(processIdentifier: pid)?.activate()
}

func typeText(_ text: String, pid: pid_t) {
    activate(pid)
    usleep(150_000)
    let source = CGEventSource(stateID: .hidSystemState)
    var utf16 = Array(text.utf16)
    guard
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { return }
    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
    down.post(tap: .cghidEventTap)
    usleep(20_000)
    up.post(tap: .cghidEventTap)
}

func keyPress(code: CGKeyCode, flags: CGEventFlags, pid: pid_t) {
    activate(pid)
    usleep(150_000)
    let source = CGEventSource(stateID: .hidSystemState)
    guard
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else { return }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(40_000)
    up.post(tap: .cghidEventTap)
}

// MARK: - Output

func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\t", with: "\\t")
}

func interesting(_ node: Node) -> Bool {
    if !node.id.isEmpty || !node.desc.isEmpty || !node.title.isEmpty || !node.actions.isEmpty {
        return true
    }
    let controls: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXTextField",
        "AXLink", "AXRow", "AXOutline", "AXRadioGroup", "AXMenuButton", "AXTabGroup",
        "AXDisclosureTriangle",
    ]
    return controls.contains(node.role)
}

func printNodes(_ nodes: [Node], json: Bool, target: Target) {
    if json {
        let entries: [[String: Any]] = nodes.map { node in
            var entry: [String: Any] = [
                "role": node.role, "window": node.window, "depth": node.depth,
                "actions": node.actions,
            ]
            if !node.id.isEmpty { entry["id"] = node.id }
            if !node.desc.isEmpty { entry["description"] = node.desc }
            if !node.title.isEmpty { entry["title"] = node.title }
            if !node.value.isEmpty { entry["value"] = node.value }
            if let enabled = node.enabled { entry["enabled"] = enabled }
            if let frame = node.frame {
                entry["x"] = Int(frame.origin.x)
                entry["y"] = Int(frame.origin.y)
                entry["width"] = Int(frame.width)
                entry["height"] = Int(frame.height)
            }
            return entry
        }
        let document: [String: Any] = [
            "target": ["pid": Int(target.pid), "name": target.name, "bundle": target.bundle],
            "nodes": entries,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        else {
            FileHandle.standardError.write(Data("could not encode json\n".utf8))
            exit(5)
        }
        FileHandle.standardOutput.write(data)
        print()
        return
    }
    for node in nodes {
        var line = "\(node.role) window=\(escaped(node.window)) depth=\(node.depth)"
        if !node.id.isEmpty { line += " id=\(escaped(node.id))" }
        if !node.desc.isEmpty { line += " desc=\(escaped(node.desc))" }
        if !node.title.isEmpty { line += " title=\(escaped(node.title))" }
        if !node.value.isEmpty { line += " value=\(escaped(node.value))" }
        if let enabled = node.enabled { line += " enabled=\(enabled)" }
        if !node.actions.isEmpty { line += " actions=\(node.actions.joined(separator: ","))" }
        if let frame = node.frame {
            line +=
                " frame=\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
                + "\(Int(frame.width)),\(Int(frame.height))"
        }
        print(line)
    }
}

// MARK: - Main

let options = parseArguments()

// Listing apps needs no target and no accessibility trust.
if options.command == "apps" {
    for app in runningApps().sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
        print(
            "\(app.processIdentifier)\t\(app.bundleIdentifier ?? "?")\t"
                + "\(app.localizedName ?? "?")\t\(app.isActive ? "active" : "")")
    }
    exit(0)
}

let target = resolveTarget(options)

// MARK: - Pixels

struct SampledColor {
    let red: Double
    let green: Double
    let blue: Double
    let count: Int

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// WCAG 2.1 relative luminance.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

func contrastRatio(_ left: SampledColor, _ right: SampledColor) -> Double {
    let high = max(left.luminance, right.luminance)
    let low = min(left.luminance, right.luminance)
    return (high + 0.05) / (low + 0.05)
}

/// The on-screen window of this process whose bounds contain the point, with its bounds in
/// screen points. AX frames use the same coordinate space, so no conversion is needed.
func windowID(containing point: CGPoint, pid: pid_t) -> (id: Int, bounds: CGRect)? {
    let list =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in list {
        guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else { continue }
        guard let raw = window[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary)
        else { continue }
        if bounds.contains(point) {
            return (window[kCGWindowNumber as String] as? Int ?? 0, bounds)
        }
    }
    return nil
}

func captureWindow(_ id: Int) -> NSBitmapImageRep? {
    let path = NSTemporaryDirectory() + "axdrv-\(getpid())-\(id).png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-o", "-x", "-l", String(id), path]
    do {
        try task.run()
    } catch {
        return nil
    }
    task.waitUntilExit()
    defer { try? FileManager.default.removeItem(atPath: path) }
    guard task.terminationStatus == 0,
        let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let image = NSBitmapImageRep(data: data), image.pixelsWide > 0
    else { return nil }
    return image
}

/// Pixel colors inside a rect of the capture, grouped by a 4-bit bucket per channel. The
/// bucket average keeps antialiased edge pixels from dragging the reported color.
func sampledColors(in image: NSBitmapImageRep, rect: CGRect) -> [SampledColor] {
    let minX = max(0, Int(rect.minX.rounded(.down)))
    let maxX = min(image.pixelsWide - 1, Int(rect.maxX.rounded(.up)))
    let minY = max(0, Int(rect.minY.rounded(.down)))
    let maxY = min(image.pixelsHigh - 1, Int(rect.maxY.rounded(.up)))
    guard minX <= maxX, minY <= maxY else { return [] }
    var buckets: [Int: (red: Double, green: Double, blue: Double, count: Int)] = [:]
    for y in minY...maxY {
        for x in minX...maxX {
            // Read the stored components as they are. `screencapture` writes the
            // composited values into a Display P3 file, and converting to sRGB shifts
            // them: the paper token came back 2 levels light and the ink 9.
            guard let color = image.colorAt(x: x, y: y) else { continue }
            let red = color.redComponent
            let green = color.greenComponent
            let blue = color.blueComponent
            let key =
                (Int(red * 15) << 8) | (Int(green * 15) << 4) | Int(blue * 15)
            let bucket = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (
                bucket.red + red, bucket.green + green, bucket.blue + blue, bucket.count + 1
            )
        }
    }
    return buckets.values
        .map {
            SampledColor(
                red: $0.red / Double($0.count), green: $0.green / Double($0.count),
                blue: $0.blue / Double($0.count), count: $0.count)
        }
        .sorted { $0.count > $1.count }
}

func printColorReport(
    label: String, frame: CGRect, colors: [SampledColor], windowBounds: CGRect, json: Bool
) {
    let total = max(colors.reduce(0) { $0 + $1.count }, 1)
    func share(_ color: SampledColor?) -> Double {
        guard let color else { return 0 }
        return Double(color.count) / Double(total)
    }
    let background = colors.first
    // The ink is the cluster that contrasts most with the background and still covers
    // enough pixels to be text rather than an edge artifact.
    let ink = colors.dropFirst().filter { share($0) >= 0.02 }
        .max { left, right in
            guard let background else { return false }
            return contrastRatio(left, background) < contrastRatio(right, background)
        }
    // Antialiased glyph edges win on average for thin type, so report the glyph core
    // separately: the smallest-luminance-distance-of-zero cluster that still exists.
    let peak = colors.dropFirst().filter { share($0) >= 0.001 }
        .max { left, right in
            guard let background else { return false }
            return contrastRatio(left, background) < contrastRatio(right, background)
        }
    func ratio(_ color: SampledColor?) -> Double {
        guard let background, let color else { return 1 }
        return contrastRatio(color, background)
    }
    // A point sample has one cluster. Reporting an ink share and a contrast there would be
    // noise, so only the pixel is printed.
    if colors.count <= 1 {
        if json {
            print(
                #"{"label":"\#(escaped(label))","point":[\#(Int(frame.minX)),\#(Int(frame.minY))],"#
                    + #""hex":"\#(background?.hex ?? "")"}"#)
        } else {
            print("\(Int(frame.minX)),\(Int(frame.minY))  \(background?.hex ?? "none")")
        }
        return
    }
    if json {
        let rows = colors.prefix(6).map {
            String(
                format: #"{"hex":"%@","share":%.3f,"luminance":%.3f}"#, $0.hex, share($0),
                $0.luminance)
        }
        print(
            #"{"label":"\#(escaped(label))","frame":[\#(Int(frame.minX)),\#(Int(frame.minY)),"#
                + #"\#(Int(frame.width)),\#(Int(frame.height))],"window":[\#(Int(windowBounds.minX)),"#
                + #"\#(Int(windowBounds.minY)),\#(Int(windowBounds.width)),\#(Int(windowBounds.height))],"#
                + #""background":"\#(background?.hex ?? "")","ink":"\#(ink?.hex ?? "")","#
                + #""inkShare":\#(String(format: "%.3f", share(ink))),"contrast":\#(String(format: "%.2f", ratio(ink))),"#
                + #""peak":"\#(peak?.hex ?? "")","peakShare":\#(String(format: "%.3f", share(peak))),"#
                + #""peakContrast":\#(String(format: "%.2f", ratio(peak))),"#
                + #""colors":[\#(rows.joined(separator: ","))]}"#)
        return
    }
    print("label      \(label)")
    print(
        "frame      \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
    )
    print(
        "background \(background?.hex ?? "none") \(String(format: "%.0f%%", share(background) * 100))"
    )
    print(
        "ink        \(ink?.hex ?? "none") \(String(format: "%.0f%%", share(ink) * 100))"
            + "  contrast \(String(format: "%.2f", ratio(ink))):1")
    print(
        "peak       \(peak?.hex ?? "none") \(String(format: "%.1f%%", share(peak) * 100))"
            + "  contrast \(String(format: "%.2f", ratio(peak))):1")
    let palette = colors.prefix(6).map {
        String(format: "%@ %.0f%%", $0.hex, share($0) * 100)
    }
    print("colors     \(palette.joined(separator: "  "))")
}

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("AX NOT TRUSTED\n".utf8))
    exit(3)
}

messagingTimeout = options.timeout
nodeLimit = options.maxNodes
let selector = Selector(options.operands)
let nodes = snapshot(target, depthLimit: options.depth)

switch options.command {
case "windows":
    let list =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in list {
        let owner = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        guard owner == target.pid else { continue }
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let name = window[kCGWindowName as String] as? String ?? ""
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print(
            "\(id)\t\(name)\t\(bounds["X"] ?? 0),\(bounds["Y"] ?? 0) "
                + "\(bounds["Width"] ?? 0)x\(bounds["Height"] ?? 0)")
    }

case "activate":
    activate(target.pid)
    print("activated \(target.name)")

case "dump":
    let selected = selector.isEmpty ? nodes.filter(interesting) : nodes.filter(selector.matches)
    printNodes(options.all && selector.isEmpty ? nodes : selected, json: options.json, target: target)

case "texts":
    for node in nodes where node.role == "AXStaticText" {
        if selector.isEmpty || selector.matches(node), !node.value.isEmpty {
            print(escaped(node.value))
        }
    }

case "press":
    guard !selector.isEmpty else { usage() }
    let node = resolve(selector, in: nodes)
    print(press(node) ? "pressed \(describe(node))" : "press failed \(describe(node))")

case "select":
    guard !selector.isEmpty else { usage() }
    if selectRow(containing: selector, in: nodes) {
        print("selected row containing \(options.operands.joined(separator: " "))")
    } else {
        FileHandle.standardError.write(Data("no selectable row matched\n".utf8))
        exit(5)
    }

case "click":
    guard !selector.isEmpty else { usage() }
    let node = resolve(selector, in: nodes)
    print(click(node, pid: target.pid) ? "clicked \(describe(node))" : "click failed \(describe(node))")

case "frame":
    guard !selector.isEmpty else { usage() }
    let node = resolve(selector, in: nodes)
    guard let frame = node.frame else {
        FileHandle.standardError.write(Data("element has no frame\n".utf8))
        exit(5)
    }
    print(
        "\(Int(frame.origin.x)),\(Int(frame.origin.y)),"
            + "\(Int(frame.width)),\(Int(frame.height))")

case "type":
    guard let text = options.operands.first else { usage() }
    typeText(text, pid: target.pid)
    print("typed \(text.count) characters into \(target.name)")

case "key":
    guard let raw = options.operands.first, let code = UInt16(raw) else { usage() }
    var flags: CGEventFlags = []
    for modifier in options.operands.dropFirst() {
        switch modifier {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "option", "alt": flags.insert(.maskAlternate)
        case "control", "ctrl": flags.insert(.maskControl)
        default: usage()
        }
    }
    keyPress(code: CGKeyCode(code), flags: flags, pid: target.pid)
    print("sent key \(code) to \(target.name)")

case "color":
    if let point = options.at {
        guard let window = windowID(containing: point, pid: target.pid) else {
            FileHandle.standardError.write(Data("no window of this app contains the point\n".utf8))
            exit(5)
        }
        guard let image = captureWindow(window.id) else {
            FileHandle.standardError.write(Data("window capture failed. Grant Screen Recording.\n".utf8))
            exit(4)
        }
        let scale = CGSize(
            width: Double(image.pixelsWide) / Double(window.bounds.width),
            height: Double(image.pixelsHigh) / Double(window.bounds.height))
        let local = CGPoint(
            x: (point.x - window.bounds.minX) * scale.width,
            y: (point.y - window.bounds.minY) * scale.height)
        let colors = sampledColors(
            in: image, rect: CGRect(x: local.x - 1, y: local.y - 1, width: 3, height: 3))
        printColorReport(
            label: "point \(Int(point.x)),\(Int(point.y))", frame: CGRect(origin: point, size: .zero),
            colors: colors, windowBounds: window.bounds, json: options.json)
        exit(0)
    }
    guard !selector.isEmpty else { usage() }
    let node = resolve(selector, in: nodes)
    guard let frame = node.frame else {
        FileHandle.standardError.write(Data("element has no frame\n".utf8))
        exit(5)
    }
    let center = CGPoint(x: frame.midX, y: frame.midY)
    guard let window = windowID(containing: center, pid: target.pid) else {
        FileHandle.standardError.write(Data("no window of this app contains the element\n".utf8))
        exit(5)
    }
    guard let image = captureWindow(window.id) else {
        FileHandle.standardError.write(Data("window capture failed. Grant Screen Recording.\n".utf8))
        exit(4)
    }
    // The capture is in pixels; AX reports points. The ratio is the Retina scale.
    let scale = CGSize(
        width: Double(image.pixelsWide) / Double(window.bounds.width),
        height: Double(image.pixelsHigh) / Double(window.bounds.height))
    let rect = CGRect(
        x: (frame.minX - window.bounds.minX) * scale.width,
        y: (frame.minY - window.bounds.minY) * scale.height,
        width: frame.width * scale.width,
        height: frame.height * scale.height
    ).integral
    printColorReport(
        label: describe(node), frame: frame,
        colors: sampledColors(in: image, rect: rect), windowBounds: window.bounds,
        json: options.json)

default:
    usage()
}
