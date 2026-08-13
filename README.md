# instantswitch

Near-instant Space switching on macOS 27, bound to your mouse's side buttons.

Measured at about 56 ms, against about 1100 ms for the system's own
ctrl+arrow shortcut.

Built on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)
by jurplel and [FasterSwiper](https://github.com/mgbowen/FasterSwiper) by
mgbowen, plus geesawra's C port of the macOS 27 serializer. See
[NOTICE](NOTICE) for full provenance and licensing.

## Requirements

- macOS 27 (tested on 27.0, build 26A5388g)
- Xcode Command Line Tools. Xcode itself is not needed, and neither is Swift.
- A mouse with side buttons

## Setup

### 1. Build the app

```sh
git clone https://github.com/SanRive/instantswitch
cd instantswitch
./build-app.sh /Applications/InstantSwitch.app
```

Install it to `/Applications` before granting permission in step 3. The grant
is tied to the bundle's location, so granting first and moving it afterwards
silently breaks it.

### 2. Open it

```sh
open -a InstantSwitch
```

A menu bar icon appears. There is no Dock icon and no window: the menu bar item
is the whole interface, and it doubles as a reminder that the app is running.

At this point the menu reads "Needs permission" and the buttons do nothing.
That is expected.

### 3. Grant permission

The app injects synthetic input, so macOS requires explicit permission.

1. Open System Settings
2. Go to Privacy and Security, then Device Control and Data Access
3. Click the "+" button
4. Press Command-Shift-G, type `/Applications`, and select `InstantSwitch.app`
5. Turn its switch on

On macOS 26 and earlier this pane is called Accessibility. macOS 27 renamed it
to Device Control and Data Access.

### 4. Restart the app

The event tap is installed at launch, so the new permission does not take
effect until the app restarts.

Click the menu bar icon, choose "Quit InstantSwitch", then open it again from
Spotlight or Launchpad.

### 5. Confirm it works

Click the menu bar icon. It should now read "Active", and the icon should no
longer look dimmed.

Press your mouse's side buttons. Button 3 (back) moves one Space left, button 4
(forward) moves one Space right. The switch is immediate, with no slide
animation.

### 6. Start it automatically

Click the menu bar icon and turn on "Open at Login". It then appears under
System Settings, General, Login Items, where it can also be turned off.

## Using it

| Menu item | What it does |
| --- | --- |
| Active / Paused / Needs permission | Current state. The icon dims when not active. |
| Enabled | Pauses without quitting, for when another tool needs those buttons. |
| Open at Login | Registers or removes the login item. |
| Quit InstantSwitch | Exits. |

To use different buttons, change `kButtonBack` and `kButtonForward` in
[`src/app_main.m`](src/app_main.m) and rebuild. Rebuilding changes the app's
code hash, so you must remove and re-add it in System Settings afterwards.

### Other mouse utilities

Mac Mouse Fix, BetterMouse and similar tools install their own event taps.
Taps are chained, and whichever one comes first and consumes a button hides it
from everything after it. If one of them is bound to buttons 3 or 4, unbind
those buttons there. This is the only reliable fix, and not something this app
can work around.

InstantSwitch passes through every button it does not handle, so the rest of
your mappings are unaffected.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Nothing happens at all | Permission not granted, or granted before the app was moved or rebuilt. |
| Menu still says "Needs permission" after granting | The tap is installed at launch. Quit and reopen the app. |
| It worked, then stopped after a rebuild | Rebuilding changed the code hash and invalidated the grant. Remove and re-add the entry. |
| Buttons work, but apps also navigate back and forward | Another utility is bound to the same buttons. |
| One click jumps two Spaces | Two things are bound at once, for example this app and a Hammerspoon config. |

## Alternative: Hammerspoon

If you already run Hammerspoon and would rather not install an app, build the
daemon instead:

```sh
./build.sh ~/.hammerspoon/bin/spaced
```

Grant `spaced` permission the same way, then copy
[`hammerspoon/init.example.lua`](hammerspoon/init.example.lua) to
`~/.hammerspoon/init.lua`, or merge its space-switching section into your own
config.

The daemon reads `left`, `right`, `speed <n>`, `reset` and `quit` on stdin, one
per line. Do not run this and the app at the same time, as both will fire.

## How it works

### Why this is needed

macOS 27 broke every third-party way of changing Space. Measured, not assumed:

| Approach | Result |
| --- | --- |
| `hs.spaces.gotoSpace()` | Dead. Neither Dock nor WindowManager exposes the Mission Control accessibility tree (`mc`) any more. |
| Synthetic ctrl+arrow via an event tap | Ignored. The space-switch hotkey only accepts real HID events. |
| `CGSManagedDisplaySetCurrentSpace`, `CGSShowSpaces` / `CGSHideSpaces` | Bookkeeping only. `CGSGetActiveSpace` reports the new Space, but the WindowServer never performs the transition. The on-screen window list is identical before and after, so you keep looking at the same windows. |
| System Events pressing ctrl+arrow | Works, but takes about 1100 ms, roughly 97% of which is animation. |
| High-velocity synthetic Dock swipe | Works, and skips the animation. This is what the app uses. |

### Why a resident process

The Dock only acts on the synthetic gesture when it is posted from a long-lived
process. A process that posts the events and exits is silently ignored: the
calls return success and nothing happens.

This is why upstream's command line tool does nothing on macOS 27 while their
menu bar app works. Both the app and the daemon hold the event tap open for
their lifetime.

### The prediction cache

InstantSpaceSwitcher caches a predicted Space index after each switch and uses
it instead of the real index, so that a rapid burst of presses does not race the
WindowServer. It never invalidates that cache.

That is fine while it causes every Space change itself. It is not fine in
practice: macOS moves you into a newly created fullscreen Space automatically,
and you can also click a desktop in Mission Control or press ctrl+arrow. After
any of those the cached index is wrong, and the edge check refuses moves because
it believes you are parked at the end of the list. Reproduced deterministically:

```
walked to the left edge with the daemon   ->  prediction = 0
moved right twice by other means          ->  actually at index 2
asked the daemon to move left             ->  returned 0, refused, no move
```

The symptom is a side button that quietly stops working, usually right after
you put something fullscreen, until you happen to move the other way and
rewrite the prediction.

[`src/predictions.c`](src/predictions.c) drops the cache when a press is more
than 600 ms after the previous one, or when the number of Spaces changed. The
cache only ever helps within a burst, so this costs nothing.

A new fullscreen Space is also inserted next to the current one rather than
appended, which shifts the index of everything after it:

```
before:  { 6, 8, 7, 9 }        active index 1
after:   { 6, 50, 8, 7, 9 }    active index 2      50 inserted at position 2
```

## Measurements

macOS 27.0 (26A5388g), Apple silicon, single 2560x1440 display. Identical
harness for both paths, with a 3 second settle before sampling.

```
Latency    gesture      n=16   min=51    max=66    avg=56 ms
           ctrl+arrow   n=4    min=1111  max=1361  avg=1197 ms

Accuracy   gesture      20 scored, 20 correct, 0 wrong, 0 discarded
```

Accuracy means every move landed exactly one Space, in both directions, with
correct no-op behaviour at both edges, including moving into and out of a
fullscreen Space.

### If you re-measure this

A Space switch is not observable until it has fully settled. Sampling the active
Space sooner than about 3 seconds returns stale mid-transition state, which
looks exactly like overshoot or a dropped move.

This produced a completely wrong conclusion during development, and the gesture
approach was briefly judged unreliable because of it. The giveaway was that the
same short settle made the known-good ctrl+arrow path appear to skip Spaces too.
If your reference path looks broken, suspect the measurement first.

Gesture velocity is momentum, not latency. Upstream's default of 2000 overshoots
by two Spaces on the first move on this hardware, while anything at or below
1000 lands exactly one. Lowering it does not make switching slower.

## Limitations

- This relies on private, undocumented APIs on a beta OS. CGEvent fields 55,
  110, 123, 124, 129, 130 and 132, and the serialized IOHID payload in field
  4205, are all undocumented. Any macOS update can break it without warning.
- Verified on one machine with one display. Multi-monitor is untested.
- It depends on unmerged upstream work (InstantSpaceSwitcher PR #88 and the
  `macos-27` branch lineage). Prefer upstream once this lands there.
- Source only, deliberately. An unsigned prebuilt binary that asks for input
  permission is indistinguishable from malware. Build it yourself, and read
  [`src/app_main.m`](src/app_main.m) first. It is short.

## Credits and AI disclosure

The macOS 27 serialization approach is mgbowen's, in FasterSwiper (Apache-2.0),
and is the reason any of this works on macOS 27. The space-switching core is
jurplel's, in InstantSpaceSwitcher (MIT). The C port of the serializer is
geesawra's. See [NOTICE](NOTICE).

Parts of this work, including the resident-process finding, the gesture sign
fix, the prediction cache fix and the app itself, were written with AI
assistance, as were parts of the upstream work it builds on. Both mgbowen and
geesawra disclosed the same. Review the code before granting it permission.

## License

New code is MIT ([LICENSE](LICENSE)). Vendored sources keep their original
licenses: MIT ([LICENSE-MIT](LICENSE-MIT)) and Apache-2.0
([LICENSE-APACHE](LICENSE-APACHE)). See [NOTICE](NOTICE).
