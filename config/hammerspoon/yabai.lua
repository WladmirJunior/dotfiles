-- Keyboard layer for yabai, mirroring the OmniWM bindings of the main Mac.
-- Hammerspoon owns the hotkeys (no skhd); every action is a `yabai -m` call.
--
-- Workspaces are the native macOS desktops. yabai cannot create desktops
-- without its scripting addition (SIP stays on), so a missing one is added
-- through Mission Control (hs.spaces) the first time its number is used.

local M = {}

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

local function goto_space(n)
  local idx = space_index(n)
  if idx then focus_index(idx) end
end

local function move_to_space(n)
  local idx = space_index(n)
  if idx then run('"$Y" -m window --space ' .. idx) end
end

local function back_and_forth()
  if last_space then focus_index(last_space) end
end

-- cleanup_spaces(leave_current): remove every empty desktop that is not on
-- screen. With leave_current (a window just closed), an empty desktop on
-- screen is left first; the resulting space_changed signal then removes it.
local function cleanup_spaces(leave_current)
  local spaces = query('--spaces --display') or {}
  if #spaces <= 1 then return end
  local removed = false
  for _, sp in ipairs(spaces) do
    if #sp.windows == 0 and not sp['is-visible'] and not sp['is-native-fullscreen'] then
      if hs.spaces.removeSpace(sp.id, false) then removed = true end
    end
  end
  if removed then hs.spaces.closeMissionControl() end
  if leave_current then
    local cur = query('--spaces --space')
    spaces = query('--spaces --display') or {}
    if cur and #cur.windows == 0 and #spaces > 1 then
      run('"$Y" -m space --focus ' .. (cur.index > 1 and cur.index - 1 or cur.index + 1))
    end
  end
end

-- yabai reports window/space events; the signal calls back through the `hs`
-- command-line client (hs.ipc, loaded by init.lua).
local HS_CLI = hs.processInfo.bundlePath .. '/Contents/Frameworks/hs/hs'
local function add_signal(label, event, leave)
  local action = string.format("%s -c 'package.loaded.yabai.cleanup_spaces(%s)'", HS_CLI, tostring(leave))
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
-- An app window that slides in over the current desktop and out on the next
-- press, like the Spotify/Slack panels of the main Mac. yabai leaves it
-- floating (yabairc rule); a hidden window is moved to the current desktop
-- before it is shown, so showing it never jumps to another desktop.
local function panel_frame(screen, margin)
  local f = screen:frame()
  return hs.geometry.rect(f.x + margin, f.y + margin, f.w - 2 * margin, f.h - 2 * margin)
end

local function toggle_panel(bundle_id, margin, duration)
  local app = hs.application.get(bundle_id)
  if app and not app:isHidden() and app:isFrontmost() then
    local win = app:mainWindow()
    if win then
      local f = win:frame()
      win:setFrame(hs.geometry.rect(f.x, -f.h, f.w, f.h), duration)
      hs.timer.doAfter(duration, function() app:hide() end)
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
    win:setFrame(hs.geometry.rect(target.x, -target.h, target.w, target.h), 0)
    running:unhide()
    win:focus()
    win:setFrame(target, duration)
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
  { opt_s, 'left', 'Move window left', y('"$Y" -m window --swap west || "$Y" -m window --display west') },
  { opt_s, 'down', 'Move window down', y('"$Y" -m window --swap south || "$Y" -m window --display south') },
  { opt_s, 'up', 'Move window up', y('"$Y" -m window --swap north || "$Y" -m window --display north') },
  { opt_s, 'right', 'Move window right', y('"$Y" -m window --swap east || "$Y" -m window --display east') },
  { ctrl_cmd, 'tab', 'Focus next monitor', y('"$Y" -m display --focus next || "$Y" -m display --focus first') },
  { ctrl_cmd, '`', 'Focus last monitor', y('"$Y" -m display --focus recent') },
  { opt, 'return', 'Toggle fullscreen', y('"$Y" -m window --toggle zoom-fullscreen') },
  { ctrl_opt_s, 'left', 'Move column left', y('"$Y" -m window --warp west') },
  { ctrl_opt_s, 'right', 'Move column right', y('"$Y" -m window --warp east') },
  { ctrl_opt, 'home', 'Move column to first', y('"$Y" -m window --warp first') },
  { ctrl_opt, 'end', 'Move column to last', y('"$Y" -m window --warp last') },
  { opt, 't', 'New Kitty window', new_terminal_window },
  { opt, 'home', 'Focus first column', y('"$Y" -m window --focus first') },
  { opt, 'end', 'Focus last column', y('"$Y" -m window --focus last') },
  { opt, '.', 'Cycle size forward', function() cycle_size(1) end },
  { opt, ',', 'Cycle size backward', function() cycle_size(-1) end },
  { opt_s, 'f', 'Toggle full width', y('"$Y" -m window --toggle zoom-parent') },
  { ctrl_opt, 'f', 'Expand to available width', y('"$Y" -m window --ratio abs:0.8') },
  { ctrl_opt, 'r', 'Reload Hammerspoon', function() hs.reload() end },
  { opt, '-', 'Width -10%', y('"$Y" -m window --resize right:-60:0 || "$Y" -m window --resize left:60:0') },
  { opt, '=', 'Width +10%', y('"$Y" -m window --resize right:60:0 || "$Y" -m window --resize left:-60:0') },
  { opt_s, '-', 'Height -10%', y('"$Y" -m window --resize bottom:0:-60 || "$Y" -m window --resize top:0:60') },
  { opt_s, '=', 'Height +10%', y('"$Y" -m window --resize bottom:0:60 || "$Y" -m window --resize top:0:-60') },
  { opt_s, 'b', 'Balance sizes', y('"$Y" -m space --balance') },
  { opt_s, 'r', 'Raise floating windows', raise_floating },
  { ctrl_opt, 'm', 'Menu anywhere', menu_anywhere },
  { opt, '`', 'Quake terminal (Kitty)', quake_terminal },
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
