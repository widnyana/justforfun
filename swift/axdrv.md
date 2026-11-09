# axdrv

Accessibility-driven UI driver for a running macOS app. One file, no
dependencies beyond the system SDK: `AppKit` + `ApplicationServices`.

## Purpose

Tests and automation for a desktop app are usually brittle: they click at
recorded pixel coordinates that break on any layout change. `axdrv` takes a
different path. It walks the app's accessibility tree and lets you address
controls the way assistive technology does, by role, `AXIdentifier`, title, or
value. A test asserts on what the app exposes and presses controls by name.

## When to use it

- Writing or debugging an automated UI test for the app: press and assert by
  id/text so the test survives layout changes.
- Inspecting what a running instance actually exposes (`dump`, `texts`)
  without recompiling the app.
- Exercising a real user interaction path (`click*`, `select`) end to end,
  including controls that do not respond to `AXPress`.
- Picking between several concurrently running builds of the app via
  `AXDRV_PID`.

Not the right tool for: logic-level tests (call the code directly), headless
CI (AX needs a logged-in GUI session and Accessibility trust), or driving
other apps without passing `AXDRV_PID` or changing the hardcoded bundle id.

## Build

```sh
swiftc -O switft/axdrv.swift -o /tmp/axdrv
```

## Requirements

1. Accessibility trust. The process that runs `axdrv` (your terminal, or a
   test runner) needs permission in System Settings > Privacy & Security >
   Accessibility. Without it the tool prints `AX NOT TRUSTED` and exits 3.
2. The target app is running. By default it looks for the first instance with
   bundle id `id.web.widnyana.chet`. Not running: prints `chet not running`,
   exits 4.

### Target selection: `AXDRV_PID`

More than one build of the app can be running at the same time (for example a
`.build/xc` copy next to another build). By bundle id alone it is ambiguous.
Set `AXDRV_PID` to the process id of the instance you want to drive:

```sh
AXDRV_PID=12345 /tmp/axdrv dump
```

`AXDRV_PID` wins over the bundle-id lookup; without it, the first instance
found by bundle id is used.

## Commands

    axdrv dump|texts|press <id>|select <row id>|click <text>|clickid <id>|clicktitle <title>|frame <id>

All commands snapshot the accessibility tree once at startup and then match
against that snapshot.

| Command | Argument | What it does | Exit cases |
|---|---|---|---|
| `dump` | - | Prints every element that has a non-empty identifier, title, or value, as `role id=... title=... value=...`. The discovery view: run this first to learn what ids exist. | - |
| `texts` | - | Prints the value of every `AXStaticText` element, one per line, in tree order. For asserting visible screen text. | - |
| `press` | element id | Finds the element whose `AXIdentifier` equals the id and performs the AX press action (`kAXPressAction`) on it. Fires the control's own action handler. | `press failed` on AX error, `no element with id <id>` if not found |
| `select` | row id | Finds the `AXOutline`, walks its rows, and selects the `AXRow` that contains an element with the given `AXIdentifier`, by setting `AXSelectedRows` on the outline. | `no selectable row with id <id>` and exit 4 if not found |
| `click` | text | Finds the element whose `AXValue` equals the given text and synthesizes a real mouse click at its center. | `click failed` if no geometry, `no element with value <text>` if not found |
| `clickid` | element id | Same synthesized click as `click`, matched by `AXIdentifier`. | same as `click` |
| `clicktitle` | title | Same synthesized click as `click`, matched by `AXTitle`. Use this for elements without a stable identifier. | same as `click` |
| `frame` | element id | Prints the screen-frame of the element with the given id: `x= y= w= h=` in global screen coordinates (top-left origin). For tests that need geometry, e.g. drags. | `no framed element <id>` if not found or no geometry |

## How it works

### Snapshot construction

`all(_:)` does an iterative depth-first walk from the application root
(`AXUIElementCreateApplication(pid)`), pushing children with a depth counter
and popping the last element first. The depth counter caps recursion at 40
levels: the tree is finite and hostile apps (or bugs in the app's own AX
implementation) can produce deep or cyclic structures; the cap bounds the walk
instead of hanging. The result is a flat array; every command matches against
it with `first(where:)` or a `where` filter.

Order is DFS-with-a-stack, so siblings end up in reverse discovery order and
children are interleaved with parents. For `dump` and `texts` the exact order
rarely matters; for `press`/`click` matching it matters only if two elements
share an identifier, in which case the last-visited match wins (the flat array
is searched front to back, and back-to-front tree order means the earliest
tree element is last). In practice ids in the target app are unique, so this
is a non-issue, but it is worth knowing before you rely on "first match".

### Attribute helpers

- `attr(_:_:)` wraps `AXUIElementCopyAttributeValue` and returns nil on any AX
  error. Every lookup failure collapses to nil/empty rather than throwing.
- `str(_:_:)` is `attr` plus `as? String`, returning `""` for anything that is
  not a string. Used for role, title, value, identifier reads.
- `point(_:_:)` reads an AX value and decodes it as `CGPoint` via
  `AXValueGetValue(_:.cgPoint:)`, guarding the CF type first. Used for
  `kAXPositionAttribute`.
- `size(_:)` does the same for `kAXSizeAttribute` into a `CGSize`.
- `kids(_:)` reads `kAXChildrenAttribute` as `[AXUIElement]`.

### The two ways of pressing

`press` and `click*` are deliberately different mechanisms:

- `press` calls `AXUIElementPerformAction(hit, kAXPressAction)`. No mouse
  movement, no focus change, no window activation. The control's own action
  selector runs. This is the clean path, but it only works for controls that
  expose a press action.
- `click*` synthesizes real HID-level mouse events. It reads the element's
  position and size, computes the center point, posts `leftMouseDown`, sleeps
  30 ms, then posts `leftMouseUp` at the HID event tap
  (`CGEvent.post(tap: .cghidEventTap)`). This works for anything that reacts
  to a genuine click, including controls that ignore AX press actions, and it
  exercises the same code path a human finger would. Cost: it moves the
  pointer, requires the window to be visible and not occluded at that point,
  and whatever is under the cursor gets clicked.

Rule of thumb: `press` when an identifier exists and a press action is
supported, `click*` (or `select` for outline rows) otherwise.

### `select` details

Outline rows are not always children of the outline in one hop; `select` walks
the full subtree of every `AXOutline` looking for an `AXRow` whose descendants
contain the target identifier. Selection is applied by setting
`AXSelectedRows` to a one-element array on the outline itself, which is how
multi-select-capable outlines are meant to be driven. It exits 0 on success
even if the AX set call failed, but prints `select failed` in that case.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (or the command printed its result) |
| 2 | Usage error: no command argument, or unknown command |
| 3 | Accessibility not trusted for this process |
| 4 | Target app not running / target not found (`select` miss) |

## Notes and caveats

- The tree snapshot is taken once per invocation. If the app's UI changes
  after the snapshot, a second `axdrv` call sees the new state; a single call
  does not re-walk.
- `frame` coordinates are global screen coordinates (macOS top-left origin),
  same space the CGEvent click uses, so `frame` output and `click*` targeting
  agree.
- `usleep(30_000)` between mouse down and up is a deliberate human-ish pause;
  some controls ignore a zero-delay click.
- The app target (`id.web.widnyana.chet`) is hardcoded in this file. If you
  reuse `axdrv` for another app, change that one string or always pass
  `AXDRV_PID`.
