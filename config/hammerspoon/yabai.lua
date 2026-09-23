-- Keyboard layer for yabai, mirroring the OmniWM bindings of the main Mac.
-- Hammerspoon owns the hotkeys (no skhd); every action is a `yabai -m` call.
-- Nothing here may shadow text editing: Option/Option+Shift with arrows, . ,
-- and ` stay with the focused app (word jumps, Alt+. in the shell, the
-- grave-accent dead key).
--
-- Workspaces are the native macOS desktops. yabai cannot create desktops
-- without its scripting addition (SIP stays on), so a missing one is added
-- through Mission Control (hs.spaces) the first time its number is used.

local M = {}

-- Load every extension up front. A lazy load prints "-- Loading extension",
-- and a print from a callback that outlived an `hs` CLI call raises "ipc port
-- is no longer valid", which pops the console open.
local _ = { hs.alert, hs.application, hs.axuielement, hs.canvas, hs.chooser, hs.eventtap, hs.fs, hs.geometry,
  hs.json, hs.screen, hs.spaces, hs.task, hs.timer, hs.urlevent, hs.window }

local function find_yabai()
  for _, p in ipairs({ os.getenv('HOME') .. '/.local/bin/yabai', '/opt/homebrew/bin/yabai', '/usr/local/bin/yabai' }) do
    if hs.fs.attributes(p, 'mode') == 'file' then return p end
  end
end

local YABAI = find_yabai()
if not YABAI then return M end

-- Async so a slow yabai never stalls Hammerspoon's hotkey thread. CMD is a
-- shell snippet where `Y` stands for the yabai binary (allows `a || b`).
local function run(cmd, on_exit)
  local script = 'Y="$1"; ' .. cmd
  hs.task.new('/bin/sh', on_exit, { '-c', script, 'sh', YABAI }):start()
end

local function query(args)
  local out, ok = hs.execute("'" .. YABAI .. "' -m query " .. args)
  if not ok then return nil end
  return hs.json.decode(out)
end

-- ── Workspaces ────────────────────────────────────────────────────────────────
local digit_keys = { '1', '2', '3', '4', '5', '6', '7', '8', '9' }
local last_space

local function remember_space()
  local cur = query('--spaces --space')
  if cur then last_space = cur.index end
end

-- Desktops are dynamic: using a number past the last desktop appends one new
-- desktop, and an empty desktop is removed as soon as it is left (or its last
-- window closes), so the numbers always name the desktops that hold windows.

-- space_index(n): yabai index of desktop N on the focused display; past the
-- last one, a new desktop is appended. nil if creation failed.
local function space_index(n)
  local spaces = query('--spaces --display') or {}
  if spaces[n] then return spaces[n].index end
  local count = #spaces
  local ok, err = hs.spaces.addSpaceToScreen(hs.screen.mainScreen(), true)
  if not ok then
    hs.alert.show('Could not create a desktop: ' .. tostring(err))
    return nil
  end
  -- Mission Control needs a moment to settle before yabai sees the new one.
  for _ = 1, 20 do
    spaces = query('--spaces --display') or {}
    if #spaces > count then return spaces[#spaces].index end
    hs.timer.usleep(50000)
  end
  return nil
end

local function focus_index(idx)
  remember_space()
  run('"$Y" -m space --focus ' .. idx, function(code)
    if code ~= 0 and idx >= 1 and idx <= 9 then
      hs.eventtap.keyStroke({ 'ctrl' }, digit_keys[idx], 0)
    end
  end)
end

-- Mission Control is open when the Dock exposes its "mc" group.
local function mc_is_open()
  local dock = hs.application.get('com.apple.dock')
  local ax = dock and hs.axuielement.applicationElement(dock)
  for _, child in ipairs(ax and ax:attributeValue('AXChildren') or {}) do
    if child:attributeValue('AXIdentifier') == 'mc' then return true end
  end
  return false
end

-- Option+N: go to desktop N. Pressed on the desktop already on screen it opens
-- Mission Control; any Option+N while Mission Control is open closes it (and
-- then goes to N when N is another desktop).
local function goto_space(n)
  local cur = query('--spaces --space')
  if mc_is_open() then
    hs.spaces.closeMissionControl()
    local spaces = query('--spaces --display') or {}
    if cur and spaces[n] and spaces[n].index ~= cur.index then
      hs.timer.doAfter(0.35, function() focus_index(spaces[n].index) end)
    end
    return
  end
  local idx = space_index(n)
  if not idx then return end
  if cur and idx == cur.index then
    hs.spaces.toggleMissionControl()
  else
    focus_index(idx)
  end
end

local function move_to_space(n)
  local idx = space_index(n)
  if idx then run('"$Y" -m window --space ' .. idx) end
end

local function back_and_forth()
  if last_space then focus_index(last_space) end
end

-- Removing a desktop needs Mission Control on screen (the Dock only exposes
-- the remove action there). Two things keep that from flashing:
--  * it waits for the desktop-switch slide to finish; opening Mission Control
--    mid-slide made it pop up and collapse halfway;
--  * with Screen Recording permission, a still image of the screen covers the
--    display while Mission Control opens and closes behind it.
local SWITCH_SETTLE = 0.6
local cleanup_timer

local function remove_empty_spaces()
  local spaces = query('--spaces --display') or {}
  if #spaces <= 1 then return end
  local doomed = {}
  for _, sp in ipairs(spaces) do
    if #sp.windows == 0 and not sp['is-visible'] and not sp['is-native-fullscreen'] then
      table.insert(doomed, sp.id)
    end
  end
  if #doomed == 0 then return end

  local user_mc = mc_is_open()
  local cover
  if not user_mc and hs.screenRecordingState() then
    local screen = hs.screen.mainScreen()
    local img = screen:snapshot()
    if img then
      cover = hs.canvas.new(screen:fullFrame())
      cover:level(hs.canvas.windowLevels.screenSaver)
      cover[1] = { type = 'image', image = img, imageScaling = 'scaleToFit' }
      cover:show()
    end
  end
  for _, id in ipairs(doomed) do hs.spaces.removeSpace(id, false) end
  if not user_mc then hs.spaces.closeMissionControl() end
  if cover then
    -- Hold the cover until Mission Control has finished closing.
    hs.timer.doAfter(0.5, function() cover:delete() end)
  end
end

-- cleanup_spaces(leave_current): remove every empty desktop that is not on
-- screen. With leave_current (a window just closed), an empty desktop on
-- screen is left first; the resulting space_changed signal then removes it.
local function cleanup_spaces(leave_current)
  if leave_current then
    local cur = query('--spaces --space')
    local spaces = query('--spaces --display') or {}
    if cur and #cur.windows == 0 and #spaces > 1 then
      run('"$Y" -m space --focus ' .. (cur.index > 1 and cur.index - 1 or cur.index + 1))
      return
    end
  end
  if cleanup_timer then cleanup_timer:stop() end
  cleanup_timer = hs.timer.doAfter(SWITCH_SETTLE, function()
    cleanup_timer = nil
    remove_empty_spaces()
  end)
end

-- yabai reports window/space events through a hammerspoon:// URL (not the
-- `hs` CLI, whose print redirection breaks callbacks that run afterwards).
hs.urlevent.bind('yabai-cleanup', function(_, params)
  cleanup_spaces(params.leave == 'true')
end)
local function add_signal(label, event, leave)
  local action = string.format("open -g 'hammerspoon://yabai-cleanup?leave=%s'", tostring(leave))
  run(string.format('"$Y" -m signal --add label=%s event=%s action="%s"', label, event, action))
end
add_signal('hs_cleanup_window', 'window_destroyed', true)
add_signal('hs_cleanup_app', 'application_terminated', true)
add_signal('hs_cleanup_space', 'space_changed', false)

-- ── Windows ───────────────────────────────────────────────────────────────────
local function focus_nth(n)
  local wins = query('--windows --space') or {}
  local tiled = {}
  for _, w in ipairs(wins) do
    if w['is-visible'] and not w['is-floating'] and not w['is-minimized'] then
      table.insert(tiled, w)
    end
  end
  table.sort(tiled, function(a, b)
    if a.frame.x ~= b.frame.x then return a.frame.x < b.frame.x end
    return a.frame.y < b.frame.y
  end)
  if tiled[n] then run('"$Y" -m window --focus ' .. tiled[n].id) end
end

local size_steps = { 1 / 3, 1 / 2, 2 / 3 }
local size_index = {}

local function cycle_size(dir)
  local w = query('--windows --window')
  if not w then return end
  local i = ((size_index[w.id] or 2) - 1 + dir) % #size_steps + 1
  size_index[w.id] = i
  run(string.format('"$Y" -m window --ratio abs:%.4f', size_steps[i]))
end

-- Option+T: a new window of the running Kitty (same instance, no extra Dock
-- icon), or Kitty itself when it is not running.
local KITTY_ID = 'net.kovidgoyal.kitty'
local function new_terminal_window()
  local app = hs.application.get(KITTY_ID)
  if app then
    hs.eventtap.keyStroke({ 'cmd' }, 'n', 0, app)
    app:activate()
  else
    hs.application.launchOrFocusByBundleID(KITTY_ID)
  end
end

local function toggle_layout()
  local s = query('--spaces --space')
  if not s then return end
  run('"$Y" -m space --layout ' .. (s.type == 'bsp' and 'stack' or 'bsp'))
end

local function raise_floating()
  local wins = query('--windows --space') or {}
  local ids = {}
  for _, w in ipairs(wins) do
    if w['is-floating'] and w['is-visible'] then table.insert(ids, '"$Y" -m window --focus ' .. w.id) end
  end
  if #ids > 0 then run(table.concat(ids, '; ')) end
end

local function quake_terminal()
  local kitten = os.getenv('HOME') .. '/.local/bin/kitten'
  if hs.fs.attributes(kitten) then
    hs.task.new(kitten, nil, { 'quick-access-terminal' }):start()
  end
end

-- ── App panels ────────────────────────────────────────────────────────────────
-- An app window that slides up from the bottom over the current desktop and
-- back down on the next press, like the Spotify/Slack panels of the main Mac.
-- yabai leaves it floating (yabairc rule); a hidden window is moved to the
-- current desktop before it is shown, so showing never jumps desktops.
--
-- Moving a real window every frame stutters (each step is an Accessibility
-- call the app must answer). The slide animates a snapshot in an hs.canvas
-- instead, and the real window only appears or hides at the end. Snapshots
-- need Screen Recording permission; without it the panel shows and hides
-- instantly.
local function panel_frame(screen, margin)
  local f = screen:frame()
  return hs.geometry.rect(f.x + margin, f.y + margin, f.w - 2 * margin, f.h - 2 * margin)
end

local panel_snapshots = {}
local slide_timer, slide_canvas

local function stop_slide()
  if slide_timer then slide_timer:stop() end
  if slide_canvas then slide_canvas:delete() end
  slide_timer, slide_canvas = nil, nil
end

-- slide_image(img, frame, from_y, to_y, duration, done)
local function slide_image(img, frame, from_y, to_y, duration, done)
  stop_slide()
  local c = hs.canvas.new({ x = frame.x, y = from_y, w = frame.w, h = frame.h })
  c:level(hs.canvas.windowLevels.floating)
  c[1] = { type = 'image', image = img, imageScaling = 'scaleToFit' }
  c:show()
  slide_canvas = c
  local start = hs.timer.secondsSinceEpoch()
  slide_timer = hs.timer.doEvery(1 / 60, function()
    local t = math.min((hs.timer.secondsSinceEpoch() - start) / duration, 1)
    local e = 1 - (1 - t) ^ 3
    c:topLeft({ x = frame.x, y = from_y + (to_y - from_y) * e })
    if t >= 1 then
      slide_timer:stop()
      slide_timer = nil
      if done then done() end
      -- Keep the image a beat so the real window is drawn before it goes.
      hs.timer.doAfter(0.05, function()
        c:delete()
        if slide_canvas == c then slide_canvas = nil end
      end)
    end
  end)
end

local function can_snapshot()
  return hs.screenRecordingState and hs.screenRecordingState()
end

local function toggle_panel(bundle_id, margin, duration)
  local app = hs.application.get(bundle_id)
  if app and not app:isHidden() and app:isFrontmost() then
    local win = app:mainWindow()
    local img = win and can_snapshot() and win:snapshot()
    if img then
      local f = win:frame()
      panel_snapshots[bundle_id] = img
      app:hide()
      slide_image(img, f, f.y, win:screen():fullFrame().h, duration)
    else
      app:hide()
    end
    return
  end

  local function show(running)
    local win = running:mainWindow() or running:allWindows()[1]
    if not win then return false end
    local cur = query('--spaces --space')
    if cur then hs.execute(string.format("'%s' -m window %d --space %d", YABAI, win:id(), cur.index)) end
    local screen = hs.screen.mainScreen()
    local target = panel_frame(screen, margin)
    win:setFrame(target, 0)
    local img = can_snapshot() and panel_snapshots[bundle_id]
    local function reveal()
      running:unhide()
      win:focus()
    end
    if img then
      slide_image(img, target, screen:fullFrame().h, target.y, duration, reveal)
    else
      reveal()
    end
    return true
  end

  if app and show(app) then return end
  hs.application.launchOrFocusByBundleID(bundle_id)
  local attempts = 0
  local poll
  poll = hs.timer.doEvery(0.1, function()
    attempts = attempts + 1
    local running = hs.application.get(bundle_id)
    if (running and show(running)) or attempts > 60 then poll:stop() end
  end)
end

local function close_window()
  local win = hs.window.focusedWindow()
  if win and not win:close() then hs.eventtap.keyStroke({ 'cmd' }, 'w', 0) end
end

local function kill_app()
  local app = hs.application.frontmostApplication()
  if not app then return end
  if app:bundleID() == 'com.apple.finder' and not hs.window.focusedWindow() then return end
  if app:isUnresponsive() then app:kill9() else app:kill() end
end

-- ── Menu anywhere: fuzzy-pick any menu item of the frontmost app ──────────────
local function menu_anywhere()
  local app = hs.application.frontmostApplication()
  if not app then return end
  local items = {}
  local function walk(list, path)
    for _, it in ipairs(list or {}) do
      local title = it.AXTitle
      if title and title ~= '' then
        local p = { table.unpack(path) }
        table.insert(p, title)
        if it.AXChildren then
          walk(it.AXChildren[1], p)
        elseif it.AXEnabled then
          table.insert(items, { text = table.concat(p, ' › '), path = p })
        end
      end
    end
  end
  walk(app:getMenuItems(), {})
  local chooser = hs.chooser.new(function(choice)
    if choice then app:selectMenuItem(choice.path) end
  end)
  chooser:choices(items)
  chooser:show()
end

-- ── Bindings (OmniWM action id -> key -> yabai action) ────────────────────────
local opt, opt_s = { 'alt' }, { 'alt', 'shift' }
local ctrl_opt, ctrl_opt_s, ctrl_cmd = { 'ctrl', 'alt' }, { 'ctrl', 'alt', 'shift' }, { 'ctrl', 'cmd' }

local function y(cmd) return function() run(cmd) end end

local bindings = {
  { ctrl_opt, 'tab', 'Workspace back and forth', function()
    run('"$Y" -m space --focus recent', function(code) if code ~= 0 then back_and_forth() end end)
  end },
  { opt, 'tab', 'Focus previous window', y('"$Y" -m window --focus recent') },
  { opt, 'w', 'Close window', close_window },
  { opt, 'q', 'Quit app', kill_app },
  { opt, 'm', 'Music panel', function() toggle_panel('com.apple.Music', 12, 0.22) end },
  { ctrl_opt_s, 'up', 'Move window to previous workspace', y('"$Y" -m window --space prev') },
  { ctrl_opt_s, 'down', 'Move window to next workspace', y('"$Y" -m window --space next') },
  { ctrl_opt_s, 'pageup', 'Move column to previous workspace', y('"$Y" -m window --space prev') },
  { ctrl_opt_s, 'pagedown', 'Move column to next workspace', y('"$Y" -m window --space next') },
  { ctrl_opt, 'left', 'Focus left', y('"$Y" -m window --focus west || "$Y" -m display --focus west') },
  { ctrl_cmd, 'left', 'Move window left', y('"$Y" -m window --swap west || "$Y" -m window --display west') },
  { ctrl_opt, 'down', 'Focus down', y('"$Y" -m window --focus south || "$Y" -m display --focus south') },
  { ctrl_cmd, 'down', 'Move window down', y('"$Y" -m window --swap south || "$Y" -m window --display south') },
  { ctrl_opt, 'up', 'Focus up', y('"$Y" -m window --focus north || "$Y" -m display --focus north') },
  { ctrl_cmd, 'up', 'Move window up', y('"$Y" -m window --swap north || "$Y" -m window --display north') },
  { ctrl_opt, 'right', 'Focus right', y('"$Y" -m window --focus east || "$Y" -m display --focus east') },
  { ctrl_cmd, 'right', 'Move window right', y('"$Y" -m window --swap east || "$Y" -m window --display east') },
  { ctrl_cmd, 'tab', 'Focus next monitor', y('"$Y" -m display --focus next || "$Y" -m display --focus first') },
  { ctrl_cmd, '`', 'Focus last monitor', y('"$Y" -m display --focus recent') },
  { opt, 'f', 'Fill the screen', y('"$Y" -m window --toggle zoom-fullscreen') },
  { opt_s, 'f', 'Native fullscreen', function()
    local win = hs.window.focusedWindow()
    if win then win:toggleFullScreen() end
  end },
  { ctrl_opt_s, 'left', 'Move column left', y('"$Y" -m window --warp west') },
  { ctrl_opt_s, 'right', 'Move column right', y('"$Y" -m window --warp east') },
  { ctrl_opt, 'home', 'Move column to first', y('"$Y" -m window --warp first') },
  { ctrl_opt, 'end', 'Move column to last', y('"$Y" -m window --warp last') },
  { opt, 't', 'New Kitty window', new_terminal_window },
  { opt, 'return', 'New Kitty window', new_terminal_window },
  { opt, 'home', 'Focus first column', y('"$Y" -m window --focus first') },
  { opt, 'end', 'Focus last column', y('"$Y" -m window --focus last') },
  { ctrl_opt, '.', 'Cycle size forward', function() cycle_size(1) end },
  { ctrl_opt, ',', 'Cycle size backward', function() cycle_size(-1) end },
  { ctrl_opt, 'f', 'Expand to available width', y('"$Y" -m window --ratio abs:0.8') },
  { ctrl_opt, 'r', 'Reload Hammerspoon', function() hs.reload() end },
  { opt, '-', 'Width -10%', y('"$Y" -m window --resize right:-60:0 || "$Y" -m window --resize left:60:0') },
  { opt, '=', 'Width +10%', y('"$Y" -m window --resize right:60:0 || "$Y" -m window --resize left:-60:0') },
  { opt_s, '-', 'Height -10%', y('"$Y" -m window --resize bottom:0:-60 || "$Y" -m window --resize top:0:60') },
  { opt_s, '=', 'Height +10%', y('"$Y" -m window --resize bottom:0:60 || "$Y" -m window --resize top:0:-60') },
  { opt_s, 'b', 'Balance sizes', y('"$Y" -m space --balance') },
  { opt_s, 'r', 'Raise floating windows', raise_floating },
  { ctrl_opt, 'm', 'Menu anywhere', menu_anywhere },
  { ctrl_opt, '`', 'Quake terminal (Kitty)', quake_terminal },
  { opt_s, 'l', 'Toggle workspace layout (bsp/stack)', toggle_layout },
  { opt_s, 'o', 'Overview (Mission Control)', function() hs.spaces.toggleMissionControl() end },
}

for n = 1, 9 do
  table.insert(bindings, { opt, digit_keys[n], 'Switch to workspace ' .. n, function() goto_space(n) end })
  table.insert(bindings, { opt_s, digit_keys[n], 'Move window to workspace ' .. n,
    function() move_to_space(n) end })
  table.insert(bindings, { ctrl_opt, digit_keys[n], 'Focus column ' .. n, function() focus_nth(n) end })
end

-- Command palette: every binding above, searchable by name.
local function command_palette()
  local choices = {}
  for i, b in ipairs(bindings) do
    table.insert(choices, { text = b[3], subText = table.concat(b[1], '+') .. '+' .. b[2], idx = i })
  end
  local chooser = hs.chooser.new(function(choice)
    if choice then bindings[choice.idx][4]() end
  end)
  chooser:choices(choices)
  chooser:show()
end
table.insert(bindings, { ctrl_opt, 'space', 'Command palette', command_palette })

M.goto_space, M.move_to_space, M.new_terminal_window = goto_space, move_to_space, new_terminal_window
M.cleanup_spaces, M.toggle_panel = cleanup_spaces, toggle_panel

M.hotkeys = {}
for _, b in ipairs(bindings) do
  table.insert(M.hotkeys, hs.hotkey.bind(b[1], b[2], b[4]))
end

return M
