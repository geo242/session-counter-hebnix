-- Mock Hebnix host to exercise session_counter/main.lua
-- json_encode/json_decode are supplied by run_tests.py (py_json_encode / py_json_decode)
local store = {}
local mono = 0
local clock = 1.7e12
local connected = true
local draws = {}

hebnix = {
    log = function(...) print("[log]", ...) end,
    get_bool = function(k, d) local v = store[k]; if type(v) == "boolean" then return v end; return d == nil and false or d end,
    get_string = function(k, d) local v = store[k]; if type(v) == "string" then return v end; return d or "" end,
    get_number = function(k, d) local v = store[k]; if type(v) == "number" then return v end; return d or 0 end,
    set = function(k, v)
        assert(type(v) ~= "table" and v ~= nil, "unsupported store value for " .. k)
        store[k] = v
    end,
    monotonic_seconds = function() return mono end,
    unix_millis = function() return clock end,
    rl_connected = function() return connected end,
    measure_text = function(t, size, bold) measure_calls = (measure_calls or 0) + 1; return utf8.len(t) * size * (bold and 0.6 or 0.55) end,
    json_encode = function(v) return py_json_encode(v) end,
    json_decode = function(s) return py_json_decode(s) end,
}

local draw = {
    rect = function(x, y, w, h, o) table.insert(draws, { kind = "rect", color = o.color }) end,
    line = function() end,
    text = function(x, y, t, o)
        assert(type(t) == "string" and o.size > 0, "bad text call")
        table.insert(draws, { kind = "text", text = t, color = o.color, size = o.size, x = x, y = y })
    end,
}

local plugin
local function load_plugin()
    plugin = dofile(arg_path)
    plugin.on_load()
end

local function frame(dt)
    draws = {}
    mono = mono + (dt or 1)
    -- any defined on_tick keeps Hebnix repainting at the overlay rate
    assert(plugin.on_tick == nil, "on_tick defined")
    -- like the host: on_overlay is only called while the plugin defines it
    if plugin.on_overlay then plugin.on_overlay(draw, 1920, 1080) end
    return draws
end

local press = {}
local function fake_ui()
    return setmetatable({}, { __index = function(self, k)
        if k == "horizontal" then return function(f) f() end end
        if k == "collapsing" then return function(_, f) f(self) end end
        if k == "button" then return function(t) local p = press[t]; press[t] = nil; return p == true end end
        if k == "combo_box" then return function(key, _, opts) return opts[1] end end
        return function() end
    end })
end
-- settings are changed from the settings page, which runs on_settings every frame
local function settings_changed() plugin.on_settings(fake_ui()) end

-- text drawn this frame, label characters joined back up
local function screen()
    local parts = {}
    for _, d in ipairs(frame()) do if d.kind == "text" then table.insert(parts, d.text) end end
    return table.concat(parts, "|")
end

-- the mode label is drawn one character at a time at 17px
local function label_and_score()
    local parts, label = {}, {}
    for _, d in ipairs(frame()) do
        if d.kind == "text" then
            table.insert(parts, d.text)
            if math.abs(d.size - 17) < 0.01 then table.insert(label, d.text) end
        end
    end
    return table.concat(label), table.concat(parts, "|")
end

local function ev(name, guid, data)
    data = data or {}
    if guid then data.MatchGuid = guid end
    plugin.on_game_event(name, { event_type = name, match_guid = guid, data = data })
end

local ME = { Name = "Me", PrimaryId = "Steam|111|0", TeamNum = 0 }
local function state(guid, playlist, opp_id, extra)
    local game = { PlaylistId = playlist, bHasTarget = true, Target = { Name = "Me", TeamNum = 0 } }
    for k, v in pairs(extra or {}) do game[k] = v end
    ev("UpdateState", guid, { Players = { ME, { Name = "Opp", PrimaryId = opp_id or "Epic|222|0", TeamNum = 1 } }, Game = game })
end

local function play(guid, playlist, winner, opp_id)
    ev("MatchCreated", guid)
    state(guid, playlist, opp_id)
    ev("CountdownBegin", guid)
    state(guid, playlist, opp_id)
    ev("MatchEnded", guid, { WinnerTeamNum = winner })
    ev("GameLeft", guid)  -- Hebnix sends MatchDestroyed as GameLeft
end

local function record_of(mode)
    local s = py_json_decode(store["sc_session"])
    local r = s.modes[mode]
    return r and r.w, r and r.l, r and r.streak
end

load_plugin()

-- 1. not in a match: hidden by default ("During matches")
assert(#frame() == 0, "drew outside a match")
assert(plugin.on_overlay == nil, "on_overlay defined while hidden")

-- 2. a ranked 2v2 win shows up and stays through the post-match screen
ev("MatchCreated", "m1")
state("m1", 11)
frame(1) -- fade in
local label, s = label_and_score()
assert(label == "RANKED 2V2", "label was " .. label .. " / " .. s)
assert(s:find("|0|\u{2013}|0"), "score missing: " .. s)
assert(plugin.on_overlay ~= nil, "on_overlay not defined while shown")
-- unchanged frames reuse measured widths
local before = measure_calls
label_and_score(); label_and_score()
assert(measure_calls == before, "text re-measured every frame")
ev("CountdownBegin", "m1")
ev("MatchEnded", "m1", { WinnerTeamNum = 0 })
-- pop: the win number is drawn bigger right after
local popped
for _, d in ipairs(frame(0.05)) do if d.text == "1" then popped = d.size end end
assert(popped and popped > 58, "no pop animation, size " .. tostring(popped))
local settled
for _, d in ipairs(frame(1)) do if d.text == "1" then settled = d.size end end
assert(math.abs(settled - 58) < 0.01, "number size not back to 58: " .. settled)
ev("GameLeft", "m1")
assert(record_of("Ranked 2v2") == 1)
frame(1) -- fade out
assert(#frame(1) == 0, "still drawn after leaving")
assert(plugin.on_overlay == nil, "on_overlay still defined after fading out")

-- 3. late events for a finished match are ignored
ev("MatchEnded", "m1", { WinnerTeamNum = 1 })
local w, l = record_of("Ranked 2v2")
assert(w == 1 and l == 0, "late event counted")

-- 4. two losses -> loss streak, wrapped onto two lines
play("m2", 11, 1)
play("m3", 11, 1)
w, l, streak = record_of("Ranked 2v2")
assert(w == 1 and l == 2 and streak == -2, string.format("got %s-%s streak %s", w, l, streak))
store["sc_show"] = "Always"
settings_changed()
s = screen(); s = screen()
assert(s:find("2 loss|streak"), "streak text: " .. s)

-- 5. bots don't count
play("m4", 11, 0, "Unknown|0|0")
w, l = record_of("Ranked 2v2")
assert(w == 1 and l == 2, "bot match counted")

-- 6. modes are separate
play("m5", 27, 0)
assert(record_of("Ranked Hoops") == 1)
label = label_and_score()
assert(label == "RANKED HOOPS", "label " .. label)
state("m6", 11)
label = label_and_score()
assert(label == "RANKED 2V2", "back to 2v2: " .. label)
ev("GameLeft", "m6") -- never started: no leave

-- 7. leaving early is a loss, reconnecting takes it back
ev("MatchCreated", "m7")
state("m7", 11)
ev("RoundStarted", "m7")
ev("GameLeft", "m7")
w, l, streak = record_of("Ranked 2v2")
assert(l == 3 and streak == -3, "leave not a loss")
clock = clock + 10000
state("m7", 11)
w, l, streak = record_of("Ranked 2v2")
assert(l == 2 and streak == -2, "reconnect did not undo: " .. l .. " " .. streak)
ev("MatchEnded", "m7", { WinnerTeamNum = 0 })
w, l, streak = record_of("Ranked 2v2")
assert(w == 2 and l == 2 and streak == 1, "reconnect result wrong")
ev("GameLeft", "m7")

-- 8. losing the Stats API mid-match isn't a leave
ev("MatchCreated", "m8")
state("m8", 11)
ev("RoundStarted", "m8")
plugin.on_game_event("GameLeft", { event_type = "GameLeft", data = { reason = "connection_lost" } })
plugin.on_game_event("GameDisconnected", { event_type = "GameDisconnected", data = { reason = "connection_lost" } })
w, l = record_of("Ranked 2v2")
assert(l == 2, "connection loss counted as leave")

-- 9. winner from Game.bHasWinner + team name, custom playlist names
store["sc_names"] = " 73 : Mystery Mode , junk"
ev("MatchCreated", "m9")
state("m9", 73)
state("m9", 73, nil, { bHasWinner = true, Winner = "Orange", Teams = { { Name = "Blue", TeamNum = 0 }, { Name = "Orange", TeamNum = 1 } } })
assert(select(2, record_of("Mystery Mode")) == 1, "custom name / bHasWinner")
ev("GameLeft", "m9")

-- 10. offline match without a playlist uses the team size
play("m10", 0, 0)
assert(record_of("1v1") == 1, "team size fallback")

-- 11. persists across reloads, expires after the reset period
load_plugin()
frame(); local lbl, sc = label_and_score(); assert(lbl == "1V1", "session not restored: " .. lbl .. " / " .. sc)
assert(record_of("Ranked 2v2") == 2)
clock = clock + 5 * 3600e3
load_plugin()
frame()
label, s = label_and_score()
assert(label == "SESSION" and s:find("|0|\u{2013}|0"), "expired session kept: " .. s)

-- 12. a long idle while loaded starts a new session by the next match
play("m11", 10, 0)
assert(record_of("Ranked 1v1") == 1)
clock = clock + 5 * 3600e3
ev("MatchCreated", "m11b")
assert(record_of("Ranked 1v1") == nil, "idle session not reset")
ev("GameLeft", "m11b")

-- 13. settings render; manual buttons adjust the mode on screen
play("m12", 13, 0)
press["+L"] = true
plugin.on_settings(fake_ui())
w, l, streak = record_of("Ranked 3v3")
assert(w == 1 and l == 1 and streak == -1, "manual +L")
press["-W"] = true
plugin.on_settings(fake_ui())
assert(record_of("Ranked 3v3") == 0, "manual -W")
press["Reset session"] = true
plugin.on_settings(fake_ui())
assert(record_of("Ranked 3v3") == nil, "reset")

-- 14. appearance options
store["sc_bg_opacity"] = 180
store["sc_shadow"] = true
store["sc_debug"] = true
store["sc_show_label"] = false
local found_rect, found_debug = false, false
for _, d in ipairs(frame()) do
    if d.kind == "rect" and d.color:match("^#000000") then found_rect = true end
    if d.kind == "text" and d.text:find("api:connected") then found_debug = true end
    assert(not (d.kind == "text" and d.text == "S"), "label drawn when hidden")
end
assert(found_rect and found_debug, "background/debug missing")
press["Restore default appearance"] = true
plugin.on_settings(fake_ui())
assert(store["sc_bg_opacity"] == 0 and store["sc_shadow"] == false and store["sc_show_label"] == true)
store["sc_scale"] = 200
local big
for _, d in ipairs(frame()) do if d.text == "0" then big = d.size end end
assert(math.abs(big - 116) < 0.01, "scale setting ignored")

-- 15. "While Rocket League is running" hides when disconnected
store["sc_show"] = "While Rocket League is running"
connected = false
frame(1)
assert(#frame(1) == 0, "shown while disconnected")

-- 16. preview shows the sample record even when hidden, and is off again after a reload
assert(plugin.on_overlay == nil, "on_overlay kept after fading out")
store["sc_preview"] = true
store["sc_scale"] = 100
settings_changed()
label, s = label_and_score()
assert(label == "RANKED SNOW DAY" and s:find("|7|\u{2013}|3|3 win|streak"), "preview: " .. s)
press["Play pop animation"] = true
plugin.on_settings(fake_ui())
local pop_size
for _, d in ipairs(frame(0.05)) do if d.text == "7" then pop_size = d.size end end
assert(pop_size and pop_size > 58, "preview pop")
load_plugin()
assert(store["sc_preview"] == false, "preview survived reload")
assert(#frame(1) == 0, "preview still drawn after reload")

-- 17. "Between plays": hidden from the kickoff countdown until a goal or the match end
connected = true
store["sc_show"] = "Between plays"
settings_changed()
frame(1) -- fade-in starts
assert(#screen() > 0, "hidden in menus")
ev("MatchCreated", "b1")
state("b1", 11)
assert(#screen() > 0, "hidden before the first kickoff")
ev("CountdownBegin", "b1")
frame(1)
assert(#frame(1) == 0 and plugin.on_overlay == nil, "shown during live play")
ev("RoundStarted", "b1")
state("b1", 11)
assert(plugin.on_overlay == nil, "updates during play brought it back")
ev("GoalScored", "b1")
frame(1)
assert(#screen() > 0, "hidden after a goal")
ev("CountdownBegin", "b1")
frame(1)
assert(plugin.on_overlay == nil, "shown at the next kickoff")
ev("MatchEnded", "b1", { WinnerTeamNum = 0 })
frame(1)
assert(#screen() > 0, "hidden after the match")
ev("GameLeft", "b1")

print("ALL TESTS PASSED")
