# switft

macOS UI-driving helpers written in Swift. The directory name is an intentional
misspelling of "swift"; it holds throwaway-but-working Swift scripts that drive a
running macOS app for testing purposes.

## Why `axdrv.swift` exists

`axdrv.swift` is a standalone command-line driver built on the macOS
Accessibility (AX) API. It reads the accessibility tree of a running
application so an automated test (or a human in a terminal) can find and
operate on controls by their `AXIdentifier` or title, instead of guessing
pixel coordinates or recording brittle mouse scripts.

Concretely, it exists to answer these questions from a shell:

- What controls and text does the running app currently show? (`dump`, `texts`)
- Can I press this button / click this control by name? (`press`, `click`, `clickid`, `clicktitle`)
- Can I select a row in a list by identifier? (`select`)
- Where exactly is this control on screen? (`frame`)

It is a single-file, zero-dependency Swift program: `AppKit` and
`ApplicationServices` only. Build it with the system `swiftc`:

```sh
swiftc -O swift/axdrv.swift -o /tmp/axdrv
```

It needs Accessibility permission (System Settings > Privacy & Security >
Accessibility) granted to whatever terminal or process runs it. It targets the
app with bundle id `id.web.widnyana.chet` by default; set `AXDRV_PID` to point
it at a specific running instance.

## When to use `axdrv.swift`

- You are writing an automated UI test or script for `chet` and want to press
  or assert on controls by id/text instead of pixel coordinates. Pixel
  scripts break on any layout change; AX identifiers survive layout changes.
- You are iterating on the app and want a quick terminal view of what the UI
  currently exposes (`dump`, `texts`) without adding logging to the app.
- You need to simulate a real user interaction end to end (`click*`,
  `select`), the same event path a human produces, while a build of the app
  is running.

When not to use it: unit-level logic tests (run the logic directly), CI
headless environments (the AX API needs a logged-in GUI session plus
Accessibility trust), and driving apps other than `chet` without editing the
hardcoded bundle id or passing `AXDRV_PID`.

Full command reference and internals: see [`axdrv.md`](axdrv.md).
