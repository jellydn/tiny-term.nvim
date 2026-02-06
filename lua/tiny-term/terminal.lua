--- Terminal object and buffer management for tiny-term.nvim
-- Handles terminal lifecycle, buffer management, and window operations

local M = {}

-- Dependencies
local config = require("tiny-term.config")
local util = require("tiny-term.util")
local window = require("tiny-term.window")

-- Track all active terminals indexed by terminal ID (tid)
---@type table<string, TinyTerm.Terminal>
M.terminals = {}

--- Terminal object metatable
local Terminal = {}
Terminal.__index = Terminal

-- Double-esc state tracking for all terminals
local esc_state = {
  timer = nil,
  count = 0,
  delay_ms = 200,
}

--- Clean up the double-esc timer
local function cleanup_esc_timer()
  if esc_state.timer then
    esc_state.timer:close()
    esc_state.timer = nil
  end
  esc_state.count = 0
end

--- Handle double-esc keypress in terminal mode
--- @return boolean handled True if we should exit to normal mode
local function handle_double_esc()
  esc_state.count = esc_state.count + 1

  if esc_state.count == 2 then
    -- Double esc detected - exit to normal mode
    cleanup_esc_timer()
    return true
  end

  -- First esc - start timer
  if esc_state.timer then
    esc_state.timer:stop()
  else
    esc_state.timer = vim.uv.new_timer()
  end

  esc_state.timer:start(esc_state.delay_ms, 0, function()
    -- Timer expired - single esc, let it pass through
    esc_state.count = 0
  end)

  -- First esc - return false to let it pass through
  return false
end

--- Create a new terminal object
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal term Terminal object
function Terminal.new(cmd, opts)
  opts = opts or {}

  -- Generate terminal ID
  local id = util.tid(cmd, opts)

  -- Handle interactive option (shortcut for start_insert, auto_insert, auto_close)
  local interactive = opts.interactive
  if interactive == nil then
    interactive = config.config.interactive
  end
  if interactive ~= false then
    -- When interactive is true (default), set the three options if not explicitly provided
    opts.start_insert = opts.start_insert ~= nil and opts.start_insert or true
    opts.auto_insert = opts.auto_insert ~= nil and opts.auto_insert or true
    opts.auto_close = opts.auto_close ~= nil and opts.auto_close or true
  end

  -- Create terminal object
  local self = setmetatable({
    id = id,
    cmd = cmd,
    opts = opts,
    buf = nil,
    win = nil,
    cwd = opts.cwd or vim.fn.getcwd(),
    env = opts.env,
    job_id = nil,
    autocmd_id = nil, -- Track TermClose autocmd for cleanup
    keymap_ids = {}, -- Track keymap IDs for cleanup
  }, Terminal)

  return self
end

--- Create the terminal buffer (without starting the process)
--- @return integer buf Buffer ID
function Terminal:create_buffer()
  -- Create a new buffer (unlisted, scratch)
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options for terminal
  vim.api.nvim_set_option_value("filetype", "tiny_term", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf }) -- Keep buffer when window closes

  -- Store buffer reference
  self.buf = buf

  -- Set up TermClose autocmd for auto-close functionality
  -- This autocmd fires when the terminal process exits
  local autocmd_id = vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    callback = function()
      self:handle_exit()
    end,
  })
  self.autocmd_id = autocmd_id

  return buf
end

--- Start the terminal process in the buffer
--- Must be called when the buffer is the current buffer
function Terminal:start_process()
  local buf = self.buf

  -- Build command for terminal
  local cmd = self.cmd or config.config.shell
  local cwd = self.cwd or vim.fn.getcwd()

  -- Build environment for terminal
  local env = self.env
  if env then
    -- Convert env table to format expected by termopen
    local env_list = {}
    for k, v in pairs(env) do
      table.insert(env_list, k .. "=" .. tostring(v))
    end
    env = env_list
  end

  -- Change to working directory before starting terminal
  vim.fn.chdir(cwd)

  -- Start terminal process
  -- termopen returns job_id on success, 0 on failure
  local job_id = vim.fn.termopen(cmd, {
    cwd = cwd,
    env = env,
    on_exit = function(_, exit_code, _)
      -- Clean up when process exits
      self:handle_exit()
    end,
  })

  if job_id == 0 then
    error("Failed to start terminal: " .. tostring(cmd))
  end

  self.job_id = job_id
  self.process_started = true
end

--- Create a window for the terminal
--- @return integer win Window ID
function Terminal:create_window()
  local position = window.get_window_position(self.opts)

  -- Pass buffer and terminal to window creation function
  local opts = vim.tbl_deep_extend("force", self.opts, {
    buf = self.buf,
    term = self, -- Pass terminal reference for winbar
  })

  if position == "float" then
    -- Floating windows are never stacked
    self.win = window.create_float(opts)
  else
    -- Split windows use stacking (reuse existing split at same position)
    self.win = window.stack_in_split(self.buf, position, opts)
  end

  -- Set up keymaps for the window
  self:setup_keymaps()

  return self.win
end

--- Set up keymaps for the terminal window
function Terminal:setup_keymaps()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end

  local keys = config.config.win.keys or {}
  local is_floating = self:is_floating()

  -- Clear existing keymaps for this buffer
  self:clear_keymaps()

  -- Set buffer-local keymaps
  for _, keymap in ipairs(keys) do
    -- Check if keymap is disabled
    if keymap[1] == false then
      goto continue
    end

    local mode = keymap.mode or "n"
    local lhs = keymap[1]
    local rhs = keymap[2]

    -- Special handling for navigation keys in floating windows
    if is_floating and (lhs == "<C-h>" or lhs == "<C-j>" or lhs == "<C-k>" or lhs == "<C-l>") then
      -- Skip navigation keymaps in floating windows - let them pass through
      goto continue
    end

    local opts = {
      desc = keymap.desc,
      buffer = self.buf,
      noremap = true,
      silent = true,
    }

    -- Store keymap ID for cleanup
    local keymap_id = vim.keymap.set(mode, lhs, rhs, opts)
    table.insert(self.keymap_ids, keymap_id)

    ::continue::
  end

  -- Set up double-esc to normal mode in terminal mode
  -- This is a special keymap that handles the double-esc detection
  local esc_keymap_id = vim.api.nvim_buf_set_keymap(self.buf, "t", "<Esc>", "", {
    callback = function()
      if handle_double_esc() then
        -- Double esc detected - exit to normal mode
        vim.cmd("stopinsert")
      else
        -- Single esc - feed it to the terminal
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      end
    end,
    desc = "Double-esc to normal mode",
    noremap = true,
    silent = true,
  })
  table.insert(self.keymap_ids, esc_keymap_id)
end

--- Clear keymaps for the terminal buffer
function Terminal:clear_keymaps()
  -- Note: vim.keymap.set doesn't return an ID that can be used for deletion
  -- So we clear all buffer-local keymaps and re-apply them
  -- This is a limitation of Neovim's keymap API
  self.keymap_ids = {}
end

--- Show the terminal window
--- Creates window if needed, reuses existing buffer
--- @return integer win Window ID
function Terminal:show()
  -- Create buffer if it doesn't exist
  if not self:buf_valid() then
    self:create_buffer()
  end

  -- Create window if it doesn't exist or is invalid
  if not self:is_visible() then
    self:create_window()
  end

  -- Start the terminal process if not already started
  if not self.process_started then
    -- Switch to the terminal window and start the process
    local current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(self.win)
    self:start_process()
    vim.api.nvim_set_current_win(current_win)
  end

  -- Handle start_insert option
  local start_insert = self.opts.start_insert
  if start_insert == nil then
    start_insert = config.config.start_insert
  end

  if start_insert then
    -- Start insert mode in terminal
    vim.api.nvim_set_current_win(self.win)
    vim.cmd("startinsert")
  end

  return self.win
end

--- Hide the terminal window
--- For split windows, this hides the window but keeps it available for stacking
--- For floating windows, this closes the window
function Terminal:hide()
  if self:is_visible() then
    local position = window.get_window_position(self.opts)

    if position == "float" then
      -- Close floating windows (they're never stacked)
      vim.api.nvim_win_close(self.win, true)
    else
      -- For split windows, just switch away but keep window
      -- Don't close it as other terminals may be stacked here
      local current_win = vim.api.nvim_get_current_win()
      if current_win == self.win then
        -- Switch to previous window
        vim.cmd("wincmd p")
      end
    end

    self.win = nil
  end
end

--- Toggle terminal visibility
function Terminal:toggle()
  if self:is_visible() then
    self:hide()
  else
    self:show()
  end
end

--- Close the terminal
--- Kills process and deletes buffer
function Terminal:close()
  -- Clear the TermClose autocmd first to prevent double-cleanup
  if self.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self.autocmd_id)
    self.autocmd_id = nil
  end

  -- Kill the job if it's still running
  if self.job_id then
    vim.fn.jobstop(self.job_id)
    self.job_id = nil
  end

  -- Close window if open
  if self:is_visible() then
    local position = window.get_window_position(self.opts)
    if position == "float" then
      vim.api.nvim_win_close(self.win, true)
    else
      -- For split windows, switch away first
      local current_win = vim.api.nvim_get_current_win()
      if current_win == self.win then
        vim.cmd("wincmd p")
      end
      -- Then close the window
      vim.api.nvim_win_close(self.win, true)
    end
    self.win = nil
  end

  -- Delete buffer if valid
  if self:buf_valid() then
    vim.api.nvim_buf_delete(self.buf, { force = true })
    self.buf = nil
  end

  -- Remove from terminals table
  M.terminals[self.id] = nil
end

--- Handle terminal process exit (called by TermClose autocmd)
--- Auto-closes window if configured, otherwise just cleans up
function Terminal:handle_exit()
  -- Clean up autocmd
  if self.autocmd_id then
    vim.api.nvim_del_autocmd(self.autocmd_id)
    self.autocmd_id = nil
  end

  -- Clear job ID
  self.job_id = nil

  -- Handle auto_close option
  local auto_close = self.opts.auto_close
  if auto_close == nil then
    auto_close = config.config.auto_close
  end

  if auto_close then
    -- Close window if configured
    if self.win and vim.api.nvim_win_is_valid(self.win) then
      local position = window.get_window_position(self.opts)

      if position == "float" then
        -- Close floating windows
        vim.api.nvim_win_close(self.win, true)
      else
        -- For split windows, switch away but keep window
        -- Don't close it as other terminals may be stacked here
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.win then
          vim.cmd("wincmd p")
        end
      end

      self.win = nil
    end

    -- Delete buffer
    if self:buf_valid() then
      vim.api.nvim_buf_delete(self.buf, { force = true })
      self.buf = nil
    end

    -- Remove from terminals table
    M.terminals[self.id] = nil
  end
end

--- Check if the terminal window is floating
--- @return boolean is_floating True if window is floating
function Terminal:is_floating()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return false
  end
  return window.is_floating(self.win)
end

--- Check if the terminal window is visible
--- @return boolean is_visible True if window is valid and visible
function Terminal:is_visible()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return false
  end

  -- Check if window is in the current tabpage
  local current_tab = vim.api.nvim_get_current_tabpage()
  local win_tab = vim.api.nvim_win_get_tabpage(self.win)

  return win_tab == current_tab
end

--- Check if the terminal window is on the current tabpage
--- Alias for is_visible() - matches Snacks.terminal API
--- @return boolean on_current_tab True if window is on current tabpage
function Terminal:on_current_tab()
  return self:is_visible()
end

--- Check if the terminal buffer is valid
--- @return boolean is_valid True if buffer is still valid
function Terminal:buf_valid()
  return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

--- Focus the terminal window
function Terminal:focus()
  if self:is_visible() then
    vim.api.nvim_set_current_win(self.win)

    -- Handle auto_insert option
    local auto_insert = self.opts.auto_insert
    if auto_insert == nil then
      auto_insert = config.config.auto_insert
    end

    if auto_insert then
      vim.cmd("startinsert")
    end
  end
end

--- Get or create a terminal for the given command and options
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal term Terminal object
function M.get_or_create(cmd, opts)
  opts = opts or {}

  -- Generate terminal ID to check if terminal already exists
  local id = util.tid(cmd, opts)

  -- Return existing terminal if found and buffer is valid
  local existing = M.terminals[id]
  if existing and existing:buf_valid() then
    return existing
  end

  -- Create new terminal
  local term = Terminal.new(cmd, opts)
  M.terminals[id] = term

  return term
end

--- List all active terminals
--- @return table terminals Table of terminal objects
function M.list()
  local active = {}
  for id, term in pairs(M.terminals) do
    if term:buf_valid() then
      table.insert(active, term)
    end
  end
  return active
end

--- Get a terminal by ID
--- @param id string Terminal ID
--- @return TinyTerm.Terminal|nil term Terminal object or nil
function M.get(id)
  return M.terminals[id]
end

--- Close all terminals
function M.close_all()
  for id, term in pairs(M.terminals) do
    if term:buf_valid() then
      term:close()
    end
  end
  M.terminals = {}
end

return M
