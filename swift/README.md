# swift helpers

Throwaway-but-working Swift scripts for driving a running macOS app from a terminal or a
test script. The directory name is an intentional misspelling.

## axdrv

`axdrv.swift` is a standalone command-line driver built on the macOS Accessibility (AX)
API. It reads the accessibility tree of a running app so a human or a test can address
controls by what they are, not where they are drawn.

What it answers from a shell:

- Which controls and text does the running app expose? (`dump`, `texts`, `dump --json`)
- Can I press or click this control by identifier or label? (`press`, `click`)
- Can I move a list or sidebar selection? (`select`)
- Where is this control on screen? (`frame`)
- Which process or window am I looking at? (`apps`, `windows`, `--pid`)

It is one file with no dependencies beyond `AppKit` and `ApplicationServices`:

```sh
swiftc -O swift/axdrv.swift -o /tmp/axdrv
/tmp/axdrv apps
/tmp/axdrv --pid 4321 dump
```

The caller needs Accessibility permission in System Settings > Privacy & Security >
Accessibility. The target app must be running in a logged-in GUI session.

Target selection is `--pid`, `--app <bundle id or name>`, or the frontmost app. Selectors are
`key=value` terms (`id=note.new`, `role=AXButton desc=Back`, `enabled=true`), and a selector
must match exactly one element before it can act.

Full command reference, selector design, DOM comparison, JSON shape, an anonymized walkthrough,
and the pitfalls: see [`axdrv.md`](axdrv.md).
