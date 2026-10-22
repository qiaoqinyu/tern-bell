-- Exercises the real window state machine with controllable async player results.
return function(load_window)
    local results = {}
    local function equal(actual, expected, message)
        assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
    local function fixture(initial)
        local f = { agents = initial or {}, timers = {}, events = {}, sounds = {}, toasts = {}, callbacks = {}, broken = false, listBroken = false, calls = 0 }
        local cx = {
            agents = { list = function()
                if f.listBroken then error("agent snapshot unavailable", 0) end
                return f.agents
            end },
            toast = function(_, _, title, detail) table.insert(f.toasts, { title = title, detail = detail }) end,
        }
        local api = {
            timer = function(_, callback) table.insert(f.timers, callback) end,
            on = function(name, callback) f.events[name] = callback end,
            command = function() end,
            log = { error = function() end },
        }
        local modules = {
            ["./audio"] = { notify = function(_, report)
                f.calls += 1
                if f.deferred then
                    table.insert(f.callbacks, report)
                elseif f.broken or f.calls == f.failLoadAt then
                    report("settings JSON unreadable", cx, true)
                else
                    table.insert(f.sounds, true)
                    report(nil, cx, false)
                end
            end },
        }
        local function load(first)
            f.timers, f.events = {}, {}
            load_window(api, function(name) return assert(modules[name], name) end)
            if first and f.events.window_start then f.events.window_start(cx) end
        end
        function f.tick()
            local next = table.remove(f.timers, 1)
            assert(next, "waiting observer stopped: no scheduled poll")
            next(cx)
        end
        function f.resolve(retry)
            local callback = table.remove(f.callbacks, 1)
            assert(callback, "no pending playback")
            callback(if retry then "settings JSON unreadable" else nil, cx, retry == true)
        end
        function f.reload() load(false) end
        function f.state(state) f.agents = { { pane = 7, state = state } } end
        function f.finish(result) f.events.agent_finished({pane = 7, result = result}, cx) end
        load(true)
        return f
    end
    local function test(name, body)
        local ok, err = pcall(body)
        table.insert(results, { name = name, passed = ok, error = if ok then "" else tostring(err) })
    end
    test("hot reload restarts input reminders without replaying an existing wait", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.tick() f.reload() f.state("waiting_input") f.tick()
        equal(#f.sounds, 0, "reload baseline must stay silent")
        f.state("working") f.tick() f.state("waiting_input") f.tick()
        equal(#f.sounds, 1, "new wait after reload must ring")
    end)
    test("settings read failure recovers without another reload", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.tick() f.broken = true f.state("waiting_input") f.tick()
        f.broken = false f.tick()
        equal(#f.sounds, 1, "still-pending wait must ring after settings recover")
        f.tick()
        equal(#f.sounds, 1, "recovery must not repeat a wait reminder")
    end)
    test("sustained settings failure gives one visible error and no sound", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.tick() f.broken = true f.state("waiting_input")
        for _ = 1, 4 do f.tick() end
        equal(#f.sounds, 0, "invalid settings cannot trigger playback")
        equal(#f.toasts, 1, "same failure must be visible once")
        f.broken = false f.tick() f.state("working") f.tick()
        f.broken = true f.state("waiting_input") f.tick()
        equal(#f.toasts, 2, "new failure after recovery must be visible")
    end)
    test("agent snapshot failure preserves pending state and recovers", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.tick() f.listBroken = true f.tick()
        f.listBroken = false f.state("waiting_input") f.tick()
        equal(#f.sounds, 1, "snapshot recovery must resume waiting detection")
    end)
    test("a second pane's settings failure does not replay the first pane", function()
        local f = fixture({ { pane = 7, state = "working" }, { pane = 8, state = "working" } })
        f.tick() f.failLoadAt = 2
        f.agents = { { pane = 7, state = "waiting_input" }, { pane = 8, state = "waiting_input" } }
        f.tick()
        equal(#f.sounds, 1, "first pane was handled before second settings read failed")
        f.tick()
        equal(#f.sounds, 2, "recovery must ring only the pending pane")
        f.tick()
        equal(#f.sounds, 2, "both waits must now stay silent")
    end)
    test("idle and ongoing tool work stay silent; each new wait rings once", function()
        local f = fixture({ { pane = 7, state = "idle" } })
        f.tick() f.tick() f.state("working") f.tick() f.tick()
        equal(#f.sounds, 0, "idle and work must stay silent")
        f.state("waiting_input") f.tick() f.tick() f.tick()
        equal(#f.sounds, 1, "sustained wait must ring once")
        f.state("working") f.tick() f.state("waiting_input") f.tick()
        equal(#f.sounds, 2, "a later wait must ring again")
        f.state("idle") f.tick()
        equal(#f.sounds, 2, "idle is not a new waiting request")
    end)
    test("completion and failure survive reload; close and exit stay silent", function()
        local f = fixture()
        f.reload() f.finish("done") f.finish("failed") f.finish("exited") f.finish("closed")
        equal(#f.sounds, 2, "only done and failed are notifications")
    end)
    test("a slow player does not duplicate a sustained waiting notification", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.deferred = true f.tick() f.state("waiting_input") f.tick() f.tick() f.tick()
        equal(f.calls, 1, "only one request may be in flight per wait")
        f.resolve() f.tick() f.tick()
        equal(f.calls, 1, "successful wait must not be replayed")
    end)
    test("a stale settings failure cannot revive an earlier wait", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.deferred = true f.tick() f.state("waiting_input") f.tick()
        f.state("working") f.tick() f.state("waiting_input") f.tick()
        equal(f.calls, 2, "each distinct wait starts one request")
        f.resolve(true) f.tick()
        equal(f.calls, 2, "old failure must not change the new in-flight wait")
        f.resolve() f.tick()
        equal(f.calls, 2, "new wait completed once")
    end)
    test("a removed pane cannot leave a retrying notification behind", function()
        local f = fixture({ { pane = 7, state = "working" } })
        f.deferred = true f.tick() f.state("waiting_input") f.tick()
        f.agents = {} f.tick() f.resolve(true) f.tick()
        equal(f.calls, 1, "removed pane must not retry")
        f.state("waiting_input") f.tick()
        equal(f.calls, 1, "reappearing pane establishes a silent baseline")
    end)
    return results
end
