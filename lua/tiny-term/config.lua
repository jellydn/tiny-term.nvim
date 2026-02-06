-- Configuration system for tiny-term.nvim
-- Based on Snacks.terminal API for compatibility

local M = {}

-- Default configuration
---@class TinyTerm.Config
---@field shell string Shell command to use
---@field win table Window configuration
---@field start_insert boolean Start in insert mode
---@field auto_insert boolean Enter insert mode on toggle
---@field auto_close boolean Close window on process exit
local defaults = {
  -- Shell to use for terminals
  shell = vim.o.shell,

  -- Window configuration
  win = {
    -- Position: "float", "bottom", "top", "left", "right"
    -- Default: auto (cmd provided -> "float", no cmd -> "bottom")

    -- Float window size (as fraction of editor)
    width = 0.8,
    height = 0.8,

    -- Border style (nil uses 'winborder' option from Neovim 0.11)
    border = nil,

    -- Split size in rows/columns
    split_size = 15,

    -- Enable split stacking (tmux-like behavior)
    stack = true,

    -- Keymaps for terminal windows (nil uses defaults)
    keys = nil,
  },

  -- Behavior options
  start_insert = true,
  auto_insert = true,
  auto_close = true,

  -- Interactive mode: shortcut for start_insert, auto_insert, and auto_close
  -- When false, disables all three options (default: true)
  -- Matches Snacks.terminal API
  interactive = true,

  -- Auto-override Snacks.terminal with tiny-term for zero-change compatibility
  -- When true, automatically replaces Snacks.terminal with tiny-term
  override_snacks = false,
}

-- Current configuration (initialized with defaults)
M.config = vim.deepcopy(defaults)

---Setup tiny-term with user options
---@param opts? table User configuration options
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
  return M.config
end

return M
