-- tiny-term.nvim - Minimal terminal toggle plugin for Neovim 0.11+
-- API-compatible drop-in replacement for Snacks.terminal

local M = {}

-- Import configuration module
local config = require("tiny-term.config")

-- Expose config to users
M.config = config.config

---Setup tiny-term with user options
---@param opts? table User configuration options
function M.setup(opts)
  local merged = config.setup(opts)
  M.config = merged

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

  -- Generate terminal ID
  local id = util.tid(cmd, opts)

  -- Check if terminal already exists
  local existing = terminal.get(id)
  if existing and existing:buf_valid() then
    return existing, false
  end

  -- Handle opts.create option (default true)
  local should_create = opts.create ~= false

  if not should_create then
    return nil, nil
  end

  -- Create new terminal
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

-- Module __call metatable: M(cmd, opts) -> M.toggle(cmd, opts)
-- This allows require("tiny-term")(cmd, opts) to work
setmetatable(M, {
  __call = function(_, cmd, opts)
    return M.toggle(cmd, opts)
  end,
})

return M
