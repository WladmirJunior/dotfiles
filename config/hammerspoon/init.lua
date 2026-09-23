-- Managed by dotfiles (public). A private overlay may own ~/.hammerspoon/init.lua
-- instead; the installer never replaces one it did not write.

hs.autoLaunch(true)

local ok, err = pcall(require, 'yabai')
if not ok then
  hs.alert.show('yabai hotkeys failed to load: ' .. tostring(err))
end
