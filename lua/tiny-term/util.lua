local M = {}

--- Generate a deterministic terminal ID based on command, cwd, env, and count
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
  local env_key = ""
  if opts.env then
    -- Sort keys for deterministic serialization
    local sorted_keys = {}
    for k in pairs(opts.env) do
      table.insert(sorted_keys, k)
    end
    table.sort(sorted_keys)

    -- Build serialized env string
    local env_parts = {}
    for _, k in ipairs(sorted_keys) do
      table.insert(env_parts, k .. "=" .. tostring(opts.env[k]))
    end
    env_key = table.concat(env_parts, "|")
  end

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

return M
