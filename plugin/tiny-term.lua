-- Guard for Neovim 0.11+
if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("tiny-term.nvim requires Neovim 0.11+", vim.log.levels.ERROR)
  return
end

-- Load the plugin module
local tiny_term = require("tiny-term")

-- Helper function to find terminal by buffer number
local function get_terminal_by_buf(buf)
  local terminals = tiny_term.list()
  for _, term in ipairs(terminals) do
    if term.buf == buf then
      return term
    end
  end
  return nil
end

-- Command completion for shell commands
local function cmd_complete(arg, cmd_line)
  -- Skip completion for now - could be enhanced to suggest common commands
  return {}
end

-- Create user commands
vim.api.nvim_create_user_command("TinyTerm", function(opts)
  tiny_term.toggle(opts.fargs[1], {})
end, {
  nargs = "?",
  desc = "Toggle a tiny terminal",
  complete = cmd_complete,
})

vim.api.nvim_create_user_command("TinyTermOpen", function(opts)
  tiny_term.open(opts.fargs[1], {})
end, {
  nargs = "?",
  desc = "Open a new tiny terminal",
  complete = cmd_complete,
})

vim.api.nvim_create_user_command("TinyTermClose", function()
  local current_buf = vim.api.nvim_get_current_buf()
  local ft = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
  if ft == "tiny_term" then
    local term = get_terminal_by_buf(current_buf)
    if term then
      term:close()
    else
      -- Fallback to closing the window if term object not found
      vim.cmd.close()
    end
  else
    vim.notify("Not in a tiny-term buffer", vim.log.levels.WARN)
  end
end, {
  desc = "Close the current tiny terminal",
})

vim.api.nvim_create_user_command("TinyTermList", function()
  local terminals = tiny_term.list()
  if #terminals == 0 then
    vim.notify("No active terminals", vim.log.levels.INFO)
    return
  end

  -- Build a nice display of all terminals
  local lines = { "TinyTerm Active Terminals:", "" }
  for i, term in ipairs(terminals) do
    local cmd = term.cmd or "shell"
    local status = term:is_visible() and "[visible]" or "[hidden]"
    table.insert(lines, string.format("  %d. %s - %s (buf: %d)", i, cmd, status, term.buf))
  end

  -- Display using vim.notify with multiline message
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, {
  desc = "List all active tiny terminals",
})
