// axdrv: drive a running macOS app through its accessibility tree instead of pixel
// coordinates. Standalone tool: no project dependency and no hardcoded bundle id.
//
// Build:  swiftc -O axdrv.swift -o /tmp/axdrv
// Help:   /tmp/axdrv help
//
// Target: --pid <pid>, --app <name or bundle id>, or the frontmost app.
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
    var command = ""
    var operands: [String] = []
}

func usage() -> Never {
    print(
        """
        usage: axdrv [--pid <pid>|--app <name|bundle>] [--json] [--all] [--depth <n>] <command> [operand]

        target:
          --pid <pid>          drive this process
          --app <name|bundle>  drive the first app with this bundle id or name
          (neither)            drive the frontmost app

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

func makeNode(_ element: AXUIElement, window: String, depth: Int) -> Node {
    Node(
        element: element,
        role: str(element, kAXRoleAttribute as String),
        id: str(element, "AXIdentifier"),
        desc: str(element, "AXDescription"),
        title: str(element, kAXTitleAttribute as String),
        value: str(element, kAXValueAttribute as String),
        enabled: attr(element, "AXEnabled") as? Bool,
        actions: actions(element),
        window: window,
        depth: depth,
        origin: point(element, kAXPositionAttribute as String),
        size: size(element))
}

/// Windows only. The menu bar is excluded on purpose: menu items are better reached with
/// keyboard shortcuts, and including the full menu tree floods every dump.
func walk(_ root: AXUIElement, window: String, depthLimit: Int, into nodes: inout [Node]) {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (element, depth) = stack.popLast() {
        nodes.append(makeNode(element, window: window, depth: depth))
        if depth < depthLimit {
            for child in kids(element) { stack.append((child, depth + 1)) }
        }
    }
}

func snapshot(_ target: Target, depthLimit: Int) -> [Node] {
    let app = AXUIElementCreateApplication(target.pid)
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

func click(_ node: Node) -> Bool {
    guard let frame = node.frame else { return false }
    let center = CGPoint(x: frame.midX, y: frame.midY)
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
let target = resolveTarget(options)

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("AX NOT TRUSTED\n".utf8))
    exit(3)
}

let selector = Selector(options.operands)
let nodes = snapshot(target, depthLimit: options.depth)

switch options.command {
case "apps":
    for app in runningApps().sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
        print(
            "\(app.processIdentifier)\t\(app.bundleIdentifier ?? "?")\t"
                + "\(app.localizedName ?? "?")\t\(app.isActive ? "active" : "")")
    }

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
        if (selector.isEmpty || selector.matches(node)), !node.value.isEmpty {
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
    print(click(node) ? "clicked \(describe(node))" : "click failed \(describe(node))")

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

default:
    usage()
}
