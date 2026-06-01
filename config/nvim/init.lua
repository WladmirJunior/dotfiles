-- Basic Neovim configuration

vim.opt.number = true          -- Show line numbers
vim.opt.relativenumber = true  -- Relative numbers (helps with navigation)
vim.opt.mouse = 'a'            -- Enable mouse support
vim.opt.ignorecase = true      -- Case-insensitive search
vim.opt.smartcase = true       -- ...unless you type an uppercase letter
vim.opt.tabstop = 2            -- 2-space tabs (Flutter/Dart default)
vim.opt.shiftwidth = 2
vim.opt.expandtab = true       -- Use spaces instead of tabs
vim.opt.termguicolors = true   -- Rich colors (needed for Ghostty)
vim.opt.cursorline = true      -- Highlight current line
vim.opt.clipboard = 'unnamedplus'
vim.opt.undofile = true

-- Theme
-- vim.cmd("colorscheme evening")
-- vim.cmd("colorscheme catppuccin")
vim.cmd("colorscheme zaibatsu")
