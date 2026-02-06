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
    -- Position: "float" (no cmd) or "bottom" (with cmd)
    position = "float",

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
          local term = require("tiny-term").get()
          if term then
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
          if file ~= "" then
            local term = require("tiny-term").get()
            if term then
              term:hide()
            end
            vim.cmd("e " .. file)
          end
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
