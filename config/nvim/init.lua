-- Neovim configuration: lean, curated, one plugin per problem.
-- Read top to bottom; every plugin block says what it does and why it's here.
-- Plugins are managed by lazy.nvim and pinned in lazy-lock.json (same dir).

-- ─────────────────────────── Options ───────────────────────────
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
vim.opt.signcolumn = 'yes'     -- Stable gutter (gitsigns/diagnostics don't shift text)
vim.opt.splitright = true      -- New vsplits open to the right
vim.opt.splitbelow = true      -- New splits open below
vim.opt.updatetime = 250       -- Faster CursorHold (diagnostics float, gitsigns)

-- Leader key must be set before plugins load.
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ─────────────────────────── lazy.nvim bootstrap ───────────────────────────
-- Plugin manager: lazy-loads everything, locks versions in lazy-lock.json,
-- UI via :Lazy. Clones itself on first run.
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath })
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  -- ── Colorscheme: tokyonight ──
  -- Modern theme with treesitter/LSP highlight groups done right.
  {
    'folke/tokyonight.nvim',
    priority = 1000,
    config = function() vim.cmd.colorscheme('tokyonight-night') end,
  },

  -- ── Syntax: nvim-treesitter (main branch, the current rewrite) ──
  -- Incremental parser: real syntax tree instead of regex highlighting.
  -- Gives precise highlight, structural selection and correct indentation.
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    build = ':TSUpdate',
    lazy = false,
    config = function()
      require('nvim-treesitter').install({
        'lua', 'vim', 'vimdoc', 'bash', 'dart', 'clojure', 'go', 'python',
        'json', 'yaml', 'toml', 'markdown', 'markdown_inline', 'diff',
      })
      -- Start treesitter highlight for any buffer whose parser is installed.
      vim.api.nvim_create_autocmd('FileType', {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },

  -- ── Fuzzy finder: fzf-lua ──
  -- Files/grep/buffers/help picker on top of the fzf binary already installed
  -- (faster than telescope, no extra native deps).
  {
    'ibhagwan/fzf-lua',
    cmd = 'FzfLua',
    keys = {
      { '<leader>ff', '<cmd>FzfLua files<cr>', desc = 'Find files' },
      { '<leader>fg', '<cmd>FzfLua live_grep<cr>', desc = 'Live grep (rg)' },
      { '<leader>fb', '<cmd>FzfLua buffers<cr>', desc = 'Buffers' },
      { '<leader>fh', '<cmd>FzfLua helptags<cr>', desc = 'Help' },
      { '<leader>fr', '<cmd>FzfLua oldfiles<cr>', desc = 'Recent files' },
    },
  },

  -- ── Completion: blink.cmp ──
  -- Completion engine with a Rust fuzzy matcher (the fast, current choice).
  -- version = '1.*' pulls the prebuilt matcher, no Rust toolchain needed.
  {
    'saghen/blink.cmp',
    version = '1.*',
    event = 'InsertEnter',
    opts = {
      keymap = { preset = 'enter' },        -- Enter accepts, C-n/C-p navigate
      completion = { documentation = { auto_show = true } },
      sources = { default = { 'lsp', 'path', 'buffer' } },
    },
  },

  -- ── LSP: nvim-lspconfig as config data + native vim.lsp.enable ──
  -- Neovim 0.11+ manages servers natively; lspconfig just ships the per-server
  -- defaults. Servers are installed via brew (NOT mason: mason downloads
  -- binaries outside the exec-allowlisted paths and they get killed on the
  -- corp Mac). Each server is enabled only when its binary exists.
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local servers = {
        lua_ls = 'lua-language-server',   -- brew install lua-language-server
        bashls = 'bash-language-server',  -- brew install bash-language-server
        clojure_lsp = 'clojure-lsp',      -- brew install clojure-lsp/brew/clojure-lsp-native
        gopls = 'gopls',                  -- brew install gopls
        dartls = 'dart',                  -- ships with the Dart/Flutter SDK
      }
      for server, binary in pairs(servers) do
        if vim.fn.executable(binary) == 1 then vim.lsp.enable(server) end
      end
      -- Native maps already exist: K hover, grn rename, gra code action,
      -- grr references, gri implementation, [d / ]d diagnostics.
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, { desc = 'Go to definition' })
      vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
    end,
  },

  -- ── Git: gitsigns ──
  -- Change markers in the gutter, hunk navigation/stage/reset, line blame.
  {
    'lewis6991/gitsigns.nvim',
    event = { 'BufReadPre', 'BufNewFile' },
    opts = {
      on_attach = function(bufnr)
        local gs = require('gitsigns')
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end
        map('n', ']h', gs.next_hunk, 'Next hunk')
        map('n', '[h', gs.prev_hunk, 'Prev hunk')
        map('n', '<leader>hs', gs.stage_hunk, 'Stage hunk')
        map('n', '<leader>hr', gs.reset_hunk, 'Reset hunk')
        map('n', '<leader>hp', gs.preview_hunk, 'Preview hunk')
        map('n', '<leader>hb', gs.blame_line, 'Blame line')
      end,
    },
  },

  -- ── Files: oil.nvim ──
  -- Edit the filesystem like a buffer: '-' opens the parent dir, rename/move/
  -- delete by editing lines and :w. Complements yazi (browsing stays there;
  -- oil is for quick in-editor file surgery).
  {
    'stevearc/oil.nvim',
    keys = { { '-', '<cmd>Oil<cr>', desc = 'Open parent directory' } },
    opts = { view_options = { show_hidden = true } },
  },

  -- ── Formatting: conform.nvim ──
  -- On-demand formatting (<leader>f) routed to the right tool per filetype.
  -- Only runs formatters that are actually installed.
  {
    'stevearc/conform.nvim',
    keys = {
      { '<leader>f', function() require('conform').format({ lsp_format = 'fallback' }) end,
        desc = 'Format buffer' },
    },
    opts = {
      formatters_by_ft = {
        dart = { 'dart_format' },
        go = { 'gofmt' },
        json = { 'jq' },
        sh = { 'shfmt' },
      },
    },
  },

  -- ── Discoverability: which-key ──
  -- Pops up the available keymaps after you press <leader> (or any prefix).
  -- The learning tool of this config: shows what exists instead of memorizing.
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {},
  },
}, {
  -- lazy.nvim options: no auto-update checker noise.
  checker = { enabled = false },
  change_detection = { notify = false },
})
