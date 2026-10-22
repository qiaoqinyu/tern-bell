local M = { sounds = {}, paths = {}, custom = {} }
for _, name in { "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink" } do
    table.insert(M.sounds, name)
    M.paths[name] = "/System/Library/Sounds/" .. name .. ".aiff"
end
-- Custom sounds are user-supplied: the package ships none. Drop audio
-- files (.wav .aiff .mp3 .m4a .caf) into <plugin-data>/bell/sounds/custom/
-- and they appear in the list by file name, after the built-ins.
local custom = tern.plugin.data .. "/sounds/custom"
if tern.fs.exists(custom) then
    local playable = { wav = true, aiff = true, mp3 = true, m4a = true, caf = true }
    local files = tern.fs.list(custom)
    table.sort(files)
    for _, file in files do
        local stem, ext = string.match(file, "^(.-)%.(%w+)$")
        if stem and #stem > 0 and playable[ext:lower()] then
            if not M.paths[stem] then table.insert(M.sounds, stem) end
            M.paths[stem] = custom .. "/" .. file
            M.custom[stem] = true
        end
    end
end
function M.load()
    local cfg = tern.kv.get("settings")
    if type(cfg) ~= "table" then
        cfg = { enabled = tern.kv.get("enabled") ~= false, sound = tern.kv.get("sound"), volume = tern.kv.get("volume") }
    end
    return {
        enabled = cfg.enabled ~= false,
        sound = if type(cfg.sound) == "string" and cfg.sound ~= "" then cfg.sound else "Glass",
        failureSound = if type(cfg.failureSound) == "string" and cfg.failureSound ~= "" then cfg.failureSound else "Basso",
        volume = if type(cfg.volume) == "number" then math.clamp(cfg.volume, 0, 100) else 50,
    }
end
return M
