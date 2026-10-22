local audio = require("./audio")
local reportedErrors = {}
local previousStates = {}
local waits = {}
local pollingError = nil
local function notify(failed, cx, complete)
    audio.notify(failed, function(err, freshCx, retrySettings)
        if not err then
            reportedErrors = {}
        elseif not reportedErrors[err] then
            reportedErrors[err] = true
            tern.log.error(err)
            local targetCx = freshCx or cx
            targetCx:toast("error", "Bell could not play a sound", err)
        end
        if complete then complete(retrySettings == true) end
    end)
end
local function poll_waiting(cx)
    -- A timer is one-shot. Schedule first so a transient failure cannot end the chain.
    tern.timer(750, poll_waiting)
    local ok, err = pcall(function()
        local current = {}
        for _, agent in cx.agents:list() do
            local before = previousStates[agent.pane]
            current[agent.pane] = agent.state
            -- First observations (including after reload/reconnect) stay silent.
            if before and before ~= "waiting_input" and agent.state == "waiting_input" then
                waits[agent.pane] = { pending = true, inFlight = false }
            elseif agent.state ~= "waiting_input" then
                waits[agent.pane] = nil
            end
            local wait = waits[agent.pane]
            if wait and wait.pending and not wait.inFlight then
                wait.inFlight = true
                notify(false, cx, function(retrySettings)
                    if waits[agent.pane] == wait then
                        wait.inFlight = false
                        wait.pending = retrySettings
                    end
                end)
            end
            previousStates[agent.pane] = agent.state
        end
        previousStates = current
        for pane in waits do
            if current[pane] ~= "waiting_input" then waits[pane] = nil end
        end
    end)
    if ok then
        pollingError = nil
    elseif pollingError ~= tostring(err) then
        pollingError = tostring(err)
        tern.log.error(pollingError)
        cx:toast("error", "Bell input reminders temporarily unavailable", pollingError)
    end
end
-- window_start is not re-fired on hot reload; each new VM starts its own chain.
tern.timer(0, poll_waiting)
tern.on("agent_finished", function(ev, cx)
    if ev.result ~= "done" and ev.result ~= "failed" then return end
    notify(ev.result == "failed", cx)
end)
tern.command({ id = "settings", title = "Bell: Settings", run = function(cx)
    cx:new_block("bell.settings", {}, "tab")
end })
