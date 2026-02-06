local M = {}

--- Generate a simple terminal ID based on command, cwd, and count
--- @param cmd string|nil The command to run in the terminal (nil = shell)
--- @param opts table|nil Options table containing cwd, count, etc.
--- @return string id The terminal ID
function M.tid(cmd, opts)
  opts = opts or {}
  local cmd_key = cmd or vim.o.shell
  local cwd = opts.cwd or vim.fn.getcwd()
  local count = opts.count or vim.v.count1 or 1
  return string.format("%s|%s|%d", cmd_key, cwd, count)
end

--- Parse a shell command into a table of arguments
--- Handles spaces and tabs inside quotes (single and double) and backslash escapes.
--- @param cmd string|string[] Command to parse (already parsed if table)
--- @return string[] args Parsed arguments list
function M.parse(cmd)
  if type(cmd) == "table" then
    return cmd
  end

  local args = {}
  local in_single_quotes = false
  local in_double_quotes = false
  local current = ""

  local function add()
    table.insert(args, current)
    current = ""
  end

  local i = 1
  while i <= #cmd do
    local char = cmd:sub(i, i)

    if in_single_quotes then
      if char == "'" then
        in_single_quotes = false
        add()
      else
        current = current .. char
      end
    elseif in_double_quotes then
      if char == "\\" and i < #cmd then
        local next_char = cmd:sub(i + 1, i + 1)
        if next_char == '"' or next_char == "\\" then
          current = current .. next_char
          i = i + 1
        else
          current = current .. char
        end
      elseif char == '"' then
        in_double_quotes = false
        add()
      else
        current = current .. char
      end
    else
      if char == "'" then
        in_single_quotes = true
      elseif char == '"' then
        in_double_quotes = true
      elseif char == " " or char == "\t" then
        if #current > 0 then
          add()
        end
      else
        current = current .. char
      end
    end
    i = i + 1
  end

  if #current > 0 then
    add()
  end

  return args
end

return M
