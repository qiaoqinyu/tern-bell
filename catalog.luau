local M = { sounds = {}, paths = {} }
for _, name in { "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink" } do
    table.insert(M.sounds, name)
    M.paths[name] = "/System/Library/Sounds/" .. name .. ".aiff"
end
-- CS 1.6 clips are user-supplied: the package ships none. Drop `.wav`
-- files into <plugin-data>/bell/sounds/cs16/ and they appear here.
local clips = if tern.fs.exists(tern.plugin.data .. "/sounds/cs16") then tern.fs.list(tern.plugin.data .. "/sounds/cs16") else {}
table.sort(clips)
for _, file in clips do
    local clip = string.match(file, "^(.-)%.wav$")
    if clip and #clip > 0 then
        local name = "CS16_" .. clip
        table.insert(M.sounds, name)
        M.paths[name] = tern.plugin.data .. "/sounds/cs16/" .. file
    end
end
function M.load()
    local cfg = tern.kv.get("settings")
    if type(cfg) ~= "table" then
        cfg = { enabled = tern.kv.get("enabled") ~= false, sound = tern.kv.get("sound"), volume = tern.kv.get("volume") }
    end
    return { enabled = cfg.enabled ~= false, sound = if cfg.sound and M.paths[cfg.sound] then cfg.sound else "Glass", volume = if type(cfg.volume) == "number" then math.clamp(cfg.volume, 0, 100) else 50 }
end
return M
