local M = {}

local default_keys = {
  { "<C-h>", "<C-w>h", mode = "t", desc = "Move to window left" },
  { "<C-j>", "<C-w>j", mode = "t", desc = "Move to window below" },
  { "<C-k>", "<C-w>k", mode = "t", desc = "Move to window above" },
  { "<C-l>", "<C-w>l", mode = "t", desc = "Move to window right" },
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
      if term then
        term:hide()
      end
    end,
    mode = "n",
    desc = "Hide terminal",
  },
  {
    "gf",
    function()
      local file = vim.fn.expand("<cfile>")
      if file == "" then
        return
      end
      local current_win = vim.api.nvim_get_current_win()
      local ok, term_id = pcall(vim.api.nvim_win_get_var, current_win, "tiny_term_id")
      if ok and term_id then
        local terminal = require("tiny-term.terminal")
        local term = terminal.get(term_id)
        if term then
          term:hide()
        end
      end
      vim.cmd("e " .. file)
    end,
    mode = "n",
    desc = "Open file under cursor",
  },
}

function M.get_default_keys()
  return default_keys
end

local split_windows = {}
local split_terminals = {}
local split_active_term = {}

function M.get_window_position(opts)
  local win_opts = opts.win or {}
  local position = win_opts.position

  if not position then
    position = opts.cmd and "float" or "bottom"
  end

  return position
end

function M.create_float(opts)
  local win_opts = opts.win or {}
  local width = win_opts.width or 0.8
  local height = win_opts.height or 0.8

  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  local win_width = math.floor(editor_width * width)
  local win_height = math.floor(editor_height * height)
  local row = math.floor((editor_height - win_height) / 2)
  local col = math.floor((editor_width - win_width) / 2)

  local border = win_opts.border
  local config = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = border,
    mouse = true,
  }

  local buf = opts.buf or vim.api.nvim_create_buf(false, true)
  if not buf or buf == 0 then
    error("Failed to create terminal buffer")
  end

  local win_id = vim.api.nvim_open_win(buf, true, config)
  if not win_id or win_id == 0 then
    error("Failed to create floating window")
  end
  if not vim.api.nvim_win_is_valid(win_id) then
    error("Window became invalid immediately after creation")
  end
  vim.api.nvim_set_option_value("wrap", false, { win = win_id })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win_id })
  vim.api.nvim_set_option_value(
    "winhighlight",
    "NormalFloat:TinyTermNormal,FloatBorder:TinyTermBorder",
    { win = win_id }
  )

  -- Store terminal ID on window for keymap access
  if opts.term then
    pcall(vim.api.nvim_win_set_var, win_id, "tiny_term_id", opts.term.id)
  end

  return win_id
end

local function split_at(position, split_size)
  local split_cmd
  if position == "bottom" or position == nil then
    split_cmd = "botright " .. split_size .. "split"
  elseif position == "top" then
    split_cmd = "topleft " .. split_size .. "split"
  elseif position == "right" then
    split_cmd = "botright vertical " .. split_size .. "split"
  elseif position == "left" then
    split_cmd = "topleft vertical " .. split_size .. "split"
  end
  vim.cmd(split_cmd)
end

function M.create_split(opts)
  local win_opts = opts.win or {}
  local position = M.get_window_position(opts)
  local split_size = win_opts.split_size or 15
  local current_win = vim.api.nvim_get_current_win()

  split_at(position, split_size)
  local win_id = vim.api.nvim_get_current_win()

  if opts.buf then
    vim.api.nvim_win_set_buf(win_id, opts.buf)
  end
  if opts.term then
    pcall(vim.api.nvim_win_set_var, win_id, "tiny_term_id", opts.term.id)
  end
  vim.api.nvim_set_option_value("winhighlight", "Normal:TinyTermNormal,FloatBorder:TinyTermBorder", { win = win_id })

  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

  return win_id
end

function M.is_floating(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return false
  end

  local config = vim.api.nvim_win_get_config(win_id)
  return config.relative ~= nil and config.relative ~= ""
end

function M.create_window(opts)
  local position = M.get_window_position(opts)

  if position == "float" then
    return M.create_float(opts)
  else
    return M.create_split(opts)
  end
end

function M.register_split(position, win_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local tabpage = vim.api.nvim_win_get_tabpage(win_id)
  if not split_windows[tabpage] then
    split_windows[tabpage] = {}
  end
  split_windows[tabpage][position] = win_id

  if not split_terminals[win_id] then
    split_terminals[win_id] = {}
  end
end

function M.register_terminal_in_split(win_id, term_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  if not split_terminals[win_id] then
    split_terminals[win_id] = {}
  end

  for _, id in ipairs(split_terminals[win_id]) do
    if id == term_id then
      split_active_term[win_id] = term_id
      return
    end
  end

  table.insert(split_terminals[win_id], term_id)
  split_active_term[win_id] = term_id
end

function M.unregister_terminal_from_split(win_id, term_id)
  if not split_terminals[win_id] then
    return
  end

  local terms = split_terminals[win_id]
  for i, id in ipairs(terms) do
    if id == term_id then
      table.remove(terms, i)
      break
    end
  end

  if split_active_term[win_id] == term_id then
    split_active_term[win_id] = terms[1]
  end

  if #terms == 0 then
    split_terminals[win_id] = nil
    split_active_term[win_id] = nil
  end
end

function M.get_split_terminals(win_id)
  return split_terminals[win_id] or {}
end

function M.switch_to_terminal(win_id, term_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local terminal = require("tiny-term.terminal")
  local term = terminal.get(term_id)
  if not term or not term.buf then
    return
  end

  term.win = win_id
  vim.api.nvim_win_set_buf(win_id, term.buf)
  split_active_term[win_id] = term_id
  configure_terminal_window(win_id, { term = term })
  vim.api.nvim_set_current_win(win_id)
  if term.focus then
    term:focus()
  end
end

function M.get_split(position)
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tab_windows = split_windows[current_tab]
  if not tab_windows then
    return nil
  end

  local win_id = tab_windows[position]

  if win_id and vim.api.nvim_win_is_valid(win_id) then
    if not M.is_floating(win_id) then
      return win_id
    end
  end

  tab_windows[position] = nil
  return nil
end

function configure_terminal_window(win_id, opts)
  if not opts.term then
    return
  end

  pcall(vim.api.nvim_win_set_var, win_id, "tiny_term_id", opts.term.id)
  M.register_terminal_in_split(win_id, opts.term.id)
  local terms = M.get_split_terminals(win_id)
  local active_term_id = split_active_term[win_id] or opts.term.id

  pcall(vim.api.nvim_win_set_var, win_id, "_tiny_term_tab_ids", terms)

  local winbar_parts = {}
  table.insert(winbar_parts, "%#TabLineFill# ")

  for idx, term_id in ipairs(terms) do
    local terminal = require("tiny-term.terminal")
    local term = terminal.get(term_id)
    if term then
      local is_active = term_id == active_term_id
      local cmd_display = term.cmd or "shell"

      if #cmd_display > 15 then
        cmd_display = cmd_display:sub(1, 12) .. "..."
      end

      local tab_text = " " .. idx .. " >_ " .. cmd_display .. " "

      if is_active then
        table.insert(winbar_parts, "%#TabLineSel#")
      else
        table.insert(winbar_parts, "%#TabLine#")
      end

      table.insert(winbar_parts, "%" .. idx .. "@v:lua.TinyTermTabClick@")
      table.insert(winbar_parts, tab_text)
      table.insert(winbar_parts, "%X")
      table.insert(winbar_parts, "%" .. idx .. "@v:lua.TinyTermTabCloseClick@")
      table.insert(winbar_parts, " ✕ ")
      table.insert(winbar_parts, "%X")
    end
  end

  table.insert(winbar_parts, "%#TabLineFill#")

  local winbar_text = table.concat(winbar_parts, "")
  pcall(vim.api.nvim_set_option_value, "winbar", winbar_text, { win = win_id })
end

function _G.TinyTermTabClick(tab_idx)
  local win_id = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win_id) or not tab_idx or tab_idx < 1 then
    return
  end

  local ok, terms = pcall(vim.api.nvim_win_get_var, win_id, "_tiny_term_tab_ids")
  if not ok or not terms or not terms[tab_idx] then
    return
  end

  local term_id = terms[tab_idx]
  M.switch_to_terminal(win_id, term_id)
end

function _G.TinyTermTabCloseClick(tab_idx)
  local win_id = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win_id) or not tab_idx or tab_idx < 1 then
    return
  end

  local ok, terms = pcall(vim.api.nvim_win_get_var, win_id, "_tiny_term_tab_ids")
  if not ok or not terms or not terms[tab_idx] then
    return
  end

  local term_id = terms[tab_idx]
  local terminal = require("tiny-term.terminal")
  local term = terminal.get(term_id)

  if not term then
    return
  end

  M.unregister_terminal_from_split(win_id, term_id)
  local remaining = M.get_split_terminals(win_id)

  if #remaining > 0 then
    local next_term_id = remaining[1]
    local next_term = terminal.get(next_term_id)
    if next_term and next_term.buf then
      vim.api.nvim_win_set_buf(win_id, next_term.buf)
      split_active_term[win_id] = next_term_id
      configure_terminal_window(win_id, { term = next_term })
      vim.api.nvim_set_current_win(win_id)
      if next_term.focus then
        next_term:focus()
      end
    end
    term.win = nil
    term.exited = true
    terminal.terminals[term_id] = nil
  else
    term:close()
  end
end

function M.stack_in_split(buf, position, opts)
  local win_opts = opts.win or {}
  local split_size = win_opts.split_size or 15
  local enable_stack = win_opts.stack ~= false

  local existing_win = enable_stack and M.get_split(position)

  if existing_win then
    vim.api.nvim_win_set_buf(existing_win, buf)
    configure_terminal_window(existing_win, opts)
    return existing_win
  end

  local current_win = vim.api.nvim_get_current_win()
  split_at(position, split_size)
  local win_id = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_buf(win_id, buf)
  configure_terminal_window(win_id, opts)
  vim.api.nvim_set_option_value("winhighlight", "Normal:TinyTermNormal,FloatBorder:TinyTermBorder", { win = win_id })

  M.register_split(position, win_id)

  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

  return win_id
end

function M.clear_split_windows()
  split_windows = {}
  split_terminals = {}
  split_active_term = {}
end

return M
