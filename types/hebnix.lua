---@meta
-- Type definitions for the Hebnix plugin API, for the Lua language server
-- (VS Code: the "Lua" extension by sumneko). Editor-only: Hebnix never loads
-- this file, and it isn't part of the plugin zip.
--
-- Written from Hebnix's source (hebnix-app/src/plugins/lua_api.rs, manager.rs,
-- rlapi.rs and docs/) as of v2.3.5. Types marked `any` weren't clear from the
-- source; check it before relying on their shape.

-------------------------------------------------------------------------------
-- Plugin hooks: define these on the table main.lua returns. Hebnix looks each
-- one up every time, so a plugin can set or clear them at runtime.
-------------------------------------------------------------------------------

---@class HebnixPlugin
---@field on_load? fun()
---@field on_unload? fun()
--- Runs every Hebnix frame while defined. Defining it keeps Hebnix repainting
--- at the overlay refresh rate, so clear it when there's nothing to do.
---@field on_tick? fun()
--- Draws over the game. Defining it keeps the overlay window presenting.
---@field on_overlay? fun(draw: HebnixDraw, width: number, height: number)
---@field on_settings? fun(ui: HebnixUi)
--- Contents of the floating window opened with hebnix.window.open.
---@field on_window? fun(ui: HebnixUi)
--- Stats API events: "UpdateState", "MatchCreated", "GoalScored", ...
---@field on_game_event? fun(event: string, data: table)
---@field on_http_response? fun(req_id: string, status: integer, body: string)
---@field on_http_result? fun(req_id: string, status: integer, body: string, headers: table<string, string>)
---@field on_http_download_response? fun(req_id: string, status: integer, body: string)
---@field on_http_redirect_response? fun(req_id: string, status: integer, location: string)
---@field on_http_upload_response? fun(req_id: string, status: integer, body: string)
--- name is the file name inside assets/; both nil if the picker was cancelled.
---@field on_asset_imported? fun(req_id: string, name: string?, error: string?)
---@field on_ws_open? fun(id: string)
---@field on_ws_message? fun(id: string, data: string)
---@field on_ws_close? fun(id: string, reason: string)

-------------------------------------------------------------------------------
-- Shared shapes
-------------------------------------------------------------------------------

--- "#rrggbb" or "#rrggbbaa"
---@alias HebnixColor string

---@class HebnixPlaylistRank
---@field playlist_id integer
---@field playlist_name string
---@field tier_id integer
---@field tier_name string
---@field division_id integer 0-3
---@field division_name string
---@field mmr integer?
---@field matches_played integer
---@field placement_matches_played integer
---@field peak_mmr integer
---@field peak_tier_id integer
---@field peak_div_id integer
---@field delta_up integer MMR needed to promote
---@field delta_down integer MMR needed to demote
---@field win_streak integer
---@field win_streak_type string "win" or "loss"
---@field rank_percentile number

---@class HebnixPlayerStats
---@field primary_id string
---@field display_name string
---@field platform string
---@field platform_user_handle string
---@field platform_user_id string
---@field avatar_url string?
---@field best string
---@field player_id integer
---@field ranks table<integer, HebnixPlaylistRank> keyed by playlist id
---@field lifetime table?
---@field averages table<integer, table>
---@field last_updated string?
---@field current_season integer
---@field fetched_at number
---@field cached boolean
---@field season_reward_level integer
---@field season_reward_wins integer
---@field error string? set when the lookup failed
---@field not_found boolean

---@class HebnixRect
---@field left number
---@field top number
---@field right number
---@field bottom number

---@class HebnixRocketLeagueProcess
---@field pid integer
---@field exe_path string
---@field root_dir string
---@field platform string
---@field save_data_path string

---@class HebnixController
---@field id integer
---@field name string
---@field kind string
---@field lx number
---@field ly number
---@field rx number
---@field ry number
---@field lt number
---@field rt number
---@field btn_south boolean
---@field btn_east boolean
---@field btn_west boolean
---@field btn_north boolean
---@field dpad_up boolean
---@field dpad_down boolean
---@field dpad_left boolean
---@field dpad_right boolean
---@field bumper_l boolean
---@field bumper_r boolean
---@field trigger_l boolean
---@field trigger_r boolean
---@field stick_l boolean
---@field stick_r boolean
---@field select boolean
---@field start boolean
---@field touchpad boolean

-------------------------------------------------------------------------------
-- draw: passed to on_overlay
-------------------------------------------------------------------------------

---@class HebnixLineOpts
---@field color? HebnixColor
---@field width? number

---@class HebnixRectOpts
---@field color? HebnixColor
---@field filled? boolean default false
---@field border? number
---@field border_color? HebnixColor
---@field radius? number

---@class HebnixGradientOpts
---@field color? HebnixColor
---@field color2? HebnixColor
---@field radius? number
---@field angle? number default 135

---@class HebnixCircleOpts
---@field color? HebnixColor
---@field width? number
---@field filled? boolean

---@class HebnixTextOpts
---@field color? HebnixColor
---@field size? number default 14
---@field halign? "left"|"center"|"right"
---@field font? "rl-body"|"rl-body-bold"|"rl-header"|"rl-header-thin"|"rl-digits"
---@field bold? boolean

---@class HebnixDraw
local HebnixDraw = {}
---@param opts? HebnixLineOpts
function HebnixDraw.line(x1, y1, x2, y2, opts) end
---@param opts? HebnixRectOpts
function HebnixDraw.rect(x, y, w, h, opts) end
---@param opts? HebnixGradientOpts
function HebnixDraw.gradient(x, y, w, h, opts) end
---@param opts? HebnixCircleOpts
function HebnixDraw.circle(x, y, radius, opts) end
---@param s string
---@param opts? HebnixTextOpts
function HebnixDraw.text(x, y, s, opts) end
--- Filled polygon: {{x, y}, {x, y}, ...}
---@param points number[][]
---@param opts? { color?: HebnixColor }
function HebnixDraw.polygon(points, opts) end
---@param path string path inside the plugin's assets folder
---@param opts? table
function HebnixDraw.image(path, x, y, w, h, opts) end
---@param frame integer handle from hebnix.capture.window_capture_frame
---@param opts? { opacity?: number }
function HebnixDraw.capture_image(frame, x, y, w, h, opts) end

-------------------------------------------------------------------------------
-- ui: passed to on_settings and on_window
-------------------------------------------------------------------------------

---@class HebnixUi
local HebnixUi = {}
---@param text string
function HebnixUi.label(text) end
---@param text string
function HebnixUi.heading(text) end
---@param hex HebnixColor
---@param text string
function HebnixUi.colored_label(hex, text) end
---@param text string
function HebnixUi.copy_to_clipboard(text) end
--- Edits the stored setting `key`; returns its current value.
---@param key string
---@param label string
---@param default? HebnixColor
---@return HebnixColor
function HebnixUi.color_picker(key, label, default) end
function HebnixUi.separator() end
---@param px? number
function HebnixUi.space(px) end
---@param text string
---@return boolean clicked
function HebnixUi.button(text) end
--- Edits the stored setting `key`; returns its current value.
---@param key string
---@param label string
---@param min number
---@param max number
---@param default? number
---@return number
function HebnixUi.slider(key, label, min, max, default) end
--- Edits the stored setting `key`; returns the selected option.
---@param key string
---@param label string
---@param options string[]
---@return string
function HebnixUi.combo_box(key, label, options) end
--- Edits the stored setting `key`; returns its current value.
---@param key string
---@param label string
---@param default? boolean
---@return boolean
function HebnixUi.checkbox(key, label, default) end
---@param key string
---@param value string
function HebnixUi.set_text_input(key, value) end
---@param key string
---@param placeholder? string
---@return string
function HebnixUi.text_input(key, placeholder) end
---@param key string
---@param placeholder? string
---@return string
function HebnixUi.password_input(key, placeholder) end
---@param text string
---@param height? number
function HebnixUi.readonly_textbox(text, height) end
---@param path string path inside the plugin's assets folder
---@param opts? table
---@return boolean drawn
function HebnixUi.image(path, opts) end
--- Button-prompt icon for a bind string; false for keyboard binds or buttons
--- with no icon.
---@param bind string
---@param opts? { width?: number, height?: number, x?: number, y?: number, tint?: HebnixColor }
---@return boolean drawn
function HebnixUi.bind_icon(bind, opts) end
---@param f fun(ui: HebnixUi)
function HebnixUi.horizontal(f) end
--- Starts folded.
---@param label string
---@param f fun(ui: HebnixUi)
function HebnixUi.collapsing(label, f) end
--- Two blocks side by side; the right one is right_width wide (default 280).
---@param left fun(ui: HebnixUi)
---@param right fun(ui: HebnixUi)
---@param right_width? number
function HebnixUi.columns(left, right, right_width) end
--- Vertical scroll area that follows its newest line until the user scrolls up.
---@param max_height number
---@param f fun(ui: HebnixUi)
function HebnixUi.scroll_area(max_height, f) end

-------------------------------------------------------------------------------
-- hebnix: the global API table
-------------------------------------------------------------------------------

---@class hebnix
hebnix = {}

--- Writes to the Hebnix console and log.
---@param ... any
function hebnix.log(...) end

-- Settings store (per plugin, persisted)

---@param key string
---@param default? boolean
---@return boolean
function hebnix.get_bool(key, default) end
---@param key string
---@param default? string
---@return string
function hebnix.get_string(key, default) end
---@param key string
---@param default? number
---@return number
function hebnix.get_number(key, default) end
---@param key string
---@param value boolean|string|number|nil
function hebnix.set(key, value) end

-- State

---@return boolean
function hebnix.is_gui_open() end
---@return boolean
function hebnix.in_match() end
--- True while connected to Rocket League's Stats API.
---@return boolean
function hebnix.rl_connected() end
---@return string
function hebnix.app_version() end
--- This plugin's folder name.
---@return string
function hebnix.slug() end
---@return string
function hebnix.plugin_dir() end
--- "steam", "epic" or "".
---@return string
function hebnix.detected_platform() end
---@return number
function hebnix.ui_scale() end
--- Seconds since an arbitrary start; use for timers.
---@return number
function hebnix.monotonic_seconds() end
--- Wall-clock epoch milliseconds (os.time is whole seconds only).
---@return integer
function hebnix.unix_millis() end
--- "fullscreen", "windowed" or "borderless", from TASystemSettings.ini.
---@return string?
function hebnix.window_mode() end

-- Rocket League config files

---@param filename string
---@return string?
function hebnix.rl_read_config(filename) end
---@param filename string
---@param content string
---@return any
function hebnix.rl_write_config(filename, content) end
---@param filename string
---@return boolean
function hebnix.rl_config_exists(filename) end
---@return any
function hebnix.rl_restore() end

-- Helpers

---@param rank string
---@return string
function hebnix.shorten_rank(rank) end
---@param id integer
---@return string
function hebnix.tier_name(id) end
---@param pid string Stats API PrimaryId, e.g. "Steam|7656...|0"
---@return string
function hebnix.platform_tag(pid) end
---@param pid string
---@return boolean
function hebnix.is_bot(pid) end

-- Input and binds

---@param bind string e.g. "f3", "controller_a"
---@return boolean
function hebnix.is_bind_pressed(bind) end
--- "(Xinput)", "(Playstation)", "(Dinput)" or "" for keyboard.
---@param bind string
---@return string
function hebnix.bind_type_label(bind) end
--- The player's Rocket League binds for an action, e.g. "scoreboard".
---@param action string
---@return string[]
function hebnix.get_action_binds(action) end
---@param action string
---@return boolean
function hebnix.is_action_pressed(action) end
function hebnix.refresh_action_binds() end
--- Starts capturing the next key or button press.
---@param timeout? number seconds, default 10
---@return boolean started
function hebnix.capture_bind_async(timeout) end
--- ("idle", nil), ("pending", nil), ("done", bind) or ("timeout", nil);
--- "done" and "timeout" reset to idle.
---@return "idle"|"pending"|"done"|"timeout" status
---@return string? bind
function hebnix.capture_bind_result() end
--- Connected pads (Universal Analog Support).
---@return HebnixController[]
function hebnix.controllers() end
---@return table[]
function hebnix.poll_gamepads() end

-- Ranks and profiles

--- Blocking network call, cached per player. Avoid in on_tick.
---@param primary_id string
---@param display_name string
---@return HebnixPlayerStats?
function hebnix.fetch_stats(primary_id, display_name) end
---@param primary_id string
---@return HebnixPlayerStats?
function hebnix.cached_stats(primary_id) end
--- Non-blocking rank fetch by Stats API PrimaryId; poll with stats_result(primary_id).
---@param primary_id string
---@param display_name string
---@return boolean
function hebnix.fetch_stats_async(primary_id, display_name) end
--- Non-blocking rank fetch by platform + platform id ("steam", id64 / "epic",
--- account id). Returns the key to poll with stats_result, or nil.
---@param platform string
---@param identifier string
---@return string?
function hebnix.fetch_profile_async(platform, identifier) end
--- nil (never requested), "pending", or the profile; check .error on it.
--- A finished result is kept for 15 s before another request refetches.
---@param key string
---@return HebnixPlayerStats|"pending"|nil
function hebnix.stats_result(key) end
function hebnix.clear_stats_cache() end

-- Launch.log, process and save file

---@param verify? boolean default true
---@return table?
function hebnix.parse_launch_log(verify) end
---@param verify? boolean default true
---@return string key poll with launch_log_result
function hebnix.parse_launch_log_async(verify) end
--- nil (never requested), "pending", or the log table.
---@param key string
---@return table|"pending"|nil
function hebnix.launch_log_result(key) end
function hebnix.clear_launch_log() end
---@return HebnixRocketLeagueProcess?
function hebnix.find_rocket_league() end
---@return HebnixRect?
function hebnix.rocket_league_window_rect() end
--- Toolhelp snapshot; cache the result instead of polling every frame.
---@param name string part of the exe name, case-insensitive
---@return boolean
function hebnix.process_running(name) end
---@return string?
function hebnix.find_save_file() end
--- Blocking (decrypt + parse); call from a button or on_load.
---@param path? string
---@return table summary has an "error" field on failure
function hebnix.load_save_summary(path) end
---@param path? string
---@return string key poll with save_summary_result
function hebnix.load_save_summary_async(path) end
---@param key string
---@return table|"pending"|nil
function hebnix.save_summary_result(key) end
function hebnix.clear_save_summary_cache() end
---@return table
function hebnix.find_save_accounts() end
---@return table
function hebnix.find_save_files() end
---@param path? string
---@return table
function hebnix.load_save_configuration(path) end
---@param path string
---@param id string
---@param value string
---@return table result { ok, backup } or { error }
function hebnix.update_save_configuration(path, id, value) end
---@param path string
---@param backup string
---@return table
function hebnix.restore_save_configuration(path, backup) end
---@param path string
---@return table
function hebnix.backup_save_configuration(path) end

-- Assets and files

---@return table[]
function hebnix.list_assets() end
--- Copies a file into the plugin's assets/ folder (file picker unless opts.path);
--- the result arrives in on_asset_imported.
---@param req_id string
---@param opts? { title?: string, filter_name?: string, extensions?: string[], path?: string, name?: string }
function hebnix.import_asset_async(req_id, opts) end
---@param path string inside the plugin folder
---@return string?
function hebnix.read_asset_text(path) end
--- Byte-safe read, only under a manifest [permissions] read_roots entry.
---@param path string
---@return string?
function hebnix.read_file(path) end
---@param rel string
---@param data string
---@return any
function hebnix.write_asset(rel, data) end
---@param rel string
---@return any
function hebnix.clear_asset_dir(rel) end
---@param rel string
---@return table?
function hebnix.image_palette(rel) end

-- Text, data and crypto

--- Segoe UI pixel width of a string at `size`.
---@param s string
---@param size number
---@param bold? boolean
---@return number
function hebnix.measure_text(s, size, bold) end
---@param json_str string
---@return any
function hebnix.json_decode(json_str) end
---@param value any
---@return string
function hebnix.json_encode(value) end
---@param data string
---@return string
function hebnix.base64_encode(data) end
---@param data string
---@return string
function hebnix.zlib_compress(data) end
---@param key string
---@param message string
---@return string hex
function hebnix.crypto_hmac_sha256(key, message) end
---@param data string
---@return string
function hebnix.crypto_sha256_base64(data) end
---@param key string PKCS#8 P-256 key
---@param msg string
---@return string?
function hebnix.p256_sign(key, msg) end
---@param key string
---@return string? uncompressed point
function hebnix.p256_public(key) end

-- Network (results arrive in the on_http_* / on_ws_* hooks)

---@param req_id string
---@param url string
---@param headers? table<string, string>
function hebnix.http_get_async(req_id, url, headers) end
---@param req_id string
---@param url string
---@param headers? table<string, string>
function hebnix.http_get_no_redirect_async(req_id, url, headers) end
---@param req_id string
---@param url string
---@param headers? table<string, string>
function hebnix.http_download_async(req_id, url, headers) end
---@param req_id string
---@param url string
---@param body string
---@param headers? table<string, string>
function hebnix.http_post_async(req_id, url, body, headers) end
---@param req_id string
---@param url string
---@param body string
---@param headers? table<string, string>
function hebnix.http_put_async(req_id, url, body, headers) end
---@param req_id string
---@param url string
---@param fields? table<string, string>
---@param files? table<string, string>
---@param headers? table<string, string>
function hebnix.http_multipart_post_async(req_id, url, fields, files, headers) end
---@param req_id string
---@param method string
---@param url string
---@param body? string
---@param headers? table<string, string>
function hebnix.http_request_async(req_id, method, url, body, headers) end
---@param id string
---@param url string
function hebnix.ws_connect_async(id, url) end
---@param id string
---@param text string
function hebnix.ws_send(id, text) end
---@param id string
---@param text string
function hebnix.ws_send_socket(id, text) end
---@param id string
function hebnix.ws_close(id) end
--- Sends a command on the Stats API socket.
---@param command string
---@param data? any
function hebnix.stats_send(command, data) end
---@param url string
---@return boolean
function hebnix.open_url(url) end
--- Reveals a folder in Explorer.
---@param path string
---@return boolean
function hebnix.open_path(path) end

-- Media

--- Whatever Windows says is playing, or nil. Refreshed about once a second.
---@return table?
function hebnix.media_session() end
--- Cover art bytes for the current media_session; changes when thumb_rev does.
---@return string?
function hebnix.media_thumbnail() end

--- Shows over the game and lands in the notifications tab.
---@param text string
---@param opts? { accent?: HebnixColor, background?: HebnixColor, text?: HebnixColor, duration?: number, image?: string }
function hebnix.toast(text, opts) end

-- Sub-tables

---@class hebnix.screen
hebnix.screen = {}
---@return boolean
function hebnix.screen.available() end
---@return integer? width
---@return integer? height
function hebnix.screen.size() end
---@return integer? r
---@return integer? g
---@return integer? b
function hebnix.screen.pixel(x, y) end
---@return integer? r
---@return integer? g
---@return integer? b
function hebnix.screen.average(x, y, w, h) end
---@param tol? integer default 20
---@return boolean?
function hebnix.screen.match_color(x, y, w, h, r, g, b, tol) end
---@return number? x
---@return number? y
function hebnix.screen.cursor() end

---@class hebnix.cvar
hebnix.cvar = {}
---@param name string
---@return boolean
function hebnix.cvar.register(name) end
---@param name string
---@param value any
---@return boolean
function hebnix.cvar.set(name, value) end
---@param name string
---@return any value
---@return "not_registered"|"unset"|nil error
function hebnix.cvar.get(name) end
---@param name string
---@return boolean
function hebnix.cvar.delete(name) end

---@class hebnix.input
hebnix.input = {}
---@param ... string keys
function hebnix.input.send(...) end

---@class hebnix.chat
hebnix.chat = {}
---@param channel string
---@param message string
function hebnix.chat.send(channel, message) end
---@param limit? integer
---@return table[]
function hebnix.chat.history(limit) end
--- True once queued on the local Stats API socket.
---@param text string
---@return boolean
function hebnix.chat.msg(text) end

---@class hebnix.audio
hebnix.audio = {}
---@param path string
---@param volume? number
---@return boolean
function hebnix.audio.play(path, volume) end

---@class hebnix.window
hebnix.window = {}
--- Opens the plugin's floating window; its contents come from on_window.
---@param opts? { title?: string, width?: number|string, height?: number|string, close_button?: boolean, opacity?: number, always_on_top?: boolean }
function hebnix.window.open(opts) end
function hebnix.window.close() end
---@return boolean
function hebnix.window.is_open() end
---@return table?
function hebnix.window.get_position() end
---@param title string
function hebnix.window.set_title(title) end
---@param on boolean
function hebnix.window.set_always_on_top(on) end

---@class hebnix.command
hebnix.command = {}
---@param opts table
function hebnix.command.change_pov(opts) end
---@param opts table
function hebnix.command.load_replay(opts) end
---@param opts table
function hebnix.command.seek_replay(opts) end
---@param speed number
function hebnix.command.set_game_speed(speed) end
---@param visible boolean
function hebnix.command.set_hud_visibility(visible) end
--- Private match with admin mode.
---@param paused boolean
function hebnix.command.set_match_paused(paused) end

---@class hebnix.overlay
hebnix.overlay = {}
---@param value any
function hebnix.overlay.send(value) end

---@class hebnix.capture
hebnix.capture = {}
---@return { id: string, title: string, process: string }[]
function hebnix.capture.windows() end
--- Asks the user to approve the window; returns a handle or nil. fps 1-30.
---@param window_id string
---@param opts? { fps?: number, cursor?: boolean }
---@return integer?
function hebnix.capture.window_capture_start(window_id, opts) end
---@param handle integer
---@return integer? frame
function hebnix.capture.window_capture_frame(handle) end
---@param handle integer
function hebnix.capture.window_capture_stop(handle) end

---@class hebnix.rlapi
--- True when WebSockets or RLAPI are enabled and the game's connection is captured.
---@field enabled boolean
hebnix.rlapi = {}
--- Poll from on_tick: (nil, "pending"), (history, nil) or (nil, error).
---@return table? history
---@return string? state
function hebnix.rlapi.matchhistory() end
