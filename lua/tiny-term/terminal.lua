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
    exited = false,
    autocmd_id = nil,
    keymap_ids = {},
    -- Per-terminal double-esc state
    esc_state = {
      timer = nil,
      count = 0,
      delay_ms = 200,
    },
  }, Terminal)

  return self
end

--- Clean up the double-esc timer for this terminal
function Terminal:cleanup_esc_timer()
  if self.esc_state.timer then
    self.esc_state.timer:close()
    self.esc_state.timer = nil
  end
  self.esc_state.count = 0
end

--- Handle double-esc keypress in terminal mode
--- @return boolean handled True if we should exit to normal mode
function Terminal:handle_double_esc()
  self.esc_state.count = self.esc_state.count + 1

  if self.esc_state.count == 2 then
    -- Double esc detected - exit to normal mode
    self:cleanup_esc_timer()
    return true
  end

  -- First esc - start timer
  if self.esc_state.timer then
    self.esc_state.timer:stop()
  else
    self.esc_state.timer = vim.uv.new_timer()
  end

  -- Timer callback wrapped in vim.schedule for proper event loop handling
  self.esc_state.timer:start(self.esc_state.delay_ms, 0, function()
    vim.schedule(function()
      -- Timer expired - single esc, send ESC to terminal via channel
      if self.job_id and self:buf_valid() then
        -- Send ESC character (\27) to the terminal's channel
        local chan = vim.fn.jobwait(self.job_id, 0)[1] or self.job_id
        vim.api.nvim_chan_send(chan, "\27")
      end
      self.esc_state.count = 0
    end)
  end)

  -- First esc - don't send anything yet, wait for timer
  return false
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
  local cmd = self.cmd or config.config.shell
  local cwd = self.cwd or vim.fn.getcwd()

  -- Use jobstart with term flag for Neovim 0.11+
  -- Build command as list for jobstart
  local cmd_list = type(cmd) == "table" and cmd or { "sh", "-c", cmd }

  local job_id = vim.fn.jobstart(cmd_list, {
    cwd = cwd,
    env = self.env,
    term = true,  -- Run in a terminal emulation
    on_exit = function(_, exit_code, _)
      -- Clean up when process exits
      self:handle_exit()
    end,
  })

  if job_id == 0 then
    error("Failed to start terminal (invalid arguments): " .. tostring(cmd))
  elseif job_id == -1 then
    error("Failed to start terminal (not executable): " .. tostring(cmd))
  end

  self.job_id = job_id
  self.exited = false
  self.process_started = true
end

--- Create a window for the terminal
--- @return integer win Window ID
function Terminal:create_window()
  local opts = vim.tbl_deep_extend("force", self.opts, {
    buf = self.buf,
    cmd = self.cmd,
    term = self,
  })
  local position = window.get_window_position(opts)

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

    -- Note: vim.keymap.set returns nil, so we don't store it
    vim.keymap.set(mode, lhs, rhs, opts)

    ::continue::
  end

  -- Set up double-esc to normal mode in terminal mode
  -- This is a special keymap that handles the double-esc detection
  local esc_keymap_id = vim.api.nvim_buf_set_keymap(self.buf, "t", "<Esc>", "", {
    callback = function()
      if self:handle_double_esc() then
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
    -- Use nvim_win_call to start process in the terminal window's context
    -- This avoids focus flicker by not actually switching windows
    vim.api.nvim_win_call(self.win, function()
      self:start_process()
    end)
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

--- Hide the terminal window (closes window, keeps buffer/process alive)
function Terminal:hide()
  if not self:is_visible() then
    return
  end

  local win = self.win
  self.win = nil

  if vim.api.nvim_get_current_win() == win then
    vim.cmd("wincmd p")
  end

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
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

--- Close the terminal (kills process, deletes buffer)
function Terminal:close()
  self.exited = true

  -- Clean up the double-esc timer
  self:cleanup_esc_timer()

  if self.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self.autocmd_id)
    self.autocmd_id = nil
  end

  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end

  self:hide()

  if self:buf_valid() then
    vim.api.nvim_buf_delete(self.buf, { force = true })
    self.buf = nil
  end

  M.terminals[self.id] = nil
end

--- Handle terminal process exit (called by TermClose autocmd)
function Terminal:handle_exit()
  if self.exited then
    return
  end
  self.exited = true

  -- Clean up the double-esc timer
  self:cleanup_esc_timer()

  if self.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, self.autocmd_id)
    self.autocmd_id = nil
  end

  self.job_id = nil

  local auto_close = self.opts.auto_close
  if auto_close == nil then
    auto_close = config.config.auto_close
  end

  if auto_close then
    vim.schedule(function()
      self:hide()

      if self:buf_valid() then
        vim.api.nvim_buf_delete(self.buf, { force = true })
        self.buf = nil
      end

      M.terminals[self.id] = nil
    end)
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

  local id = util.tid(cmd, opts)

  local existing = M.terminals[id]
  if existing and not existing.exited then
    return existing
  end

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
