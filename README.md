# instantswitch

Near-instant macOS Space switching, bound to your mouse's side buttons.

**~56 ms instead of ~1100 ms** on macOS 27.0 (26A5388g).

> Builds on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)
> and [FasterSwiper](https://github.com/mgbowen/FasterSwiper). See [NOTICE](NOTICE)
> for provenance, licensing, and the changes made here.

---

## Walkthrough

### 1. Build

Requires Xcode Command Line Tools. No Xcode or Swift needed — this is plain C.

```sh
git clone <your-fork-url> instantswitch
cd instantswitch
./build.sh ~/.hammerspoon/bin/spaced
```

That produces a single ~57 KB binary at `~/.hammerspoon/bin/spaced` and ad-hoc
signs it so it has a stable identity for the permission grant.

### 2. Grant it permission

`spaced` injects synthetic input, so macOS requires explicit permission. It does
**not** inherit Hammerspoon's — it needs its own grant.

1. **System Settings → Privacy & Security → Device Control and Data Access**
2. Click **+**
3. Press <kbd>⌘⇧G</kbd>, enter `~/.hammerspoon/bin/`, select **`spaced`**
4. Toggle it on

> On macOS 26 and earlier this pane is called **Accessibility**. macOS 27
> renamed it to *Device Control and Data Access*.

Two things about this grant, both of which cause silent failure:

- It is tied to the binary's **path and code hash**. Moving or rebuilding
  `spaced` invalidates it — remove and re-add the entry after any rebuild.
- Without it, `spaced` exits immediately with `iss_init failed` and your buttons
  simply do nothing.

### 3. Wire up the buttons

Copy [`hammerspoon/init.example.lua`](hammerspoon/init.example.lua) to
`~/.hammerspoon/init.lua`, or merge its space-switching section into your
existing config, then reload Hammerspoon.

Defaults: **button 3 → space left**, **button 4 → space right**. Both are
swallowed so apps don't also receive back/forward.

If your mouse reports different numbers, set `SPACE_BUTTON_DEBUG = true`,
reload, press the buttons, and read the numbers off the alert.

### 4. Check it works

Press a side button. The switch should be immediate with no slide animation.
If nothing happens, in order of likelihood:

| Symptom | Cause |
|---|---|
| Nothing at all | `spaced` not granted permission, or was rebuilt after granting |
| Nothing, only after a rebuild | Grant invalidated by the new code hash — remove and re-add |
| Buttons work but app also goes back/forward | Another mouse utility is also bound to those buttons |
| Nothing, and you use Mac Mouse Fix / BetterMouse | It is capturing the buttons before Hammerspoon sees them — unbind them there |

Run `~/.hammerspoon/bin/spaced` directly in a terminal to see errors: it prints
`ready` on success and `iss_init failed` when it lacks permission.

---

## Why this exists

macOS 27 broke every third-party way of changing Space. Measured, not assumed:

| Approach | Result |
|---|---|
| `hs.spaces.gotoSpace()` | Dead. Neither Dock nor WindowManager exposes the Mission Control accessibility tree (`mc`) anymore. |
| Synthetic `ctrl`+arrow via `hs.eventtap` | Ignored. The space-switch hotkey only accepts real HID events. |
| `CGSManagedDisplaySetCurrentSpace`, `CGSShowSpaces`/`CGSHideSpaces` | **Fake.** Bookkeeping only — `CGSGetActiveSpace` reports the new space, but the WindowServer never performs the transition. The on-screen window list is byte-identical before and after: you keep looking at the same windows. |
| System Events pressing `ctrl`+arrow | Works, ~1100 ms — and ~97% of that is animation, so there is nothing to optimise caller-side. |
| High-velocity synthetic Dock swipe | Works, and skips the animation. This is what we use. |

## Why a daemon

**The gesture is only acted on when posted from a long-lived process.**

This is the key finding, and the reason upstream's CLI fails on macOS 27 while
their menu-bar app works. A process that posts the events and exits — even with
a runloop pump — is silently ignored: the calls return success and nothing
happens. `spaced` therefore holds the event tap open and reads commands on
stdin (`left`, `right`, `speed <n>`, `reset`, `quit`), one per line.

## The prediction cache

ISS caches a per-display *predicted* space index after each switch and uses it
in place of the real index, so a rapid burst of presses does not race the
WindowServer. It never invalidates that cache.

That is fine while ISS causes every space change. It is not fine in practice:
macOS **auto-switches you into a newly created fullscreen space**, and you can
also click a desktop in Mission Control or press ctrl+arrow. After any of those
the cached index is wrong and `iss_should_block_switch()` refuses moves — it
thinks you are parked on an edge. Reproduced deterministically:

```
walked to left edge with the daemon   -> prediction = 0
moved right twice by another means    -> actually at index 2
asked the daemon to go left           -> returned 0, REFUSED, no move
```

The symptom is a side button that silently stops working — typically right
after you put something fullscreen — until you happen to move the other way,
which rewrites the prediction.

`issd.c` drops the cache when a press is more than `PREDICTION_TTL_MS` (600 ms)
after the previous one, or when the space count changed. The cache only ever
helps within a burst, so this costs nothing.

Also worth knowing: a new fullscreen space is **inserted next to the current
space**, not appended, so it shifts the indices of everything after it:

```
before: { 6, 8, 7, 9 }        active index 1
after:  { 6, 50, 8, 7, 9 }    active index 2   <- 50 inserted at position 2
```

## Measurements

macOS 27.0 (26A5388g), Apple silicon, single 2560x1440 display. Identical
harness for both paths, 3-second settle before sampling.

```
LATENCY   daemon        n=16  min=51  max=66  avg=56 ms
          applescript   n=4   min=1111 max=1361 avg=1197 ms

ACCURACY  daemon        20 scored, 20 correct, 0 wrong, 0 discarded
```

Accuracy = every move landed exactly one space, both directions, correct no-op
at both edges, including into and out of a fullscreen space.

### If you re-measure, read this first

**A space switch is not observable until it fully settles.** Sampling
`hs.spaces.focusedSpace()` sooner than ~3 s returns stale mid-transition state,
which looks exactly like overshoot ("it moved 2 spaces") or a dropped move.

This produced a completely wrong conclusion during development — the daemon was
judged unreliable on the strength of it. The tell: the same short settle made
the *known-good* AppleScript path appear to skip spaces too. If your reference
path looks broken, suspect your measurement.

`GESTURE_SPEED` is momentum, not latency. Upstream's default of 2000 overshoots
by two spaces on the first move here; anything ≤1000 lands exactly one. Lowering
it does not slow switching down.

## Known limitations

- **Private, undocumented APIs on a beta OS.** CGEvent fields 55/110/123/124/
  129/130/132 and the serialized IOHID payload in field 4205 are undocumented.
  Any macOS update can break this without warning.
- Verified on **one machine, one display**. Multi-monitor is untested.
- Depends on unmerged upstream work (InstantSpaceSwitcher PR #88 and the
  `macos-27` branch lineage). Prefer upstream once this lands there.
- **Source only, deliberately.** An unsigned prebuilt binary asking for input
  permission is indistinguishable from malware. Build it yourself and read
  `src/issd.c` — it is short — before granting it anything.

## Provenance and AI disclosure

The macOS 27 serialization approach is mgbowen's (FasterSwiper, Apache-2.0); the
space-switching core is jurplel's (InstantSpaceSwitcher, MIT); the C port of the
serializer is geesawra's. See [NOTICE](NOTICE).

Portions of this work — the resident-daemon finding, the gesture sign fix, the
prediction-cache fix, and much of this repository — were written with AI
assistance, as were parts of the upstream work it builds on (both mgbowen and
geesawra disclosed the same). Review accordingly before granting permission.

## License

New code: MIT ([LICENSE](LICENSE)). Vendored sources retain their original
licenses: MIT ([LICENSE-MIT](LICENSE-MIT)) and Apache-2.0
([LICENSE-APACHE](LICENSE-APACHE)). See [NOTICE](NOTICE).
