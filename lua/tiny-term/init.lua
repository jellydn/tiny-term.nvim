-- tiny-term.nvim - Minimal terminal toggle plugin for Neovim 0.11+
-- API-compatible drop-in replacement for Snacks.terminal

local M = {}

-- Import configuration module
local config = require("tiny-term.config")

-- Expose config to users
M.config = config.config

---Set up highlight groups for tiny-term
local function setup_highlights()
  -- Link to existing highlights by default for consistency
  vim.api.nvim_set_hl(0, "TinyTermNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "TinyTermBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "TinyTermWinbar", { link = "WinBar", default = true })
end

---Setup tiny-term with user options
---@param opts? table User configuration options
function M.setup(opts)
  opts = opts or {}

  -- Store override_snacks flag before merging
  local override_snacks = opts.override_snacks

  local merged = config.setup(opts)
  M.config = merged

  -- Set up highlight groups
  setup_highlights()

  -- Auto-override Snacks.terminal if requested
  if override_snacks then
    M.override_snacks()
  end

  return M
end

-- Import modules
local terminal = require("tiny-term.terminal")
local util = require("tiny-term.util")

--- Get or create a terminal by ID
--- Matches Snacks.terminal.get() API signature
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal|nil term Terminal object or nil
--- @return boolean created True if a new terminal was created
function M.get(cmd, opts)
  opts = opts or {}

  local id = util.tid(cmd, opts)

  local existing = terminal.get(id)
  if existing and not existing.exited then
    return existing, false
  end

  if opts.create == false then
    return nil, nil
  end

  local term = terminal.get_or_create(cmd, opts)
  return term, true
end

--- List all active terminals
--- Matches Snacks.terminal.list() API signature
--- @return TinyTerm.Terminal[] terms Array of terminal objects
function M.list()
  return terminal.list()
end

--- Toggle terminal visibility
--- If terminal is visible, hide it. If hidden, show it.
--- Matches Snacks.terminal.toggle() API signature
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal|nil term Terminal object or nil
function M.toggle(cmd, opts)
  opts = opts or {}

  -- Get or create the terminal
  local term = terminal.get_or_create(cmd, opts)

  -- Toggle visibility
  if term:is_visible() then
    term:hide()
  else
    term:show()

    -- Handle auto_insert option when showing
    local auto_insert = opts.auto_insert
    if auto_insert == nil then
      auto_insert = config.config.auto_insert
    end

    if auto_insert then
      vim.api.nvim_set_current_win(term.win)
      vim.cmd("startinsert")
    end
  end

  return term
end

--- Open a new terminal (always creates/shows window)
--- Similar to toggle but always creates a new terminal window
--- Matches Snacks.terminal.open() API signature
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal term Terminal object
function M.open(cmd, opts)
  opts = opts or {}

  -- Get or create the terminal and show it
  local term = terminal.get_or_create(cmd, opts)
  term:show()

  return term
end

--- Generate a terminal ID
--- @param cmd string|nil Command to run
--- @param opts table|nil Options table
--- @return string id Terminal ID
function M.tid(cmd, opts)
  return util.tid(cmd, opts)
end

--- Parse a shell command into a table of arguments
---
--- Handles spaces inside quotes (double quotes only) and backslash escapes.
--- Compatible with Snacks.terminal.parse() for API compatibility.
--- @param cmd string|string[] Command to parse
--- @return string[] args Parsed arguments list
function M.parse(cmd)
  return util.parse(cmd)
end

--- Colorize the current buffer with ANSI color codes
---
--- Replaces ANSI codes with actual Neovim highlights using terminal buffer.
--- Useful for viewing colorized command output in Neovim.
---
--- Usage example:
--- ```bash
--- ls -la --color=always | nvim - -c "lua require('tiny-term').colorize()"
--- ```
function M.colorize()
  -- Disable UI elements for cleaner display
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.statuscolumn = ""
  vim.wo.signcolumn = "no"
  vim.opt.listchars = { space = " " }

  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Remove trailing empty lines
  while #lines > 0 and vim.trim(lines[#lines]) == "" do
    lines[#lines] = nil
  end

  -- Clear buffer and open terminal
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  local chan = vim.api.nvim_open_term(buf, {})
  vim.api.nvim_chan_send(chan, table.concat(lines, "\r\n"))

  -- Set up keymap to quit
  vim.keymap.set("n", "q", "q", { silent = true, buffer = buf })

  -- Auto-scroll to end on changes
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = buf,
    callback = function()
      pcall(vim.api.nvim_win_set_cursor, 0, { #lines, 0 })
    end,
  })

  vim.api.nvim_create_autocmd("TermEnter", { buffer = buf, command = "stopinsert" })
end

--- Override Snacks.terminal with tiny-term for zero-change compatibility
---
--- Call this after both snacks.nvim and tiny-term.nvim are loaded.
--- This allows existing code using Snacks.terminal to use tiny-term instead.
---
--- Usage:
--- ```lua
--- -- Option 1: Auto-override in setup
--- require("tiny-term").setup({ override_snacks = true })
---
--- -- Option 2: Manual override
--- require("tiny-term").override_snacks()
---
--- -- Option 3: Direct assignment
--- Snacks.terminal = require("tiny-term")
--- ```
--- @return table self Returns tiny-term module for chaining
function M.override_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    vim.notify("tiny-term.nvim: snacks.nvim not found, skipping override", vim.log.levels.INFO)
    return M
  end

  snacks.terminal = M
  vim.notify("tiny-term.nvim: Snacks.terminal overridden", vim.log.levels.INFO)

  return M
end

-- Module __call metatable: M(cmd, opts) -> M.toggle(cmd, opts)
-- This allows require("tiny-term")(cmd, opts) to work
setmetatable(M, {
  __call = function(_, cmd, opts)
    return M.toggle(cmd, opts)
  end,
})

return M
