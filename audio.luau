local catalog = require("./catalog")
local M = {}
function M.stop(owner)
    tern.fs.write(tern.plugin.data .. "/audio-" .. owner, "stopped")
end
function M.play(owner, name, volume, report)
    local path = tern.plugin.data .. "/audio-" .. owner
    local token = tostring(tern.now()) .. name .. tostring(volume)
    tern.fs.write(path, token)
    if volume == 0 then return end
    if tern.runtime.os ~= "macos" then report("Bell requires macOS") return end
    local ok, err = pcall(function()
        tern.process.run({ "/usr/bin/python3", tern.plugin.dir .. "/play.py", path, token, catalog.paths[name], tostring(volume / 100) }, { timeout_ms = 12000 }, function(result)
            if result.status ~= 0 and tern.fs.read(path) == token then report("Playback failed: " .. result.stderr) end
        end)
    end)
    if not ok then report(tostring(err)) end
end
return M
