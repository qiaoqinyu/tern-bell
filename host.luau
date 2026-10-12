local catalog = require("./catalog")
local audio = require("./audio")
local ui = tern.ui
local panels = {}
local function preview(s, cx)
    audio.play(tostring(cx.pane), catalog.sounds[s.index], s.volume, function(err)
        s.error = err
        cx:render()
    end)
end
local function finish(s, cx, save)
    if save then
        tern.kv.set("settings", { enabled = s.enabled, sound = catalog.sounds[s.index], volume = s.volume })
    end
    audio.stop(tostring(cx.pane))
    panels[cx.pane] = nil
    cx:exit(0)
end
local function action(s, cx, act)
    if act == "save" then finish(s, cx, true)
    elseif act == "cancel" then finish(s, cx, false)
    elseif act == "preview" then preview(s, cx)
    elseif act == "toggle" then s.enabled = not s.enabled
    elseif act == "quieter" or act == "louder" then
        s.volume = math.clamp(s.volume + (if act == "quieter" then -10 else 10), 0, 100)
        preview(s, cx)
    end
end
tern.block.define("settings", {
    init = function(cx)
        local s = catalog.load()
        s.index = table.find(catalog.sounds, s.sound) or 6
        panels[cx.pane] = true
        return s
    end,
    title = function() return "Bell settings" end,
    view = function(s, cx)
        local rows = {}
        for i, name in catalog.sounds do
            table.insert(rows, ui.node("item", { key = tostring(i), label = name, detail = if string.sub(name, 1, 5) == "CS16_" then "CS 1.6" else "macOS" }))
        end
        local function button(text, act)
            return ui.el("button", { text = text, actions = { click = act } })
        end
        return { main = ui.col({
            ui.text("Bell settings · Changes are saved only with Enter or Save"),
            ui.row({ button(if s.enabled then "Enabled · toggle" else "Disabled · toggle", "toggle"), button("−10%", "quieter"), ui.text(tostring(s.volume) .. "%"), button("+10%", "louder"), button("Preview", "preview") }),
            ui.node("list", { key = "sounds", selected = "main.sounds." .. s.index, max = { lines = math.max(3, math.min(14, cx.rows - 10)) } }, rows),
            ui.text(s.error or "↑↓ select and preview · ←→ volume · Space toggle · Enter save · Esc cancel"),
        }), dock = ui.row({ button("Save", "save"), button("Cancel", "cancel") }) }
    end,
    key = function(s, key, cx)
        if key.name == "up" or key.name == "down" then
            s.index = math.clamp(s.index + (if key.name == "up" then -1 else 1), 1, #catalog.sounds)
            preview(s, cx)
        elseif key.name == "left" then action(s, cx, "quieter")
        elseif key.name == "right" then action(s, cx, "louder")
        elseif key.name == "space" then action(s, cx, "toggle")
        elseif key.name == "enter" then action(s, cx, "save")
        elseif key.name == "escape" then action(s, cx, "cancel")
        else return false end
    end,
    event = function(s, ev, cx)
        if ev.ev == "select" or ev.ev == "activate" then
            local index = tonumber(string.match(ev.item or "", "%.(%d+)$"))
            if index and catalog.sounds[index] then s.index = index preview(s, cx) end
        elseif ev.ev == "action" then action(s, cx, ev.act) end
    end,
})
tern.on("pane_exited", function(ev)
    if panels[ev.pane] then audio.stop(tostring(ev.pane)) panels[ev.pane] = nil end
end)
