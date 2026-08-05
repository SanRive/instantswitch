# space-switch-daemon

Near-instant macOS Space switching, bound to mouse side buttons via Hammerspoon.

**56 ms instead of ~1100 ms**, measured on macOS 27.0 (26A5388g).

> Built on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)
> and [FasterSwiper](https://github.com/mgbowen/FasterSwiper). See
> [NOTICE](NOTICE) for provenance, licensing, and the changes made here.

---

## Why this exists

macOS 27 broke every third-party way of changing Space. Measured, not assumed:

| Approach | Result |
|---|---|
| `hs.spaces.gotoSpace()` | Dead. Neither Dock nor WindowManager exposes the Mission Control accessibility tree (`mc`) anymore. |
| Synthetic `ctrl`+arrow via `hs.eventtap` | Ignored. The space-switch hotkey only accepts real HID events. |
| `CGSManagedDisplaySetCurrentSpace`, `CGSShowSpaces`/`CGSHideSpaces` | **Fake.** Updates bookkeeping only — `CGSGetActiveSpace` reports the new space, but the WindowServer never performs the transition. The on-screen window list is byte-identical before and after: you keep looking at the same windows. |
| System Events pressing `ctrl`+arrow | Works, but ~1100 ms — and ~97% of that is the animation, so there is nothing to optimise on the caller's side. |
| High-velocity synthetic Dock swipe | Works, and skips the animation. This is what we use. |

## Why a daemon

**The gesture is only acted on when it is posted from a long-lived process.**

This is the key finding and the reason upstream's CLI does not work on macOS 27
while their menu-bar app does. A process that posts the events and exits — even
with a runloop pump — is silently ignored: the calls return success and nothing
happens. `spaced` therefore holds the event tap open and reads commands on
stdin (`left`, `right`, `speed <n>`, `quit`), one line each.

## Build

Requires Command Line Tools. No Xcode or Swift needed — it is plain C.

```sh
./build.sh ~/.hammerspoon/bin/spaced
```

## Grant Accessibility

The daemon posts synthetic input, so macOS requires Accessibility permission.
It does **not** inherit Hammerspoon's — it needs its own.

1. System Settings → Privacy & Security → **Accessibility** → **+**
2. Press <kbd>⌘⇧G</kbd>, enter the directory you built into, select `spaced`
3. Toggle it on

The grant is tied to the binary's **path and code hash**. Rebuilding or moving
it silently invalidates the grant — switching will just stop working. Remove
and re-add the entry after any rebuild.

If it is not granted, `spaced` exits immediately with `iss_init failed`.

## Hook it up

Copy [`hammerspoon/init.example.lua`](hammerspoon/init.example.lua) into
`~/.hammerspoon/init.lua` (or merge the space-switching section into your
existing config) and reload Hammerspoon. It binds mouse button 3 to "space
left" and button 4 to "space right", and swallows those buttons so apps do not
also receive back/forward.

Set `SPACE_BUTTON_DEBUG = true` if your mouse reports different button numbers.

Mac Mouse Fix, if installed, must not be capturing those buttons — it consumes
them before Hammerspoon sees them.

## Measurements

macOS 27.0 (26A5388g), Apple silicon, single 2560x1440 display, 5 spaces
(4 desktops + 1 fullscreen). Identical harness for both paths, 3-second settle
before sampling.

```
LATENCY   daemon        n=16  min=51  max=66  avg=56 ms
          applescript   n=4   min=1111 max=1361 avg=1197 ms

ACCURACY  daemon        20 scored, 20 correct, 0 wrong, 0 discarded
```

Accuracy = every move landed exactly one space, both directions, with correct
no-op behaviour at both edges, including into and out of the fullscreen space.

### If you re-measure, read this first

**A space switch is not observable until it fully settles.** Sampling
`hs.spaces.focusedSpace()` sooner than ~3 s after a switch returns stale
mid-transition state, which looks exactly like overshoot ("it moved 2 spaces")
or a dropped move.

This produced a completely wrong conclusion during development — the daemon was
judged unreliable on the strength of it. The tell: the same short settle made
the *known-good* AppleScript path appear to skip spaces too. If your reference
path looks broken, suspect your measurement.

`GESTURE_SPEED` is momentum, not latency. Upstream's default of 2000 overshoots
by two spaces on the first move here; anything ≤1000 lands exactly one. Lowering
it does not make switching slower.

## Known limitations

- **Private, undocumented APIs on a beta OS.** CGEvent fields 55/110/123/124/
  129/130/132 and the serialized IOHID payload in field 4205 are all
  undocumented. Any macOS update can break this without warning.
- Verified on **one machine, one display**. Multi-monitor is untested.
- Depends on unmerged upstream work (InstantSpaceSwitcher PR #88 and the
  `macos-27` branch lineage). Prefer upstream once this lands there.
- Ships as **source only, deliberately.** An unsigned prebuilt binary asking for
  Accessibility is indistinguishable from malware to a careful user. Build it
  yourself and read `src/issd.c` — it is ~30 lines — before granting anything.

## Provenance and AI disclosure

The macOS 27 serialization approach is mgbowen's (FasterSwiper, Apache-2.0);
the space-switching core is jurplel's (InstantSpaceSwitcher, MIT); the C port of
the serializer is geesawra's. See [NOTICE](NOTICE).

Portions of this work — including the resident-daemon finding, the gesture sign
fix, and much of this repository — were written with AI assistance, as were
parts of the upstream work it builds on (both mgbowen and geesawra disclosed the
same). Review accordingly before granting it Accessibility.

## License

New code: MIT ([LICENSE](LICENSE)). Vendored sources retain their original
licenses: MIT ([LICENSE-MIT](LICENSE-MIT)) and Apache-2.0
([LICENSE-APACHE](LICENSE-APACHE)). See [NOTICE](NOTICE).
