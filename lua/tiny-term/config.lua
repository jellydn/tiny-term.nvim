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

    -- Default keymaps for terminal windows
    keys = {
      -- Navigation keys (only for split windows, skipped in floats)
      { "<C-h>", "<C-w>h", mode = "t", desc = "Move to window left" },
      { "<C-j>", "<C-w>j", mode = "t", desc = "Move to window below" },
      { "<C-k>", "<C-w>k", mode = "t", desc = "Move to window above" },
      { "<C-l>", "<C-w>l", mode = "t", desc = "Move to window right" },

      -- q to hide terminal
      {
        "q",
        function()
          local current_win = vim.api.nvim_get_current_win()
          local ok, term_id = pcall(vim.api.nvim_win_get_var, current_win, "tiny_term_id")
          if not (ok and term_id) then
            return
          end

          local terminal = require("tiny-term.terminal")
          local term = terminal.get(term_id)
          if term and type(term.hide) == "function" then
            term:hide()
          end
        end,
        mode = "n",
        desc = "Hide terminal",
      },

      -- gf to open file under cursor
      {
        "gf",
        function()
          local file = vim.fn.expand("<cfile>")
          if file == "" then
            return
          end

          -- Hide terminal before opening file
          local current_win = vim.api.nvim_get_current_win()
          local ok, term_id = pcall(vim.api.nvim_win_get_var, current_win, "tiny_term_id")
          if ok and term_id then
            local terminal = require("tiny-term.terminal")
            local term = terminal.get(term_id)
            if term and type(term.hide) == "function" then
              term:hide()
            end
          end

          vim.cmd("e " .. file)
        end,
        mode = "n",
        desc = "Open file under cursor",
      },
    },
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

-- Current configuration (set by setup())
M.config = {}

---Setup tiny-term with user options
---@param opts? table User configuration options
function M.setup(opts)
  -- Merge user config with defaults (user opts take precedence)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  -- Ensure shell is set to vim.o.shell if not explicitly provided
  if not (opts and opts.shell) then
    M.config.shell = vim.o.shell
  end

  return M.config
end

return M
