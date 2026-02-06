--- Terminal object and buffer management for tiny-term.nvim
-- Handles terminal lifecycle, buffer management, and window operations

local M = {}

local config = require("tiny-term.config")
local util = require("tiny-term.util")
local window = require("tiny-term.window")

M.terminals = {}

local Terminal = {}
Terminal.__index = Terminal

--- Helper to resolve option with fallback to config
local function opt(option_name, opts)
  local val = opts[option_name]
  if val ~= nil then
    return val
  end
  return config.config[option_name]
end

--- Create a new terminal object
--- @param cmd string|nil Command to run (nil = shell)
--- @param opts table|nil Options table
--- @return TinyTerm.Terminal term Terminal object
function Terminal.new(cmd, opts)
  opts = opts or {}
  local id = util.tid(cmd, opts)

  local interactive = opts.interactive == nil and config.config.interactive ~= false
  if interactive then
    opts.start_insert = opts.start_insert == nil and true or opts.start_insert
    opts.auto_insert = opts.auto_insert == nil and true or opts.auto_insert
    opts.auto_close = opts.auto_close == nil and true or opts.auto_close
  end

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
    esc_count = 0,
    esc_timer = nil,
  }, Terminal)

  return self
end

--- Handle double-esc keypress in terminal mode
--- @return boolean handled True if we should exit to normal mode
function Terminal:handle_double_esc()
  self.esc_count = self.esc_count + 1

  if self.esc_count == 2 then
    if self.esc_timer then
      self.esc_timer:close()
      self.esc_timer = nil
    end
    self.esc_count = 0
    return true
  end

  if not self.esc_timer then
    self.esc_timer = vim.uv.new_timer()
  end
  self.esc_timer:stop()
  self.esc_timer:start(200, 0, function()
    vim.schedule(function()
      if self.job_id and self:buf_valid() then
        vim.api.nvim_chan_send(self.job_id, "\27")
      end
      self.esc_count = 0
    end)
  end)

  return false
end

--- Create the terminal buffer (without starting the process)
--- @return integer buf Buffer ID
function Terminal:create_buffer()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_set_option_value("filetype", "tiny_term", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })

  self.buf = buf

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

  local cmd_list = type(cmd) == "table" and cmd or { "sh", "-c", cmd }

  local job_id = vim.fn.jobstart(cmd_list, {
    cwd = cwd,
    env = self.env,
    term = true,
    on_exit = function(_, exit_code, _)
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
    self.win = window.create_float(opts)
  else
    self.win = window.stack_in_split(self.buf, position, opts)
  end

  self:setup_keymaps()

  return self.win
end

--- Set up keymaps for the terminal window
function Terminal:setup_keymaps()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end

  local keys = window.get_default_keys()
  local is_floating = self:is_floating()

  for _, keymap in ipairs(keys) do
    if keymap[1] == false then
      goto continue
    end

    local mode = keymap.mode or "n"
    local lhs = keymap[1]
    local rhs = keymap[2]

    local is_nav_key = lhs == "<C-h>" or lhs == "<C-j>" or lhs == "<C-k>" or lhs == "<C-l>"
    if is_floating and is_nav_key then
      goto continue
    end

    local opts = {
      desc = keymap.desc,
      buffer = self.buf,
      noremap = true,
      silent = true,
    }

    vim.keymap.set(mode, lhs, rhs, opts)

    ::continue::
  end

  vim.api.nvim_buf_set_keymap(self.buf, "t", "<Esc>", "", {
    callback = function()
      if self:handle_double_esc() then
        vim.cmd("stopinsert")
      else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      end
    end,
    desc = "Double-esc to normal mode",
    noremap = true,
    silent = true,
  })
end

--- Show the terminal window
--- Creates window if needed, reuses existing buffer
--- @return integer win Window ID
function Terminal:show()
  if not self:buf_valid() then
    self:create_buffer()
  end

  if not self:is_visible() then
    self:create_window()
  end

  if not self.process_started then
    vim.api.nvim_win_call(self.win, function()
      self:start_process()
    end)
  end

  if opt("start_insert", self.opts) then
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

  if vim.api.nvim_get_current_win() == self.win then
    vim.cmd("wincmd p")
  end

  pcall(vim.api.nvim_win_close, self.win, true)
  self.win = nil
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

  if self.esc_timer then
    self.esc_timer:close()
    self.esc_timer = nil
  end
  self.esc_count = 0

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
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
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

  if self.esc_timer then
    self.esc_timer:close()
    self.esc_timer = nil
  end

  if self.autocmd_id then
    vim.api.nvim_del_autocmd(self.autocmd_id)
    self.autocmd_id = nil
  end

  self.job_id = nil

  if opt("auto_close", self.opts) then
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
  if self.buf == nil then
    return false
  end
  if self.process_started then
    return true
  end
  return vim.api.nvim_buf_is_valid(self.buf)
end

--- Focus the terminal window
function Terminal:focus()
  if not self:is_visible() then
    return
  end

  vim.api.nvim_set_current_win(self.win)

  if opt("auto_insert", self.opts) then
    vim.cmd("startinsert")
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
