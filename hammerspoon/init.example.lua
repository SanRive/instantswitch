-- ============================================================
--  Space switching (macOS 27)
-- ============================================================
-- macOS 27 broke every third-party way of changing Space:
--   * hs.spaces.gotoSpace() -- dead. Neither the Dock nor WindowManager
--     exposes the Mission Control accessibility tree ("mc" group) anymore.
--   * synthetic ctrl+arrow via hs.eventtap -- ignored by the space-switch
--     hotkey; only "real" HID events are accepted.
--   * CGSManagedDisplaySetCurrentSpace / CGSShowSpaces+CGSHideSpaces --
--     these update bookkeeping ONLY. CGSGetActiveSpace reports the new
--     space but the WindowServer never performs the transition, so the
--     on-screen window list is identical before and after and you keep
--     looking at the same windows. Looks instant; nothing moved.
--
-- SWITCH_METHOD below picks the mechanism. Default is "daemon".
--
-- Measured head-to-head on this machine, identical harness, 3s settles:
--   daemon      56, 56, 51, 60 ms        (avg 56 ms)
--   applescript 1201, 1361, 1111, 1116   (avg 1197 ms)
-- Accuracy: 10/10 moves landed exactly one space, both directions, with
-- correct no-op behaviour at both edges.
--
-- "daemon" (~56ms):
--   Synthesises a high-velocity Dock swipe gesture, which makes macOS skip
--   the transition animation. On macOS 27 this needs a serialized IOHID
--   payload spliced into the CGEvent (field 4205) -- see InstantSpaceSwitcher
--   issue #72. Built from geesawra's port:
--     see NOTICE for provenance and licensing
--     source: vendored in this repo under src/
--
--   CRITICAL: the gesture only works from a RESIDENT process. Posting the
--   events and exiting does nothing -- the Dock never acts on them. That is
--   why this is a long-lived daemon reading commands on stdin rather than a
--   one-shot CLI, and it is why the upstream CLI fails where the menu-bar
--   app succeeds.
--
--   CRITICAL: the binary lives at bin/spaced because THAT PATH holds the
--   Accessibility grant. Do not rename it -- the grant is tied to path + code hash, so
--   renaming or rebuilding invalidates it and switching silently stops.
--
--   NOTE: geesawra's port inverts the gesture sign for macOS 27, which on
--   this machine made the gesture move opposite to ISS's internal direction
--   model -- so its edge check guarded the wrong side and both directions
--   failed at the leftmost space. The sign inversion is removed in our build.
--
--   MEASUREMENT WARNING: a space switch is not observable until it fully
--   settles. Sampling hs.spaces.focusedSpace() sooner than ~3s after a
--   switch returns stale mid-transition state, which looks exactly like
--   overshoot ("moved 2 spaces") or a dropped move. An earlier run of this
--   config was wrongly judged unreliable for this reason -- the same short
--   settle made the known-good applescript path look like it skipped spaces
--   too. If you re-measure, use a 3s settle before reading the space.
--
-- "applescript" (slow, ~1100ms, no permissions beyond Automation):
--   Asks System Events to press the real ctrl+arrow hotkey. Reliable
--   fallback. Needs Hammerspoon authorised under System Settings >
--   Privacy & Security > Automation > Hammerspoon > System Events.
--   Measured: the AppleScript call costs ~30ms; the rest is animation.
--
-- tools/spacejump.m (build separately) is a DIAGNOSTIC only: run it with no
-- arguments to list every space and its type. Do not use it to switch.

local SWITCH_METHOD = "daemon"   -- "daemon" | "applescript"

-- Path to the binary built by ./build.sh. The Accessibility grant is tied
-- to this exact path AND its code hash, so pick a stable location and do
-- not rename or rebuild it without re-granting.
local SPACE_DAEMON = os.getenv("HOME") .. "/.hammerspoon/bin/spaced"

-- Gesture velocity. Upstream defaults to 2000, which on this machine
-- overshoots by two spaces on the first move (measured: r:+2). Anything
-- <= 1000 lands exactly one space every time; 500 leaves margin. Lower
-- values do not make the switch slower -- this is momentum, not latency.
local GESTURE_SPEED = 500

-- Direction is handled in the daemon itself (ISS.c sign fix), not here.
local DAEMON_COMMAND = { left = "left", right = "right" }

if spaceDaemon then
    spaceDaemon:terminate()
    spaceDaemon = nil
end

-- Killing Hammerspoon orphans the daemon (its stdin pipe is not always closed
-- cleanly), so instances accumulate across restarts. Reap any strays before
-- starting a fresh one -- this runs before the new daemon is spawned.
hs.execute("/usr/bin/pkill -f '[.]hammerspoon/bin/spaced' 2>/dev/null")

local function ensureDaemon()
    -- Idempotent: a live handle means ours is already spawned. Testing
    -- isRunning() here instead would spawn a duplicate when called during
    -- the window between start() and the task actually running.
    if spaceDaemon then
        return true
    end
    spaceDaemon = hs.task.new(SPACE_DAEMON, function(rc, _, se)
        -- Exited. Next switch will start a fresh one.
        if rc ~= 0 then print("space daemon exited rc=" .. tostring(rc) .. " " .. tostring(se)) end
        spaceDaemon = nil
    end, function() return true end)
    if not spaceDaemon:start() then
        spaceDaemon = nil
        hs.alert.show("Space daemon failed to start.\nCheck bin/spaced exists.")
        return false
    end
    spaceDaemon:setInput("speed " .. GESTURE_SPEED .. "\n")
    return true
end

local function switchSpace(direction) -- "left" | "right"
    if SWITCH_METHOD == "daemon" then
        if not ensureDaemon() then return end
        spaceDaemon:setInput(DAEMON_COMMAND[direction] .. "\n")
        return
    end
    local keyCode = (direction == "right") and "124" or "123"
    -- Run in-process (not via /usr/bin/osascript) so TCC attributes the
    -- Automation request to Hammerspoon itself. Deferred to the next tick
    -- so the mouse event tap can return immediately.
    hs.timer.doAfter(0, function()
        local ok, _, raw = hs.osascript.applescript(
            'tell application "System Events" to key code ' ..
            keyCode .. ' using control down')
        if not ok then
            hs.alert.show("Space switch blocked -- grant Hammerspoon\n" ..
                          "Automation access to System Events")
            print("switchSpace failed:", hs.inspect(raw))
        end
    end)
end

if SWITCH_METHOD == "daemon" then ensureDaemon() end

-- ---- mouse side buttons -------------------------------------
-- Button 3 = "back" (-> left space), button 4 = "forward" (-> right space).
-- Mac Mouse Fix must NOT be capturing these buttons, or it eats them first.
-- If your mouse reports different numbers, set SPACE_BUTTON_DEBUG = true,
-- reload, press the buttons, and read the numbers off the alert/console.

local SPACE_BUTTON_DEBUG = false

local BUTTON_ACTIONS = {
    [3] = "left",
    [4] = "right",
}

if mouseListener then
    mouseListener:stop()
    mouseListener = nil
end

mouseListener = hs.eventtap.new(
    { hs.eventtap.event.types.otherMouseDown },
    function(e)
        local button = e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
        if SPACE_BUTTON_DEBUG then
            hs.alert.show("mouse button " .. tostring(button))
            print("mouse button:", button)
        end
        local direction = BUTTON_ACTIONS[button]
        if direction then
            switchSpace(direction)
            return true -- swallow it so apps don't also go back/forward
        end
        return false
    end
)
mouseListener:start()

-- ---- optional keyboard fallback ------------------------------
-- Your physical ctrl+left / ctrl+right should still work natively.
-- Only uncomment these if they don't -- otherwise they'd double-fire.
--
-- hs.hotkey.bind({ "ctrl" }, "left",  function() switchSpace("left")  end)
-- hs.hotkey.bind({ "ctrl" }, "right", function() switchSpace("right") end)

-- ============================================================
--  Your own macros go here
-- ============================================================
-- (This example ships only the space-switching half.)

-- Restart listeners after sleep/wake
if wakeWatcher then
    wakeWatcher:stop()
    wakeWatcher = nil
end

wakeWatcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        hs.timer.doAfter(2, function()
            if mouseListener then
                mouseListener:stop()
                mouseListener:start()
            end
            -- The daemon's event tap does not always survive sleep.
            if spaceDaemon then
                spaceDaemon:terminate()
                spaceDaemon = nil
            end
            if SWITCH_METHOD == "daemon" then ensureDaemon() end
        end)
    end
end)
wakeWatcher:start()

hs.alert.show("Space switching loaded")
