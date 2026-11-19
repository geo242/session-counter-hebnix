-- Session Counter for Hebnix
-- Port of the Rocket League OBS session counter (overlay.html): a win/loss record for the
-- current session, kept per game mode, drawn over the game.
--
-- Everything comes from the Stats API events Hebnix forwards:
--   * mode    : Game.PlaylistId in UpdateState (team size for offline matches)
--   * my team : Game.Target, the player the camera follows (goal replays ignored)
--   * result  : MatchEnded.WinnerTeamNum or Game.bHasWinner
-- The session is saved in the plugin store, so it survives restarts of Hebnix and the game.

local plugin = {}

local VERSION = "1.0.2"
local P = "sc_"                    -- settings key prefix
local SESSION_KEY = P .. "session"

---------------------------------------------------------------------------
-- Static data
---------------------------------------------------------------------------

local PLAYLISTS = {
    [1] = "Casual 1v1", [2] = "Casual 2v2", [3] = "Casual 3v3", [4] = "Casual 4v4",
    [6] = "Private Match",
    [10] = "Ranked 1v1", [11] = "Ranked 2v2", [13] = "Ranked 3v3", [61] = "Ranked 4v4",
    [27] = "Ranked Hoops", [28] = "Ranked Rumble", [29] = "Ranked Dropshot", [30] = "Ranked Snow Day",
    [34] = "Tournament", [63] = "Heatseeker",
}

-- the original overlay.html look, in CSS pixels at 1080p
local DEFAULT_COLORS = {
    label  = "#b8b0c8",
    wins   = "#4ade80",
    losses = "#f87171",
    dash   = "#5b5368",
    streak = "#9146ff",
    bg     = "#000000",
    shadow = "#000000",
}
local COLOR_LABELS = {
    { key = "label",  text = "Mode label" },
    { key = "wins",   text = "Wins" },
    { key = "losses", text = "Losses" },
    { key = "dash",   text = "Dash" },
    { key = "streak", text = "Streak" },
    { key = "bg",     text = "Background" },
    { key = "shadow", text = "Text shadow" },
}

local LAYOUT = {
    pad_x = 10, pad_y = 4,
    label_size = 17, label_spacing = 2.5,
    num_size = 58, num_line = 1.05,
    dash_size = 40,
    gap = 10,
    streak_size = 16, streak_line = 1.15, streak_margin = 6, streak_width = 70,
    debug_size = 11,
}
local LINE = 1.33       -- Segoe UI line box (ascent + descent) per px of font size
local PREVIEW = { mode = "Ranked Snow Day", w = 7, l = 3, streak = 3 }  -- the README screenshot
local POP_SECONDS = 0.7
local FADE_SECONDS = 0.6
local RECONNECT_AFTER_MS = 5000    -- late messages from a match you just left aren't a reconnect

-- combo_box falls back to the first option, so defaults go first
-- "Between plays" hides the counter from each kickoff countdown until the next
-- goal or the end of the match: any visible overlay makes Windows composite the
-- game, which costs frames, so this keeps live play overlay-free.
local SHOW_OPTIONS = { "During matches", "Between plays", "While Rocket League is running", "Always" }
local ANCHORS_H = { "Left", "Center", "Right" }
local ANCHORS_V = { "Top", "Center", "Bottom" }
local ANCHOR_FACTOR = { Left = 0, Top = 0, Center = 0.5, Right = 1, Bottom = 1 }

local DEFAULTS = {
    show = SHOW_OPTIONS[1],
    anchor_h = "Left", anchor_v = "Top",
    pos_x = 1, pos_y = 2,
    scale = 100, scale_res = true,
    show_label = true, uppercase = true, show_streak = true,
    pop = true, shadow = false,
    bg_opacity = 0, bg_radius = 6,
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local session            -- { modes = { [mode] = {w,l,streak} }, current, t, done = {guid...}, leaves = {guid = {...}} }
local match = nil        -- { guid, votes = {blue, orange}, players, started, counted, playlist, human_seen, ... }
local in_game = false    -- between the first UpdateState of a match and leaving it
local live = false       -- from a kickoff countdown until the next goal or the end of the match
local ended = {}         -- guid -> true for matches already destroyed; late events for them are ignored
local ended_order = {}
local recent = {}        -- last 30 match outcomes, for the settings page
local pop = nil          -- { key = "w"|"l", at = seconds }
local fade = 0
local last_frame = nil
local names_cache = { raw = nil, map = {} }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function now_ms() return hebnix.unix_millis() end

local function opt_bool(key) return hebnix.get_bool(P .. key, DEFAULTS[key]) end
local function opt_num(key) return hebnix.get_number(P .. key, DEFAULTS[key]) end
local function opt_str(key) return hebnix.get_string(P .. key, DEFAULTS[key]) end

local function color(key)
    local hex = hebnix.get_string(P .. "c_" .. key, DEFAULT_COLORS[key])
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x") then hex = DEFAULT_COLORS[key] end
    return hex:sub(1, 7)
end

local function with_alpha(hex, alpha)
    alpha = math.max(0, math.min(255, math.floor(alpha + 0.5)))
    return hex:sub(1, 7) .. string.format("%02x", alpha)
end

local function reset_ms()
    local hours = hebnix.get_number(P .. "reset_hours", 4)
    if not hours or hours <= 0 then hours = 4 end
    return hours * 3600e3
end

local function leave_is_loss() return hebnix.get_bool(P .. "leave_loss", true) end
local function debug_on() return hebnix.get_bool(P .. "debug", false) end

-- "73:Heatseeker, 80:Something" -> { [73] = "Heatseeker", ... }
local function custom_names()
    local raw = hebnix.get_string(P .. "names", "")
    if raw ~= names_cache.raw then
        local map = {}
        for pair in raw:gmatch("[^,]+") do
            local id, name = pair:match("^%s*(%d+)%s*:%s*(.-)%s*$")
            if id and name ~= "" then map[tonumber(id)] = name end
        end
        names_cache = { raw = raw, map = map }
    end
    return names_cache.map
end

local function playlist_name(pid)
    return custom_names()[pid] or PLAYLISTS[pid] or ("Playlist " .. pid)
end

local function log_line(text)
    hebnix.log("[Session Counter] " .. text)
end

---------------------------------------------------------------------------
-- Session storage
---------------------------------------------------------------------------

local function fresh()
    return { modes = {}, current = nil, t = now_ms(), done = {}, leaves = {} }
end

local function load()
    local raw = hebnix.get_string(SESSION_KEY, "")
    if raw ~= "" then
        local ok, s = pcall(hebnix.json_decode, raw)
        if ok and type(s) == "table" and type(s.modes) == "table" and tonumber(s.t)
            and now_ms() - tonumber(s.t) < reset_ms() then
            s.done = type(s.done) == "table" and s.done or {}
            s.leaves = type(s.leaves) == "table" and s.leaves or {}
            return s
        end
    end
    return fresh()
end

local function save()
    session.t = now_ms()
    local ok, text = pcall(hebnix.json_encode, session)
    if ok then hebnix.set(SESSION_KEY, text) end
end

local function rec(mode)
    local r = session.modes[mode]
    if type(r) ~= "table" then
        r = { w = 0, l = 0, streak = 0 }
        session.modes[mode] = r
    end
    return r
end

local function peek(mode)
    local r = mode and session.modes[mode]
    if type(r) ~= "table" then return { w = 0, l = 0, streak = 0 } end
    return r
end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

local function start_pop(key)
    if key then pop = { key = key, at = hebnix.monotonic_seconds() } end
end

---------------------------------------------------------------------------
-- Match tracking
---------------------------------------------------------------------------

local function new_match(guid)
    match = {
        guid = guid, votes = { 0, 0 }, players = {}, started = false,
        counted = contains(session.done, guid), playlist = nil, human_seen = false,
    }
end

local function my_team()
    if not match then return nil end
    local b, o = match.votes[1], match.votes[2]
    if b == 0 and o == 0 then return nil end
    return b >= o and 0 or 1
end

local function team_of(p)
    local t = tonumber(p.TeamNum)
    if t == 0 or t == 1 then return t end
    return nil
end

local function is_bot(p)
    local id = tostring(p.PrimaryId or p.primaryId or "")
    return id == "" or id:lower():find("^unknown") ~= nil
end

local function human_opponent()
    local mine = my_team()
    for _, p in ipairs(match.players) do
        local t = team_of(p)
        if t and t ~= mine and not is_bot(p) then return true end
    end
    return false
end

local function team_size_label()
    local c = { [0] = 0, [1] = 0 }
    for _, p in ipairs(match.players) do
        local t = team_of(p)
        if t then c[t] = c[t] + 1 end
    end
    local n = math.max(c[0], c[1])
    if n > 0 then return n .. "v" .. n end
    return nil
end

local function log_match(result)
    local entry = string.format("%s  %s  %s", os.date("%H:%M"),
        match.playlist and playlist_name(match.playlist) or (session.current or "-"), result)
    table.insert(recent, entry)
    if #recent > 30 then table.remove(recent, 1) end
    log_line(string.format("match %s (playlist %s, team %s, players %d): %s",
        tostring(match.guid):sub(1, 8), tostring(match.playlist or "-"), tostring(my_team()),
        #match.players, result))
end

local function set_mode(name)
    if session.current ~= name then
        session.current = name
        save()
    end
end

local function update_mode(game)
    local pid = tonumber(game.PlaylistId) or 0
    if pid > 0 then
        if match.playlist ~= pid then
            match.playlist = pid
            set_mode(playlist_name(pid))
        end
    elseif not match.playlist and not match.size_label then
        -- no playlist (offline/local match): fall back to the team size
        local size = team_size_label()
        if size then
            match.size_label = size
            set_mode(size)
        end
    end
end

local function record(winner)
    if not match or match.counted or (winner ~= 0 and winner ~= 1) then return end
    local mine = my_team()
    if mine == nil then
        if not match.skip_logged then match.skip_logged = true; log_match("skip: team unknown") end
        return
    end
    -- opponents who quit vanish from the player list, so remember having seen one
    if not match.human_seen and not human_opponent() then
        if not match.skip_logged then match.skip_logged = true; log_match("skip: no human opponent") end
        return
    end
    match.counted = true
    log_match(winner == mine and "W" or (match.left_early and "L (left early)" or "L"))
    table.insert(session.done, match.guid)
    while #session.done > 50 do table.remove(session.done, 1) end
    local mode = session.current or team_size_label() or "Session"
    if not session.current then session.current = mode end
    local r = rec(mode)
    if winner == mine then
        r.w = r.w + 1
        r.streak = r.streak > 0 and r.streak + 1 or 1
        save(); start_pop("w")
    else
        r.l = r.l + 1
        r.streak = r.streak < 0 and r.streak - 1 or -1
        save(); start_pop("l")
    end
end

-- leaving early: a match you leave before it ends counts as a loss. If you then reconnect to
-- the same match (ranked reconnect), that loss is taken back and the real result counts instead.
local function record_leave()
    local mine = my_team()
    if mine == nil or not (match.human_seen or human_opponent()) then return end
    local mode = session.current or team_size_label() or "Session"
    session.leaves[match.guid] = { mode = mode, prev_streak = rec(mode).streak, at = now_ms() }
    local count, oldest_key, oldest_at = 0, nil, math.huge
    for key, x in pairs(session.leaves) do
        count = count + 1
        if (tonumber(x.at) or 0) < oldest_at then oldest_key, oldest_at = key, tonumber(x.at) or 0 end
    end
    if count > 20 and oldest_key then session.leaves[oldest_key] = nil end
    match.left_early = true
    record(1 - mine)
end

local function is_reconnect(guid, ev)
    local x = session.leaves[guid]
    return x ~= nil and ev == "UpdateState" and now_ms() - (tonumber(x.at) or 0) > RECONNECT_AFTER_MS
end

local function undo_leave(guid)
    local x = session.leaves[guid]
    local r = rec(x.mode)
    r.l = math.max(0, r.l - 1)
    r.streak = tonumber(x.prev_streak) or 0
    for i = #session.done, 1, -1 do
        if session.done[i] == guid then table.remove(session.done, i) end
    end
    session.leaves[guid] = nil
    ended[guid] = nil
    save()
end

local function mark_ended(guid)
    if not guid or ended[guid] then return end
    ended[guid] = true
    table.insert(ended_order, guid)
    if #ended_order > 100 then ended[table.remove(ended_order, 1)] = nil end
end

local function winner_from_game(g)
    local w = g.Winner
    if w == 0 or w == 1 then return w end
    if type(g.Teams) == "table" then
        for _, t in ipairs(g.Teams) do
            if t.Name == w and (t.TeamNum == 0 or t.TeamNum == 1) then return t.TeamNum end
        end
    end
    local s = tostring(w or ""):lower()
    if s:find("blue") then return 0 end
    if s:find("orange") then return 1 end
    return nil
end

local function handle(ev, event)
    local d = type(event) == "table" and event.data or nil
    if type(d) ~= "table" then d = {} end

    -- Hebnix lost the Stats API (game closed): like the overlay's socket closing, drop the match
    if ev == "GameDisconnected" or (ev == "GameLeft" and d.reason == "connection_lost") then
        match = nil
        in_game = false
        live = false
        return
    end
    if ev == "GameConnected" or ev == "GuiVisibility" then return end
    -- Hebnix forwards MatchDestroyed as GameLeft
    if ev == "MatchDestroyed" then ev = "GameLeft" end

    local guid = event and event.match_guid or d.MatchGuid
    if guid == "" then guid = nil end
    if guid and is_reconnect(guid, ev) then
        undo_leave(guid)
        if match and match.guid == guid then match = nil end
        new_match(guid)
        log_match("reconnected: leave undone")
    elseif guid and ended[guid] then
        return
    end

    if ev == "MatchCreated" or ev == "MatchInitialized" then
        if not match or (guid and guid ~= match.guid) then new_match(guid or ("m" .. now_ms())) end
    elseif guid and (not match or guid ~= match.guid) then
        new_match(guid)
    elseif not match and ev == "UpdateState" then
        new_match("m" .. now_ms())
    end

    if ev == "UpdateState" then
        in_game = true
        local g = type(d.Game) == "table" and d.Game or {}
        if type(d.Players) == "table" then match.players = d.Players end
        update_mode(g)
        local t = g.Target
        if g.bHasTarget and type(t) == "table" and not g.bReplay then
            local team = team_of(t)
            if team then match.votes[team + 1] = match.votes[team + 1] + 1 end
        end
        if not match.human_seen and my_team() ~= nil and human_opponent() then match.human_seen = true end
        if g.bHasWinner then record(winner_from_game(g)) end
    elseif ev == "RoundStarted" or ev == "CountdownBegin" then
        if match then match.started = true end
        live = true
    elseif ev == "GoalScored" then
        live = false
    elseif ev == "MatchEnded" then
        live = false
        local w = tonumber(d.WinnerTeamNum)
        if w == 0 or w == 1 then record(w) end
    elseif ev == "GameLeft" then
        in_game = false
        live = false
        if match and not match.counted and match.started and leave_is_loss() then record_leave() end
        if match and not match.counted and not match.skip_logged and #match.players > 0 then
            log_match("no result (left or canceled)")
        end
        if match then mark_ended(match.guid) end
        mark_ended(guid)
        match = nil
    end
end

-- manual fixes for the mode on screen
local function adjust(key, n)
    local r = rec(session.current or "Session")
    if not session.current then session.current = "Session" end
    r[key] = math.max(0, r[key] + n)
    if n > 0 then
        r.streak = key == "w" and math.max(r.streak, 0) + 1 or math.min(r.streak, 0) - 1
    end
    save()
    start_pop(key)
end

local function reset_session()
    session = fresh()
    save()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- hebnix.measure_text builds a DirectWrite format + layout on every call, and the
-- counter is drawn every frame, so widths are memoized per (size, text).
-- Everything drawn here is bold.
local measure_cache = {}
local measure_entries = 0

local function measure(text, size)
    local by_size = measure_cache[size]
    if not by_size then
        by_size = {}
        measure_cache[size] = by_size
    end
    local w = by_size[text]
    if w then return w end
    if measure_entries >= 2048 then
        -- the pop animation measures at many sizes; don't grow forever
        measure_cache, measure_entries = {}, 0
        by_size = {}
        measure_cache[size] = by_size
    end
    w = hebnix.measure_text(text, size, true)
    by_size[text] = w
    measure_entries = measure_entries + 1
    return w
end

local function spaced_width(text, size, spacing)
    local w = 0
    for _, ch in utf8.codes(text) do
        w = w + measure(utf8.char(ch), size) + spacing
    end
    return w
end

-- greedy word wrap, like the streak's fixed-width box
local function wrap(text, size, width)
    local lines, current = {}, nil
    for word in text:gmatch("%S+") do
        local candidate = current and (current .. " " .. word) or word
        if current and measure(candidate, size) > width then
            table.insert(lines, current)
            current = word
        else
            current = candidate
        end
    end
    if current then table.insert(lines, current) end
    return lines
end

local function streak_text(s)
    if s >= 2 then return s .. " win streak" end
    if s <= -2 then return (-s) .. " loss streak" end
    return ""
end

-- text whose line box starts at y and is line_h tall (vertically centered like CSS)
local function text_in_line(draw, x, y, line_h, str, size, col, halign, shadow)
    local ty = y + (line_h - size * LINE) / 2
    if shadow then
        local off = math.max(1, size * 0.05)
        draw.text(x + off, ty + off, str, { color = shadow, size = size, halign = halign, bold = true })
    end
    draw.text(x, ty, str, { color = col, size = size, halign = halign, bold = true })
end

local function scale_factor(h)
    local s = opt_num("scale") / 100
    if opt_bool("scale_res") then s = s * h / 1080 end
    return math.max(0.2, s)
end

local function pop_scale(key, now)
    if not pop or pop.key ~= key or not opt_bool("pop") then return 1 end
    local t = (now - pop.at) / POP_SECONDS
    if t >= 1 or t < 0 then return 1 end
    local eased = 1 - (1 - t) ^ 2   -- ease-out
    return 1.6 - 0.6 * eased
end

local function draw_counter(draw, w, h, alpha, now, mode, r)
    local s = scale_factor(h)
    local L = LAYOUT
    local a = 255 * alpha

    local show_label = opt_bool("show_label")
    local show_streak = opt_bool("show_streak")
    local label = mode or "Session"
    if opt_bool("uppercase") then label = label:upper() end

    local pad_x, pad_y = L.pad_x * s, L.pad_y * s
    local label_size = L.label_size * s
    local spacing = L.label_spacing * s
    local label_h = show_label and label_size * LINE or 0
    local label_w = show_label and spaced_width(label, label_size, spacing) or 0

    local num_size, dash_size, streak_size = L.num_size * s, L.dash_size * s, L.streak_size * s
    local gap = L.gap * s
    local num_h = num_size * L.num_line
    local dash_h = dash_size * LINE
    local streak_lh = streak_size * L.streak_line
    local row_h = math.max(num_h, dash_h, show_streak and streak_lh * 2 or 0)

    local w_text, l_text, dash_text = tostring(r.w), tostring(r.l), "\u{2013}"
    local ww = measure(w_text, num_size)
    local lw = measure(l_text, num_size)
    local dw = measure(dash_text, dash_size)
    local row_w = ww + gap + dw + gap + lw
    if show_streak then row_w = row_w + gap + L.streak_margin * s + L.streak_width * s end

    local box_w = pad_x * 2 + math.max(label_w, row_w)
    local box_h = pad_y * 2 + label_h + row_h

    local ax = ANCHOR_FACTOR[opt_str("anchor_h")] or 0
    local ay = ANCHOR_FACTOR[opt_str("anchor_v")] or 0
    local ox = math.floor(w * opt_num("pos_x") / 100 - box_w * ax)
    local oy = math.floor(h * opt_num("pos_y") / 100 - box_h * ay)

    local bg_alpha = opt_num("bg_opacity") * alpha
    if bg_alpha > 0 then
        draw.rect(ox, oy, box_w, box_h, {
            filled = true, color = with_alpha(color("bg"), bg_alpha), radius = opt_num("bg_radius") * s,
        })
    end
    local shadow = opt_bool("shadow") and with_alpha(color("shadow"), a * 0.7) or nil

    local x, y = ox + pad_x, oy + pad_y
    if show_label then
        local label_col = with_alpha(color("label"), a)
        local cx = x
        for _, code in utf8.codes(label) do
            local ch = utf8.char(code)
            text_in_line(draw, cx, y, label_h, ch, label_size, label_col, "left", shadow)
            cx = cx + measure(ch, label_size) + spacing
        end
        y = y + label_h
    end

    local row_mid = y + row_h / 2
    local function number(str, nx, width, key, col)
        local k = pop_scale(key, now)
        local size = num_size * k
        local line_h = num_h * k
        text_in_line(draw, nx + width / 2, row_mid - line_h / 2, line_h, str, size, col, "center", shadow)
    end

    number(w_text, x, ww, "w", with_alpha(color("wins"), a))
    x = x + ww + gap
    text_in_line(draw, x, row_mid - dash_h / 2, dash_h, dash_text, dash_size, with_alpha(color("dash"), a), "left", shadow)
    x = x + dw + gap
    number(l_text, x, lw, "l", with_alpha(color("losses"), a))
    x = x + lw + gap + L.streak_margin * s

    if show_streak then
        local text = streak_text(tonumber(r.streak) or 0)
        if text ~= "" then
            local lines = wrap(text, streak_size, L.streak_width * s)
            local top = row_mid - (#lines * streak_lh) / 2
            local col = with_alpha(color("streak"), a)
            for i, line in ipairs(lines) do
                text_in_line(draw, x, top + (i - 1) * streak_lh, streak_lh, line, streak_size, col, "left", shadow)
            end
        end
    end

    if debug_on() then
        local size = L.debug_size * s
        local col = with_alpha(color("label"), a)
        local lines = {
            string.format("api:%s  game:%s  playlist:%s", hebnix.rl_connected() and "connected" or "waiting",
                in_game and "in match" or "-", tostring(match and match.playlist or "-")),
            string.format("match:%s  myTeam:%s  humans:%s  counted:%s",
                match and tostring(match.guid):sub(1, 8) or "-",
                match and tostring(my_team()) or "-",
                match and tostring(human_opponent()) or "-",
                match and tostring(match.counted) or "-"),
        }
        local dy = oy + box_h
        for _, line in ipairs(lines) do
            draw.text(ox + pad_x, dy, line, { color = col, size = size })
            dy = dy + size * LINE
        end
    end
end

local function should_show()
    if not hebnix.get_bool(P .. "enabled", true) then return false end
    local mode = opt_str("show")
    if mode == "Always" then return true end
    if mode == "While Rocket League is running" then return hebnix.rl_connected() end
    if mode == "Between plays" then return hebnix.rl_connected() and not live end
    return in_game
end

---------------------------------------------------------------------------
-- Callbacks
--
-- No on_tick: Hebnix repaints its own windows at the overlay refresh rate for
-- as long as any plugin defines on_tick or on_overlay while the game runs.
-- Everything here changes on a game event, a settings frame, or (while the
-- counter is on screen) an overlay frame, so those drive the hooks instead.
---------------------------------------------------------------------------

local draw_overlay -- defined below

-- on_overlay only exists while the counter is visible or fading out: any
-- defined on_overlay keeps Hebnix in its fast repaint mode.
local function update_overlay_hook()
    local want = fade > 0 or should_show() or hebnix.get_bool(P .. "preview", false)
    if want then
        plugin.on_overlay = draw_overlay
    else
        plugin.on_overlay = nil
        last_frame = nil -- don't count the hidden time as one long fade step
    end
end

-- a new session starts after the reset period without a counted game (checked outside matches)
local function check_expiry()
    if not in_game and now_ms() - (tonumber(session.t) or 0) >= reset_ms() and next(session.modes) ~= nil then
        log_line("new session (nothing counted for a while)")
        reset_session()
    end
end

function plugin.on_load()
    hebnix.set(P .. "preview", false)
    session = load()
    plugin.on_overlay = nil
    check_expiry()
    update_overlay_hook()
    log_line("v" .. VERSION .. " loaded")
end

function plugin.on_unload()
    match = nil
    plugin.on_overlay = nil
end

function plugin.on_game_event(event_type, event)
    check_expiry() -- before handle(), so a stale session is reset before the next match counts
    handle(event_type, event)
    update_overlay_hook()
end

draw_overlay = function(draw, w, h)
    local now = hebnix.monotonic_seconds()
    local dt = last_frame and math.max(0, now - last_frame) or 0
    last_frame = now
    -- preview: a sample record at full opacity, whatever the game is doing
    if hebnix.get_bool(P .. "preview", false) then
        fade = 1
        draw_counter(draw, w, h, 1, now, PREVIEW.mode, PREVIEW)
        return
    end
    local target = should_show() and 1 or 0
    if fade < target then fade = math.min(target, fade + dt / FADE_SECONDS)
    elseif fade > target then fade = math.max(target, fade - dt / FADE_SECONDS) end
    if fade <= 0 then
        -- faded out: drop the hook until something shows it again. (fade is also 0
        -- on the first frame of a fade-in, while target is still 1.)
        if target == 0 then update_overlay_hook() end
        return
    end
    draw_counter(draw, w, h, fade, now, session.current, peek(session.current))
end

local function color_reset_all()
    for key, value in pairs(DEFAULT_COLORS) do hebnix.set(P .. "c_" .. key, value) end
    for key, value in pairs(DEFAULTS) do
        if key ~= "show" then hebnix.set(P .. key, value) end
    end
end

function plugin.on_settings(ui)
    -- runs every frame while the settings page is open: follow show/preview changes
    update_overlay_hook()
    ui.heading("Session Counter")
    ui.checkbox(P .. "enabled", "Enable Session Counter", true)
    ui.combo_box(P .. "show", "Show", SHOW_OPTIONS)
    ui.horizontal(function()
        ui.checkbox(P .. "preview", "Show preview (sample record)", false)
        if ui.button("Play pop animation") then start_pop("w") end
    end)
    ui.space(8)

    ui.heading("This session")
    local modes = {}
    for mode, r in pairs(session.modes) do
        if type(r) == "table" then table.insert(modes, mode) end
    end
    table.sort(modes)
    local any = #modes > 0
    for _, mode in ipairs(modes) do
        local r = session.modes[mode]
        do
            local marker = mode == session.current and "  (on screen)" or ""
            local streak = streak_text(tonumber(r.streak) or 0)
            ui.label(string.format("%s: %d - %d%s%s", mode, r.w, r.l,
                streak ~= "" and ("  " .. streak) or "", marker))
        end
    end
    if not any then ui.label("No matches counted yet.") end
    ui.label("Fix the record for the mode on screen (" .. (session.current or "Session") .. "):")
    ui.horizontal(function()
        if ui.button("+W") then adjust("w", 1) end
        if ui.button("-W") then adjust("w", -1) end
        if ui.button("+L") then adjust("l", 1) end
        if ui.button("-L") then adjust("l", -1) end
        if ui.button("Reset session") then reset_session() end
    end)
    ui.space(8)

    ui.heading("Counting")
    ui.checkbox(P .. "leave_loss", "Leaving a match early counts as a loss (taken back if you reconnect)", true)
    ui.slider(P .. "reset_hours", "New session after this many hours without a counted match", 1, 24, 4)
    ui.label("Extra playlist names, as id:name pairs separated by commas (e.g. 73:Heatseeker):")
    ui.text_input(P .. "names", "73:Heatseeker")
    ui.space(8)

    ui.heading("Position & size")
    ui.combo_box(P .. "anchor_h", "Horizontal anchor", ANCHORS_H)
    ui.combo_box(P .. "anchor_v", "Vertical anchor", ANCHORS_V)
    ui.slider(P .. "pos_x", "X position (% of screen)", 0, 100, DEFAULTS.pos_x)
    ui.slider(P .. "pos_y", "Y position (% of screen)", 0, 100, DEFAULTS.pos_y)
    ui.slider(P .. "scale", "Size (%)", 25, 300, DEFAULTS.scale)
    ui.checkbox(P .. "scale_res", "Scale with resolution (size is for 1080p)", DEFAULTS.scale_res)
    ui.space(8)

    ui.heading("Appearance")
    ui.checkbox(P .. "show_label", "Show the mode name", DEFAULTS.show_label)
    ui.checkbox(P .. "uppercase", "Mode name in capitals", DEFAULTS.uppercase)
    ui.checkbox(P .. "show_streak", "Show streaks (two or more in a row)", DEFAULTS.show_streak)
    ui.checkbox(P .. "pop", "Pop animation when a result is counted", DEFAULTS.pop)
    ui.checkbox(P .. "shadow", "Text shadow", DEFAULTS.shadow)
    ui.slider(P .. "bg_opacity", "Background opacity", 0, 255, DEFAULTS.bg_opacity)
    ui.slider(P .. "bg_radius", "Background corner radius", 0, 30, DEFAULTS.bg_radius)
    ui.collapsing("Colors", function(cui)
        for _, c in ipairs(COLOR_LABELS) do
            cui.color_picker(P .. "c_" .. c.key, c.text, DEFAULT_COLORS[c.key])
        end
    end)
    if ui.button("Restore default appearance") then color_reset_all() end
    ui.space(8)

    ui.collapsing("Troubleshooting", function(cui)
        cui.checkbox(P .. "debug", "Show connection and match details under the counter", false)
        cui.label("Recent matches (newest last):")
        if #recent == 0 then cui.label("  none yet") end
        for _, line in ipairs(recent) do cui.label("  " .. line) end
    end)
    ui.label("Session Counter " .. VERSION)
end

return plugin
