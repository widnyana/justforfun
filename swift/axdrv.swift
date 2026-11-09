// Selector-driven UI driver. Reads the accessibility tree of the running app so a test
// can press a control by identifier instead of guessing pixel coordinates.
// Build: swiftc -O scripts/axdrv.swift -o /tmp/axdrv
import AppKit
import ApplicationServices

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}

func kids(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func str(_ el: AXUIElement, _ name: String) -> String {
    (attr(el, name) as? String) ?? ""
}

func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
    guard let v = attr(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func size(_ el: AXUIElement) -> CGSize? {
    guard let v = attr(el, kAXSizeAttribute as String), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
    return s
}

func all(_ root: AXUIElement) -> [AXUIElement] {
    var out: [AXUIElement] = []
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (el, depth) = stack.popLast() {
        out.append(el)
        if depth < 40 { for k in kids(el) { stack.append((k, depth + 1)) } }
    }
    return out
}

func click(_ el: AXUIElement) -> Bool {
    guard let origin = point(el, kAXPositionAttribute as String), let s = size(el) else { return false }
    let center = CGPoint(x: origin.x + s.width / 2, y: origin.y + s.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
    else { return false }
    down.post(tap: .cghidEventTap)
    usleep(30_000)
    up.post(tap: .cghidEventTap)
    return true
}

let args = CommandLine.arguments
guard args.count > 1 else {
    print(
        "usage: axdrv dump|texts|press <id>|select <row id>|click <text>|"
            + "clickid <id>|clicktitle <title>|frame <id>")
    exit(2)
}
guard AXIsProcessTrusted() else { print("AX NOT TRUSTED"); exit(3) }
// More than one build of the app can be running (a `.build/xc` copy and another build).
// AXDRV_PID picks the target; without it the first instance by bundle id is used.
let envPID = ProcessInfo.processInfo.environment["AXDRV_PID"].flatMap { Int32($0) }
guard
    let pid = envPID
        ?? NSRunningApplication.runningApplications(withBundleIdentifier: "id.web.widnyana.chet").first?
        .processIdentifier
else {
    print("chet not running")
    exit(4)
}
let els = all(AXUIElementCreateApplication(pid))

switch args[1] {
case "dump":
    for el in els {
        let id = str(el, "AXIdentifier")
        let role = str(el, kAXRoleAttribute as String)
        let title = str(el, kAXTitleAttribute as String)
        let value = str(el, kAXValueAttribute as String)
        if !id.isEmpty || !title.isEmpty || !value.isEmpty {
            print("\(role) id=\(id) title=\(title) value=\(value)")
        }
    }
case "texts":
    for el in els where str(el, kAXRoleAttribute as String) == "AXStaticText" {
        let v = str(el, kAXValueAttribute as String)
        if !v.isEmpty { print(v) }
    }
case "press":
    let target = args[2]
    if let hit = els.first(where: { str($0, "AXIdentifier") == target }) {
        print(AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success ? "pressed \(target)" : "press failed")
    } else {
        print("no element with id \(target)")
    }
case "select":
    let target = args[2]
    for outline in els where str(outline, kAXRoleAttribute as String) == "AXOutline" {
        for row in all(outline) where str(row, kAXRoleAttribute as String) == "AXRow" {
            if all(row).contains(where: { str($0, "AXIdentifier") == target }) {
                let set = AXUIElementSetAttributeValue(
                    outline, "AXSelectedRows" as CFString, [row] as CFArray)
                print(set == .success ? "selected \(target)" : "select failed")
                exit(0)
            }
        }
    }
    print("no selectable row with id \(target)")
    exit(4)
case "clicktitle":
    let target = args[2]
    if let hit = els.first(where: { str($0, kAXTitleAttribute as String) == target }) {
        print(click(hit) ? "clicked \(target)" : "click failed")
    } else {
        print("no element titled \(target)")
    }
case "frame":
    let target = args[2]
    if let hit = els.first(where: { str($0, "AXIdentifier") == target }),
        let origin = point(hit, kAXPositionAttribute as String), let s = size(hit)
    {
        print("\(target) x=\(origin.x) y=\(origin.y) w=\(s.width) h=\(s.height)")
    } else {
        print("no framed element \(target)")
    }
case "clickid":
    let target = args[2]
    if let hit = els.first(where: { str($0, "AXIdentifier") == target }) {
        print(click(hit) ? "clicked \(target)" : "click failed")
    } else {
        print("no element with id \(target)")
    }
case "click":
    let target = args[2]
    if let hit = els.first(where: { str($0, kAXValueAttribute as String) == target }) {
        print(click(hit) ? "clicked \(target)" : "click failed")
    } else {
        print("no element with value \(target)")
    }
default:
    print("unknown command")
}

