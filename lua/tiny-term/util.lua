local M = {}

--- Serialize environment variables to a deterministic string
--- @param env table|nil Environment variables table
--- @return string Serialized env string
local function serialize_env(env)
  if not env then
    return ""
  end

  -- Sort keys for deterministic serialization
  local sorted_keys = {}
  for k in pairs(env) do
    table.insert(sorted_keys, k)
  end
  table.sort(sorted_keys)

  -- Build serialized env string
  local env_parts = {}
  for _, k in ipairs(sorted_keys) do
    table.insert(env_parts, k .. "=" .. tostring(env[k]))
  end

  return table.concat(env_parts, "|")
end

--- Generate a deterministic terminal ID based on command, cwd, env, and count
---
--- Uses SHA256 hash for collision resistance and privacy.
--- First 16 chars provide 64 bits of entropy (sufficient for practical use).
--- Terminals with identical configurations (cmd, cwd, env, count) get the same ID,
--- allowing reuse of existing terminal instances.
---
--- @param cmd string|nil The command to run in the terminal (nil = shell)
--- @param opts table|nil Options table containing cwd, env, etc.
--- @return string id The deterministic terminal ID
function M.tid(cmd, opts)
  opts = opts or {}

  -- Normalize cmd: nil cmd uses shell as key
  local cmd_key = cmd or vim.o.shell

  -- Get cwd from opts or current working directory
  local cwd = opts.cwd or vim.fn.getcwd()

  -- Normalize env: serialize if present, empty string if not
  local env_key = serialize_env(opts.env)

  -- Get count for numbered terminals
  -- opts.count takes precedence over vim.v.count1
  local count = opts.count or vim.v.count1 or 1

  -- Build ID string with clear delimiters
  -- Format: cmd|cwd|env|count
  local id_str = string.format("%s|%s|%s|%d", cmd_key, cwd, env_key, count)

  -- Use SHA256 hash for consistent, collision-resistant IDs
  local hash = vim.fn.sha256(id_str)

  -- Return first 16 characters of hash (sufficient for uniqueness)
  return string.sub(hash, 1, 16)
end

--- Parse a shell command into a table of arguments
---
--- Handles spaces inside quotes (double quotes only) and backslash escapes.
--- Compatible with Snacks.terminal.parse() for API compatibility.
---
--- @param cmd string|string[] Command to parse (already parsed if table)
--- @return string[] args Parsed arguments list
function M.parse(cmd)
  -- Guard clause: already parsed
  if type(cmd) == "table" then
    return cmd
  end

  local args = {}
  local in_quotes = false
  local escape_next = false
  local current = ""

  local function add()
    if #current > 0 then
      table.insert(args, current)
      current = ""
    end
  end

  for i = 1, #cmd do
    local char = cmd:sub(i, i)

    -- Guard clause: handle escaped character
    if escape_next then
      local preserve_backslash = char == '"' or char == "\\"
      current = current .. (preserve_backslash and "" or "\\") .. char
      escape_next = false
    elseif char == "\\" and in_quotes then
      escape_next = true
    elseif char == '"' then
      in_quotes = not in_quotes
    elseif char:find("[ \\t]") and not in_quotes then
      add()
    else
      current = current .. char
    end
  end

  add()
  return args
end

return M
