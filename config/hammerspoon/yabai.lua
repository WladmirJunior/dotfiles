-- Keyboard layer for yabai, mirroring the OmniWM bindings of the main Mac.
-- Hammerspoon owns the hotkeys (no skhd); every action is a `yabai -m` call.
--
-- Without yabai's scripting addition (SIP stays on) yabai cannot focus spaces,
-- so workspace switching falls back to Mission Control's "Switch to Desktop N"
-- shortcuts (Ctrl+1..9), which the installer enables.

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

local function goto_space(n)
  remember_space()
  run('"$Y" -m space --focus ' .. n, function(code)
    if code ~= 0 and n >= 1 and n <= 9 then
      hs.eventtap.keyStroke({ 'ctrl' }, digit_keys[n], 0)
    end
  end)
end

local function back_and_forth()
  if last_space then goto_space(last_space) end
end

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

local function toggle_stack()
  local w = query('--windows --window')
  if not w then return end
  if (w['stack-index'] or 0) > 0 then
    -- Floating and re-tiling a window is how yabai pulls it out of a stack.
    run('"$Y" -m window --toggle float && "$Y" -m window --toggle float')
  else
    run('"$Y" -m window --stack recent')
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
  { opt, 'left', 'Focus left', y('"$Y" -m window --focus west || "$Y" -m display --focus west') },
  { opt, 'down', 'Focus down', y('"$Y" -m window --focus south || "$Y" -m display --focus south') },
  { opt, 'up', 'Focus up', y('"$Y" -m window --focus north || "$Y" -m display --focus north') },
  { opt, 'right', 'Focus right', y('"$Y" -m window --focus east || "$Y" -m display --focus east') },
  { opt, 'tab', 'Focus previous window', y('"$Y" -m window --focus recent') },
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
  { opt, 't', 'Toggle stacked (tabbed) column', toggle_stack },
  { opt, 'home', 'Focus first column', y('"$Y" -m window --focus first') },
  { opt, 'end', 'Focus last column', y('"$Y" -m window --focus last') },
  { opt, '.', 'Cycle size forward', function() cycle_size(1) end },
  { opt, ',', 'Cycle size backward', function() cycle_size(-1) end },
  { opt_s, 'f', 'Toggle full width', y('"$Y" -m window --toggle zoom-parent') },
  { ctrl_opt, 'f', 'Expand to available width', y('"$Y" -m window --ratio abs:0.8') },
  { ctrl_opt, 'r', 'Reset window size', y('"$Y" -m window --ratio abs:0.5') },
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
    y('"$Y" -m window --space ' .. n) })
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

M.hotkeys = {}
for _, b in ipairs(bindings) do
  table.insert(M.hotkeys, hs.hotkey.bind(b[1], b[2], b[4]))
end

return M
