--- Window creation utilities for tiny-term.nvim
-- Handles floating and split window creation with Neovim 0.11+ support

local M = {}

-- Track split windows by position for stacking
-- Format: position -> window_id
-- Positions: "bottom", "top", "left", "right"
local split_windows = {}

--- Get the window position string from options
--- @param opts table Options table containing win config
--- @return string position Position string ("float", "bottom", "top", "left", "right")
function M.get_window_position(opts)
  local win_opts = opts.win or {}
  local position = win_opts.position

  -- Default to "float" when no cmd, "bottom" when cmd provided
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

  -- Create the floating window
  -- nvim_open_win returns window ID
  local win_id = vim.api.nvim_open_win(buf, true, config)

  -- Set window options for terminal
  vim.api.nvim_win_set_option(win_id, "wrap", false)
  vim.api.nvim_win_set_option(win_id, "signcolumn", "no")

  return win_id
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
  if position == "bottom" then
    vim.cmd("botright " .. split_size .. "split")
  elseif position == "top" then
    vim.cmd("topleft " .. split_size .. "split")
  elseif position == "right" then
    vim.cmd("botright vertical " .. split_size .. "split")
  elseif position == "left" then
    vim.cmd("topleft vertical " .. split_size .. "split")
  else
    -- Default to bottom split for invalid position
    vim.cmd("botright " .. split_size .. "split")
  end

  -- Get the new window ID
  local win_id = vim.api.nvim_get_current_win()

  -- Set buffer if provided
  if opts.buf then
    vim.api.nvim_win_set_buf(win_id, opts.buf)
  end

  -- Return to previous window if we had one
  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

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
  split_windows[position] = win_id
end

--- Get the existing split window for a position, if valid
--- @param position string Position ("bottom", "top", "left", "right")
--- @return integer|nil win_id Window ID or nil if no valid split exists
function M.get_split(position)
  local win_id = split_windows[position]

  -- Check if window is still valid
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    -- Verify it's not a floating window
    if not M.is_floating(win_id) then
      return win_id
    end
  end

  -- Clear invalid entries
  split_windows[position] = nil
  return nil
end

--- Create a winbar for a terminal
--- @param term TinyTerm.Terminal Terminal object
--- @param win_id integer Window ID
function M.setup_winbar(term, win_id)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  -- Create winbar showing terminal ID/title
  local title = term.cmd or "shell"
  local winbar = " " .. title .. " [" .. term.id .. "] "

  vim.api.nvim_win_set_option(win_id, "winbar", winbar)
end

--- Stack a buffer in an existing split window, or create a new split
--- @param buf integer Buffer ID to stack
--- @param position string Position ("bottom", "top", "left", "right")
--- @param opts table Options table
---   - win.split_size: number (rows for bottom/top, cols for left/right)
---   - term: TinyTerm.Terminal Terminal object (for winbar)
--- @return integer win_id Window ID
function M.stack_in_split(buf, position, opts)
  local win_opts = opts.win or {}
  local split_size = win_opts.split_size or 15

  -- Check if we have an existing valid split at this position
  local existing_win = M.get_split(position)

  if existing_win then
    -- Reuse existing split: replace the buffer
    vim.api.nvim_win_set_buf(existing_win, buf)

    -- Update winbar if terminal object provided
    if opts.term then
      M.setup_winbar(opts.term, existing_win)
    end

    return existing_win
  end

  -- No existing split, create a new one
  local current_win = vim.api.nvim_get_current_win()

  -- Create split based on position
  if position == "bottom" then
    vim.cmd("botright " .. split_size .. "split")
  elseif position == "top" then
    vim.cmd("topleft " .. split_size .. "split")
  elseif position == "right" then
    vim.cmd("botright vertical " .. split_size .. "split")
  elseif position == "left" then
    vim.cmd("topleft vertical " .. split_size .. "split")
  else
    -- Default to bottom split for invalid position
    vim.cmd("botright " .. split_size .. "split")
  end

  -- Get the new window ID
  local win_id = vim.api.nvim_get_current_win()

  -- Set buffer
  vim.api.nvim_win_set_buf(win_id, buf)

  -- Register this split for future stacking
  M.register_split(position, win_id)

  -- Update winbar if terminal object provided
  if opts.term then
    M.setup_winbar(opts.term, win_id)
  end

  -- Return to previous window if we had one
  if vim.api.nvim_win_is_valid(current_win) then
    vim.api.nvim_set_current_win(current_win)
  end

  return win_id
end

return M
