# instantswitch

Near-instant macOS Space switching, bound to your mouse's side buttons.

**~56 ms instead of ~1100 ms** on macOS 27.0 (26A5388g), where every other
third-party way of changing Space is broken.

> Builds on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)
> by jurplel and [FasterSwiper](https://github.com/mgbowen/FasterSwiper) by
> mgbowen, plus geesawra's C port of the macOS 27 serializer. See
> [NOTICE](NOTICE) for full provenance and licensing.

---

## Install

Requires Xcode Command Line Tools. No Xcode and no Swift — this is plain
C/Objective-C.

```sh
git clone https://github.com/SanRive/instantswitch
cd instantswitch
./build-app.sh /Applications/InstantSwitch.app
open -a InstantSwitch
```

A menu bar icon appears immediately — that is your reminder it is running.
Until you grant permission it reads **"⚠︎ Needs permission"**.

### Grant permission

**System Settings → Privacy & Security → Device Control and Data Access** →
**+** → select `/Applications/InstantSwitch.app` → toggle on → **quit and
reopen the app** (the event tap is installed at launch).

> On macOS 26 and earlier this pane is called **Accessibility**. macOS 27
> renamed it to *Device Control and Data Access*.

Two things about this grant, both of which fail silently:

- It is tied to the bundle's **path and code hash**. Moving or rebuilding the
  app invalidates it — install to `/Applications` *before* granting, so you only
  do this once, and remove/re-add the entry after any rebuild.
- Without it, the app runs but can switch nothing.

### Use it

Default bindings: **button 3 → space left**, **button 4 → space right**. Both
are swallowed so apps do not also navigate back/forward.

Click the menu bar icon for state, an enable/pause toggle, and **Open at Login**.

| Menu item | Meaning |
|---|---|
| Active / Paused / ⚠︎ Needs permission | Current state; the icon dims when not active |
| Enabled | Pause without quitting — for when another mouse tool needs those buttons |
| Open at Login | Registers the login item via `SMAppService` |

To change the buttons, edit `kButtonBack` / `kButtonForward` in
[`src/app_main.m`](src/app_main.m) and rebuild (then re-grant).

### Coexisting with Mac Mouse Fix / BetterMouse

Event taps are chained: whichever one sits earlier and *consumes* a button hides
it from everything downstream. If another tool is bound to buttons 3/4, unbind
them there — that is the only reliable fix, not something this app can work
around. InstantSwitch passes through every button it does not handle, so the
rest of your mappings are unaffected.

### Troubleshooting

| Symptom | Cause |
|---|---|
| Nothing happens | Not granted, or granted before the app was moved/rebuilt |
| Menu says "Needs permission" after granting | Grant applies at launch — quit and reopen |
| Buttons work but the app also goes back/forward | Another utility is also bound to those buttons |
| One click jumps two spaces | Two things are bound at once (e.g. the app *and* a Hammerspoon config) |

---

## Alternative: Hammerspoon

If you already run Hammerspoon and would rather not add an app, build the
daemon instead and drive it from your config:

```sh
./build.sh ~/.hammerspoon/bin/spaced
```

Grant `spaced` permission the same way, then copy
[`hammerspoon/init.example.lua`](hammerspoon/init.example.lua) into
`~/.hammerspoon/init.lua` or merge its space-switching section into your own.
The daemon reads `left`, `right`, `speed <n>`, `reset` and `quit` on stdin, one
per line. Do not run both this and the app — they will both fire.

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

## Why a resident process

**The gesture is only acted on when posted from a long-lived process.**

This is the key finding, and it explains why upstream's CLI does nothing on
macOS 27 while their menu-bar app works. A process that posts the events and
exits — even with a runloop pump — is silently ignored: the calls return success
and nothing happens. Both the app and `spaced` therefore hold the event tap open
for their lifetime.

## The prediction cache

ISS caches a per-display *predicted* space index after each switch and uses it
in place of the real index, so a rapid burst of presses does not race the
WindowServer. It never invalidates that cache.

That is fine while ISS causes every space change. It is not fine in practice:
macOS **auto-switches you into a newly created fullscreen space**, and you can
also click a desktop in Mission Control or press ctrl+arrow. After any of those
the cached index is wrong and `iss_should_block_switch()` refuses moves — it
believes you are parked on an edge. Reproduced deterministically:

```
walked to left edge with the daemon   -> prediction = 0
moved right twice by another means    -> actually at index 2
asked the daemon to go left           -> returned 0, REFUSED, no move
```

The symptom is a side button that silently stops working — typically right
after you put something fullscreen — until you happen to move the other way,
which rewrites the prediction.

[`src/predictions.c`](src/predictions.c) drops the cache when a press is more
than 600 ms after the previous one, or when the space count changed. The cache
only ever helps within a burst, so this costs nothing.

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
LATENCY   gesture       n=16  min=51   max=66   avg=56 ms
          ctrl+arrow    n=4   min=1111 max=1361 avg=1197 ms

ACCURACY  gesture       20 scored, 20 correct, 0 wrong, 0 discarded
```

Accuracy = every move landed exactly one space, both directions, correct no-op
at both edges, including into and out of a fullscreen space.

### If you re-measure, read this first

**A space switch is not observable until it fully settles.** Sampling the active
space sooner than ~3 s returns stale mid-transition state, which looks exactly
like overshoot ("it moved 2 spaces") or a dropped move.

This produced a completely wrong conclusion during development — the gesture
approach was judged unreliable on the strength of it. The tell: the same short
settle made the *known-good* ctrl+arrow path appear to skip spaces too. If your
reference path looks broken, suspect your measurement.

Gesture velocity is momentum, not latency. Upstream's default of 2000 overshoots
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
  [`src/app_main.m`](src/app_main.m) and [`src/issd.c`](src/issd.c) — both are
  short — before granting anything.

## Provenance and AI disclosure

The macOS 27 serialization approach is mgbowen's (FasterSwiper, Apache-2.0); the
space-switching core is jurplel's (InstantSpaceSwitcher, MIT); the C port of the
serializer is geesawra's. See [NOTICE](NOTICE).

Portions of this work — the resident-process finding, the gesture sign fix, the
prediction-cache fix, the app, and much of this repository — were written with AI
assistance, as were parts of the upstream work it builds on (both mgbowen and
geesawra disclosed the same). Review accordingly before granting permission.

## License

New code: MIT ([LICENSE](LICENSE)). Vendored sources retain their original
licenses: MIT ([LICENSE-MIT](LICENSE-MIT)) and Apache-2.0
([LICENSE-APACHE](LICENSE-APACHE)). See [NOTICE](NOTICE).
