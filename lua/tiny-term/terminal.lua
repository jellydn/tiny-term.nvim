local M = {}

local config = require("tiny-term.config")
local util = require("tiny-term.util")
local window = require("tiny-term.window")

M.terminals = {}

local Terminal = {}
Terminal.__index = Terminal

---@param cmd string|nil
---@param opts table|nil
---@return TinyTerm.Terminal
function Terminal.new(cmd, opts)
  opts = opts or {}
  local id = util.tid(cmd, opts)

  local interactive = opts.interactive == nil and config.config.interactive ~= false
  if interactive then
    opts.start_insert = opts.start_insert ~= false
    opts.auto_insert = opts.auto_insert ~= false
    opts.auto_close = opts.auto_close ~= false
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

local function _refresh_splits_if_needed(term)
  if not term.win then
    return
  end

  local win_id = term.win
  window.unregister_terminal_from_split(win_id, term.id)
  local remaining = window.get_split_terminals(win_id)
  if #remaining == 0 then
    return
  end

  local next_term = M.get(remaining[1])
  if not next_term then
    return
  end

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win_id) then
      window.switch_to_terminal(win_id, remaining[1])
    end
  end)
end

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

function Terminal:start_process()
  local cmd = self.cmd or config.config.shell
  local cwd = self.cwd or vim.fn.getcwd()

  local cmd_list
  if type(cmd) == "table" then
    cmd_list = cmd
  else
    local shell = config.config.shell
    local shellcmdflag = vim.o.shellcmdflag or "-c"
    cmd_list = { shell, shellcmdflag, cmd }
  end

  local job_id = vim.fn.jobstart(cmd_list, {
    cwd = cwd,
    env = self.env,
    term = true,
    on_exit = function()
      self.exited = true
      self.job_id = nil
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

function Terminal:create_window()
  local opts = vim.tbl_deep_extend("force", self.opts or {}, {
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

function Terminal:setup_keymaps()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return
  end

  local opts = self.opts or {}
  local keys = (opts.win or {}).keys or config.config.win.keys or window.get_default_keys()
  local nav_keys = { ["<C-h>"] = true, ["<C-j>"] = true, ["<C-k>"] = true, ["<C-l>"] = true }

  for _, keymap in ipairs(keys) do
    if keymap[1] ~= false then
      if not (self:is_floating() and nav_keys[keymap[1]]) then
        vim.keymap.set(keymap.mode or "n", keymap[1], keymap[2], {
          desc = keymap.desc,
          buffer = self.buf,
          noremap = true,
          silent = true,
        })
      end
    end
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

  local opts = self.opts or {}
  local start_insert = opts.start_insert
  if start_insert == nil then
    start_insert = config.config.start_insert
  end
  if start_insert then
    vim.api.nvim_set_current_win(self.win)
    vim.cmd("startinsert")
  end

  return self.win
end

function Terminal:hide()
  if not self:is_visible() then
    return
  end

  _refresh_splits_if_needed(self)

  if vim.api.nvim_get_current_win() == self.win then
    vim.cmd("wincmd p")
  end

  pcall(vim.api.nvim_win_close, self.win, true)
  self.win = nil
end

function Terminal:toggle()
  if self:is_visible() then
    self:hide()
  else
    self:show()
  end
end

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

  _refresh_splits_if_needed(self)

  self:hide()

  if self:buf_valid() then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    self.buf = nil
  end

  M.terminals[self.id] = nil
end

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

  local opts = self.opts or {}
  local auto_close = opts.auto_close
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

function Terminal:is_floating()
  return self.win and vim.api.nvim_win_is_valid(self.win) and window.is_floating(self.win)
end

function Terminal:is_visible()
  if not self.win or not vim.api.nvim_win_is_valid(self.win) then
    return false
  end

  return vim.api.nvim_win_get_tabpage(self.win) == vim.api.nvim_get_current_tabpage()
end

function Terminal:on_current_tab()
  return self:is_visible()
end

function Terminal:buf_valid()
  return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

function Terminal:focus()
  if not self:is_visible() then
    return
  end

  vim.api.nvim_set_current_win(self.win)

  local opts = self.opts or {}
  local auto_insert = opts.auto_insert
  if auto_insert == nil then
    auto_insert = config.config.auto_insert
  end
  if auto_insert then
    vim.cmd("startinsert")
  end
end

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

function M.create_new(cmd, opts)
  opts = opts or {}

  local base_id = util.tid(cmd, opts)
  -- Use a counter for uniqueness instead of random numbers
  local counter = M._create_counter or 0
  M._create_counter = counter + 1
  local unique_id = base_id .. "|" .. tostring(os.time()) .. "|" .. tostring(counter)

  local term = Terminal.new(cmd, opts)
  term.id = unique_id
  M.terminals[unique_id] = term

  return term
end

function M.list()
  local active = {}
  for id, term in pairs(M.terminals) do
    if term:buf_valid() then
      table.insert(active, term)
    end
  end
  return active
end

function M.get(id)
  return M.terminals[id]
end

function M.close_all()
  for id, term in pairs(M.terminals) do
    if term:buf_valid() then
      term:close()
    end
  end
  M.terminals = {}
end

return M
