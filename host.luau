local catalog = require("./catalog")
local audio = require("./audio")
local ui = tern.ui
local panels = {}
local function select_target(s, cx, target)
    audio.stop(tostring(cx.pane))
    s.target = target
    s.index = table.find(catalog.sounds, s[target]) or 6
    s.error = if catalog.paths[s[target]] then nil else "Saved sound unavailable: " .. s[target] .. ". Choose a replacement."
end
local function select_sound(s, index)
    s.index = index
    s[s.target] = catalog.sounds[index]
end
local function preview(s, cx)
    audio.play(tostring(cx.pane), s[s.target], s.volume, function(err)
        s.error = err
        if panels[cx.pane] then cx:render() end
    end)
end
local function finish(s, cx, save)
    if save then
        tern.kv.set("settings", { enabled = s.enabled, sound = s.sound, failureSound = s.failureSound, volume = s.volume })
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
    elseif act == "completion" then select_target(s, cx, "sound")
    elseif act == "failure" then select_target(s, cx, "failureSound")
    elseif act == "quieter" or act == "louder" then
        s.volume = math.clamp(s.volume + (if act == "quieter" then -10 else 10), 0, 100)
        preview(s, cx)
    end
end
tern.block.define("settings", {
    init = function(cx)
        local s = catalog.load()
        select_target(s, cx, "sound")
        panels[cx.pane] = true
        return s
    end,
    title = function() return "Bell settings" end,
    view = function(s, cx)
        local rows = {}
        for i, name in catalog.sounds do
            table.insert(rows, ui.node("item", { key = tostring(i), label = name, detail = if catalog.custom[name] then "custom" else "macOS" }))
        end
        local function button(text, act)
            return ui.el("button", { text = text, actions = { click = act } })
        end
        return { main = ui.col({
            ui.text("Bell settings · Changes are saved only with Enter or Save"),
            ui.row({ button(if s.enabled then "Enabled · toggle" else "Disabled · toggle", "toggle"), button("−10%", "quieter"), ui.text(tostring(s.volume) .. "%"), button("+10%", "louder"), button("Preview", "preview") }),
            ui.row({ ui.text("Task complete / needs input"), ui.text(ui.span(s.sound, "code")), button(if s.target == "sound" then "Editing" else "Edit", "completion") }),
            ui.row({ ui.text("Task failed"), ui.text(ui.span(s.failureSound, "code")), button(if s.target == "failureSound" then "Editing" else "Edit", "failure") }),
            ui.node("list", { key = "sounds", selected = "main.sounds." .. s.index, max = { lines = math.max(3, math.min(14, cx.rows - 13)) } }, rows),
            ui.text(s.error or "Tab category · ↑↓ select and preview · ←→ volume"),
            ui.text("Space toggle · Enter save · Esc cancel"),
        }), dock = ui.row({ button("Save", "save"), button("Cancel", "cancel") }) }
    end,
    key = function(s, key, cx)
        if key.name == "up" or key.name == "down" then
            select_sound(s, math.clamp(s.index + (if key.name == "up" then -1 else 1), 1, #catalog.sounds))
            preview(s, cx)
        elseif key.name == "tab" then select_target(s, cx, if s.target == "sound" then "failureSound" else "sound")
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
            if index and catalog.sounds[index] then select_sound(s, index) preview(s, cx) end
        elseif ev.ev == "action" then action(s, cx, ev.act) end
    end,
})
tern.on("pane_exited", function(ev)
    if panels[ev.pane] then audio.stop(tostring(ev.pane)) panels[ev.pane] = nil end
end)
