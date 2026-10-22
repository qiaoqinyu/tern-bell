local M = {}
function M.notify(failed, report)
    if tern.runtime.os ~= "macos" then report("Bell requires macOS") return end
    local ok, err = pcall(function()
        tern.process.run({ "/usr/bin/python3", tern.plugin.dir .. "/notify.py", tern.plugin.data, if failed then "failed" else "done" }, { timeout_ms = 12000 }, function(result, cx)
            if result.status == 0 then
                report(nil, cx, false)
            else
                local detail = if result.stderr ~= "" then result.stderr else "Notification player exited " .. tostring(result.status)
                report(detail, cx, result.status == 2)
            end
        end)
    end)
    if not ok then report(tostring(err)) end
end
function M.stop(owner)
    tern.fs.write(tern.plugin.data .. "/audio-" .. owner, "stopped")
end
function M.play(owner, name, volume, report)
    local catalog = require("./catalog")
    local path = tern.plugin.data .. "/audio-" .. owner
    local token = tostring(tern.now()) .. name .. tostring(volume)
    local ok, err = pcall(function()
        tern.fs.write(path, token)
        if volume == 0 then return end
        if tern.runtime.os ~= "macos" then report("Bell requires macOS") return end
        local sound = catalog.paths[name]
        if not sound or not tern.fs.exists(sound) then
            report("Sound unavailable: " .. name .. ". Restore the file or choose another sound in Bell: Settings.")
            return
        end
        tern.process.run({ "/usr/bin/python3", tern.plugin.dir .. "/play.py", path, token, sound, tostring(volume / 100) }, { timeout_ms = 12000 }, function(result, cx)
            if not tern.fs.exists(path) or tern.fs.read(path) ~= token then return end
            if result.status ~= 0 then
                report("Could not play " .. name .. ": " .. result.stderr, cx)
            else
                report(nil, cx)
            end
        end)
    end)
    if not ok then report(tostring(err)) end
end
return M
