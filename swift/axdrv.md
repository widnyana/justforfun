# axdrv

A one-file macOS UI driver that addresses controls through the accessibility tree instead
of screen coordinates. No dependencies beyond the system SDK (`AppKit`,
`ApplicationServices`), no hardcoded bundle id, no project integration.

```
axdrv apps                      # find the pid
axdrv --pid 4321 dump --json    # capture the tree
axdrv --pid 4321 press id=note.new
axdrv --pid 4321 type "Meeting notes"
axdrv --pid 4321 texts "Meeting notes"
```

## Why not coordinates

A coordinate click encodes one layout at one window size on one display. It breaks when a
toolbar moves, a sidebar collapses, a row is added, or the window opens on another Space.
An accessibility selector addresses what the control is, not where it is drawn.

## Accessibility tree vs the DOM

The mental model transfers, the details do not.

| Web DOM | macOS accessibility tree |
|---|---|
| One document per page | One tree per application, split across its windows |
| `id="save"` | `AXIdentifier` (`id=save`) |
| Element tag, `role` | `AXRole` (`role=AXButton`) |
| `aria-label`, visible text | `AXDescription` (accessible label), `AXTitle`, `AXValue` |
| CSS classes | No equivalent. There is nothing to style-query |
| `querySelector`, XPath | Walk the tree and filter attributes. This tool does that |
| `element.click()` | `AXPress` action, or a synthesized mouse click |
| `element.disabled` | `AXEnabled` plus the element's action list |
| DevTools Elements panel | `axdrv dump --json` |
| `element.focus()`, `KeyboardEvent` | `AXFocused` for reads; typing and key events go through `CGEvent` |
| Same tree for every browser | Each app owns its tree; quality depends on the app and framework |
| Inspect any website without changes | The app must expose accessibility attributes. Most native controls do; custom-drawn views may expose nothing |

The tree is not a document. There is no CSS selector engine, no class names, and no stable
DOM path. What replaces them is a small set of attributes plus the actions each element
declares. Selector design is therefore an application design concern, not a test-only hack.

## Designing selectors

Prefer, in this order:

1. **Identifier.** `id=note.new`. Stable across languages and layout. Set by the app
   developer.
2. **Role plus accessible label.** `role=AXButton desc=Back`. Works when the app exposes a
   meaningful label. Localized, so a test suite that runs in several languages needs ids.
3. **Role plus title.** `role=AXButton title=Settings…`. Common in AppKit; also localized.
4. **Bare substring.** `dump "Save"` or `press "Save"`. A discovery aid and a last resort. It
   matches across id, description, title, and value, so it goes stale with copy changes.

Never select by coordinate, ordinal position, or a label that contains changing data
(`3 items selected`, `Remove Acme`, a file name). Never put an identifier on a wrapper that
contains other controls: SwiftUI propagates the wrapper's identifier down and overwrites the
identifiers of its children. Put it on the control that is pressed.

Name identifiers `screen.element` in lowercase, for example `sidebar.library`,
`note.new`, `editor.title`, `dialog.cancel`. Keep them stable across releases; tests and
automation are allowed to depend on them.

Add them in code:

```swift
// SwiftUI
Button("New note") { create() }
    .accessibilityIdentifier("note.new")
    .accessibilityLabel("New note")

// AppKit
button.setAccessibilityIdentifier("note.new")
button.setAccessibilityLabel("New note")

// Custom NSView: role and label must be declared, or the view is invisible to AX
setAccessibilityElement(true)
setAccessibilityRole(.button)
setAccessibilityLabel("New note")
setAccessibilityIdentifier("note.new")
```

Roles follow the control, not the identifier:

| SwiftUI control | AX role |
|---|---|
| `Button` | `AXButton` |
| Link-style button | `AXLink` |
| `Toggle` switch or checkbox | `AXCheckBox` |
| `Picker` menu | `AXPopUpButton` |
| Segmented `Picker` | `AXRadioGroup` with `AXRadioButton` children |
| `Slider` | `AXSlider` |
| `TextField`, `.searchable` | `AXTextField` |
| Sidebar `List` | `AXOutline` > `AXRow` > `AXCell` |
| Sheet | `AXSheet` |

## Build and permissions

```sh
swiftc -O axdrv.swift -o /tmp/axdrv
```

1. The process that runs `axdrv` needs Accessibility permission in System Settings >
   Privacy & Security > Accessibility. Without it the tool prints `AX NOT TRUSTED` and exits
   3. The permission belongs to the caller, not to the target app.
2. A logged-in GUI session is required. This is not a headless CI tool; run it on a runner
   with a real desktop session and the permission granted.
3. The target app must be running.

## Choosing the target

- `--pid <pid>`: exact process. Use this when more than one copy of the app runs, or when a
  menu click could otherwise hit the wrong instance.
- `--app <bundle id|name>`: first running regular app matching the bundle id, then the name.
- Neither: the frontmost app.

`axdrv apps` lists running regular apps with pid, bundle id, name, and the active marker.

## Commands

```
axdrv [--pid <pid>|--app <name|bundle>] [--json] [--all] [--depth <n>] <command> [operand]
```

| Command | Operand | Result |
|---|---|---|
| `apps` | - | pid, bundle, name, active for every regular app |
| `windows` | - | window id, title, and screen bounds for the target |
| `activate` | - | brings the target app forward |
| `dump` | optional selector | accessibility nodes, filtered to actionable or named elements by default |
| `dump --all` | optional selector | every node in every window |
| `dump --json` | optional selector | one JSON document with the target and all nodes |
| `texts` | optional selector | values of `AXStaticText` nodes, one per line |
| `press` | selector | performs `AXPress` on exactly one match |
| `select` | selector | sets `AXSelectedRows` on the outline row containing one match |
| `click` | selector | synthesized mouse click at the center of one match |
| `frame` | selector | prints `x,y,w,h` in global screen points |
| `type` | text | activates the app and types the text |
| `key` | keycode and modifiers | activates the app and presses a key |

`--depth` caps the tree walk (default 60). `--json` and `--all` apply to `dump`.

### Selector syntax

Terms are `key=value`, ANDed:

```
id=note.new
role=AXButton desc=Back
role=AXButton enabled=true
title=Settings…
value=3 items selected
```

Keys: `id`, `role`, `desc` (`description`), `title`, `value`, `enabled` (true or false).
A term without `=` is a case-insensitive substring match over id, description, title, and
value. Quote operands that contain spaces.

Exactly one match is required for `press`, `click`, `frame`, and `select`. Zero matches exits
5. Several matches exits 6 and prints the candidates, so a selector cannot silently act on
the wrong element. `dump` and `texts` accept an optional selector and filter.

Tokens in selectors are not shell expressions. There are no `#`, `.`, `[attr]`, combinators,
or wildcards. This is deliberate: the attribute set is small, and `id`/`role`/`desc` cover
what native apps expose.

### JSON shape

```json
{
  "target": { "pid": 4321, "name": "Example", "bundle": "com.example.app" },
  "nodes": [
    {
      "role": "AXButton",
      "window": "Library",
      "depth": 3,
      "id": "note.new",
      "description": "New note",
      "enabled": true,
      "actions": ["AXPress"],
      "x": 812, "y": 52, "width": 28, "height": 22
    }
  ]
}
```

Store one file per screen. Diff it after a UI change to see which selectors disappeared or
moved. Positions are useful for `click` and for screenshots; identifiers are what tests should
assert on.

## A real scenario, anonymized

A native note-taking app has a sidebar, a list, an editor, and a toolbar. Some controls have
identifiers, some only labels.

1. **Find the instance.**

   ```sh
   axdrv apps | grep -i notes
   # 4321  com.example.notes  Example Notes  active
   ```

2. **Capture the tree before touching anything.**

   ```sh
   axdrv --pid 4321 dump --json > /tmp/notes-tree.json
   jq -r '.nodes[] | select(.id or .description) | [.role, .id, .description] | @tsv' \
     /tmp/notes-tree.json | sort -u
   ```

   The output shows `id=note.new`, `id=sidebar.library`, `id=editor.title`, and a toolbar
   button with only `description: Share`. The share button needs an identifier before the test
   can rely on it.

3. **Add the missing selector in the app.**

   ```swift
   Button(action: share) { Image(systemName: "square.and.arrow.up") }
       .accessibilityIdentifier("toolbar.share")
       .accessibilityLabel("Share note")
   ```

   Rebuild, relaunch, and capture again. Confirm the new id appears.

4. **Drive the flow and assert state, not pixels.**

   ```sh
   axdrv --pid 4321 press id=note.new
   axdrv --pid 4321 type "Meeting notes"
   axdrv --pid 4321 texts "Meeting notes"        # prints the line if the editor exposes it
   axdrv --pid 4321 press id=toolbar.share
   axdrv --pid 4321 dump id=dialog.share --json  # inspect the sheet
   axdrv --pid 4321 press id=dialog.cancel
   axdrv --pid 4321 select id=sidebar.library    # outline row, not a press
   ```

   If `texts` does not expose the editor content, the editor is custom-drawn; assert on a
   saved state or on an element that does expose the title, rather than falling back to
   coordinates.

5. **Check a disabled control before pressing it.**

   ```sh
   axdrv --pid 4321 dump id=note.save
   # AXButton ... id=note.save enabled=false actions=AXPress
   ```

   `AXPress` on a disabled element can report success and do nothing. Assert `enabled=true`
   first, or watch the resulting state.

6. **Capture the window for a human review.**

   ```sh
   axdrv --pid 4321 windows
   # 98765  Notes  0,0 1440x900
   screencapture -x -l 98765 /tmp/notes.png
   ```

   Window ids come from CoreGraphics; capturing by id does not depend on what is on top.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Command ran. `press`, `click`, `select` print their own result; read the text |
| 2 | Usage error |
| 3 | Accessibility is not trusted for the calling process |
| 4 | Target app or pid not found |
| 5 | Selector matched nothing, or an element has no frame |
| 6 | Selector matched more than one element |

`press failed` is printed with exit 0 because the AX action returned an error. Treat the text
as the result, or wrap the call and check for `failed`.

## Pitfalls

- **Disabled elements accept `AXPress`.** The AX call returns success; the control does
  nothing. Read `enabled` from `dump` and assert it.
- **`AXPress` is not a click.** It invokes the control's action. Some controls expose no press
  action, ignore synthesized presses, or need real focus. `click` posts HID events and needs
  the window visible and unoccluded at that point. `select` is the only correct way to move
  an outline selection.
- **Wrapper identifiers replace child identifiers.** In SwiftUI an identifier on a container
  propagates down. Put it on the control.
- **Rows are not buttons.** A sidebar or table row is `AXRow` under `AXOutline`. It has no
  press action; set `AXSelectedRows`.
- **Menus are excluded from the tree.** Use `key` for shortcuts. Pressing a menu item without
  opening its menu usually does nothing, and menu clicks by process name can hit another
  instance.
- **The snapshot is taken once per invocation.** After an action changes the UI, run a new
  `axdrv` call. A single call does not re-walk.
- **Multiple instances are common.** A test build, a release build, and a user's copy can all
  run. Always pass `--pid` in automation.
- **Labels are localized and dynamic.** Titles and descriptions change with language, counts,
  and file names. Identifiers do not.
- **Custom drawing may expose nothing.** A canvas, a Metal view, or a web view can be opaque
  to AX. That is an app accessibility gap, not something a driver can work around.
- **`type` and `key` activate the app and send events to whatever has focus.** Click or press
  the field first; do not assume focus.
- **Coordinates are global screen points, top-left origin.** They match `CGEvent` and
  `screencapture`, not a window-relative space.
- **`--all` is large.** Use a selector or the default actionable filter unless the full tree
  is the point.
- **Retina does not change coordinates.** AX frames and mouse events are in points. Screenshot
  pixels are not.
- **TCC prompts appear once per caller.** A headless runner without a GUI session and the
  permission cannot use the tool.

## Limits

`axdrv` is an observation and input tool, not a test framework. It does not wait for
conditions, retry, or assert. A test script composes those around it: poll `dump` for a
selector, assert on `texts` or `enabled`, and use the exit codes to fail fast.
