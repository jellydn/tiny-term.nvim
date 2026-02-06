--- Window creation utilities for tiny-term.nvim
-- Handles floating and split window creation with Neovim 0.11+ support

local M = {}

-- Track split windows by tabpage and position for stacking.
-- Enables tmux-like behavior: multiple terminals at the same position reuse one split.
-- Format: tabpage_id -> position -> window_id
-- Positions: "bottom", "top", "left", "right"
local split_windows = {}

--- Get the window position string from options
--- Default: cmd provided → float, no cmd (shell) → bottom split
--- @param opts table Options table containing win config and cmd
--- @return string position Position string ("float", "bottom", "top", "left", "right")
function M.get_window_position(opts)
  local win_opts = opts.win or {}
  local position = win_opts.position

  if not position then
    position = opts.cmd and "float" or "bottom"
  end

  return position
end

--- Create a floating terminal window
--- @param opts table Options table
---   - win.width: number (fraction of editor width, default 0.8)
---   - win.height: number (fraction of editor height, default 0.8)
---   - win.border: string|table|nil (border style, nil to use 'winborder')
--- @return integer win_id Window ID
function M.create_float(opts)
  local win_opts = opts.win or {}
  local width = win_opts.width or 0.8
  local height = win_opts.height or 0.8

  -- Get editor dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines

  -- Calculate window dimensions
  local win_width = math.floor(editor_width * width)
  local win_height = math.floor(editor_height * height)

  -- Calculate centered position
  local row = math.floor((editor_height - win_height) / 2)
  local col = math.floor((editor_width - win_width) / 2)

  -- Determine border style
  -- Neovim 0.11+: Use vim.o.winborder as default, explicit opts.win.border overrides
  local border = win_opts.border
  if border == nil then
    -- Use global 'winborder' option (Neovim 0.11+)
    -- In Neovim 0.11, nil border means "use global setting"
    border = nil
  end

  -- Create floating window configuration
  local config = {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = border,
    -- Neovim 0.11+: mouse field for better interaction
    mouse = true,
  }

  -- Create the buffer if not provided
  local buf = opts.buf or vim.api.nvim_create_buf(false, true)
  if not buf or buf == 0 then
    error("Failed to create terminal buffer")
  end

  -- Create the floating window
  -- nvim_open_win returns window ID
  local win_id = vim.api.nvim_open_win(buf, true, config)
  if not win_id or win_id == 0 then
    error("Failed to create floating window")
  end
  if not vim.api.nvim_win_is_valid(win_id) then
    error("Window became invalid immediately after creation")
  end

  -- Set window options for terminal
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

--- Execute the split command for a given position
--- @param position string Position ("bottom", "top", "left", "right")
--- @param split_size number Size in rows/columns
local function split_at(position, split_size)
  local split_cmd
  if position == "bottom" then
    split_cmd = "botright " .. split_size .. "split"
  elseif position == "top" then
    split_cmd = "topleft " .. split_size .. "split"
  elseif position == "right" then
    split_cmd = "botright vertical " .. split_size .. "split"
  elseif position == "left" then
    split_cmd = "topleft vertical " .. split_size .. "split"
  else
    -- Default to bottom split for invalid position
    split_cmd = "botright " .. split_size .. "split"
  end

  local ok, err = pcall(vim.cmd, split_cmd)
  if not ok then
    error("Failed to create split: " .. tostring(err))
  end
end

--- Configure window options for terminal windows
--- @param win_id integer Window ID
--- @param opts table Options table
local function configure_terminal_window(win_id, opts)
  -- Set buffer if provided
  if opts.buf then
    if not vim.api.nvim_buf_is_valid(opts.buf) then
      error("Invalid buffer provided to configure_terminal_window")
    end
    vim.api.nvim_win_set_buf(win_id, opts.buf)
  end

  -- Store terminal ID on window for keymap access
  if opts.term then
    pcall(vim.api.nvim_win_set_var, win_id, "tiny_term_id", opts.term.id)
  end

  -- Set winhighlight for terminal windows
  vim.api.nvim_set_option_value("winhighlight", "Normal:TinyTermNormal,FloatBorder:TinyTermBorder", { win = win_id })
end

--- Restore window focus if previous window is valid
--- @param current_win integer The window to restore focus to
local function restore_window_focus(current_win)
  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end
end

--- Create a split terminal window
--- @param opts table Options table
---   - win.position: string ("bottom", "top", "left", "right")
---   - win.split_size: number (rows for bottom/top, cols for left/right)
--- @return integer win_id Window ID
function M.create_split(opts)
  local win_opts = opts.win or {}
  local position = M.get_window_position(opts)
  local split_size = win_opts.split_size or 15

  -- Save current window
  local current_win = vim.api.nvim_get_current_win()

  -- Create split based on position
  split_at(position, split_size)

  -- Get the new window ID
  local win_id = vim.api.nvim_get_current_win()

  -- Configure the window
  configure_terminal_window(win_id, opts)

  -- Return to previous window if we had one
  restore_window_focus(current_win)

  return win_id
end

--- Check if a window is a floating window
--- @param win_id integer Window ID
--- @return boolean is_floating True if window is floating
function M.is_floating(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then
    return false
  end

  local config = vim.api.nvim_win_get_config(win_id)
  -- Floating windows have a 'relative' field in their config
  return config.relative ~= nil and config.relative ~= ""
end

--- Create a window (float or split) based on options
--- @param opts table Options table
--- @return integer win_id Window ID
function M.create_window(opts)
  local position = M.get_window_position(opts)

  if position == "float" then
    return M.create_float(opts)
  else
    return M.create_split(opts)
  end
end

--- Register a split window for stacking at a given position
--- @param position string Position ("bottom", "top", "left", "right")
--- @param win_id integer Window ID
function M.register_split(position, win_id)
  -- Check if window is valid before getting tabpage
  if not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local tabpage = vim.api.nvim_win_get_tabpage(win_id)
  if not split_windows[tabpage] then
    split_windows[tabpage] = {}
  end
  split_windows[tabpage][position] = win_id
end

--- Get the existing split window for a position, if valid
--- @param position string Position ("bottom", "top", "left", "right")
--- @return integer|nil win_id Window ID or nil if no valid split exists
function M.get_split(position)
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tab_windows = split_windows[current_tab]
  if not tab_windows then
    return nil
  end

  local win_id = tab_windows[position]

  -- Check if window is still valid
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    -- Verify it's not a floating window
    if not M.is_floating(win_id) then
      return win_id
    end
  end

  -- Clear invalid entries
  tab_windows[position] = nil
  return nil
end

--- Stack a buffer in an existing split window, or create a new split
--- @param buf integer Buffer ID to stack
--- @param position string Position ("bottom", "top", "left", "right")
--- @param opts table Options table
---   - win.split_size: number (rows for bottom/top, cols for left/right)
---   - term: TinyTerm.Terminal Terminal object
--- @return integer win_id Window ID
function M.stack_in_split(buf, position, opts)
  local win_opts = opts.win or {}
  local split_size = win_opts.split_size or 15

  -- Check if we have an existing valid split at this position
  local existing_win = M.get_split(position)

  if existing_win then
    -- Reuse existing split: replace the buffer
    if not vim.api.nvim_buf_is_valid(buf) then
      error("Invalid buffer provided to stack_in_split")
    end
    vim.api.nvim_win_set_buf(existing_win, buf)

    -- Update terminal ID on window
    if opts.term then
      pcall(vim.api.nvim_win_set_var, existing_win, "tiny_term_id", opts.term.id)
    end

    return existing_win
  end

  -- No existing split, create a new one
  local current_win = vim.api.nvim_get_current_win()

  split_at(position, split_size)

  local win_id = vim.api.nvim_get_current_win()

  -- Set buffer and configure window
  opts.buf = buf
  configure_terminal_window(win_id, opts)

  -- Register this split for future stacking
  M.register_split(position, win_id)

  -- Return to previous window if we had one
  restore_window_focus(current_win)

  return win_id
end

--- Clear all split windows tracking (for testing)
function M.clear_split_windows()
  split_windows = {}
end

return M
