# AGENTS.md for tiny-term

## Repository Overview

tiny-term is a minimal terminal toggle plugin for Neovim 0.11+. It provides a drop-in replacement API compatible with Snacks.terminal.

## Build, Test, and Development Commands

### Run Full Test Suite

```bash
nvim --headless -c "PlenaryBustedDirectory test/"
```

### Run Single Test File

```bash
nvim --headless -c "PlenaryBustedDirectory test/tiny_term_spec.lua" -c "qa!"
```

### Run Single Test (by pattern)

```bash
nvim --headless -c "PlenaryBustedDirectory test/ --tags=focus" -c "qa!"
```

### Check Code Formatting

```bash
stylua --check .
```

### Format Code

```bash
stylua .
```

### CI Lint Check

Uses `stylua --check .` in `.github/workflows/ci.yml`

### No Build Step

This is a runtime Neovim plugin with no compilation step. Neovim >= 0.11 is required.

## Code Style Guidelines

### Indentation & Line Endings

- **2 spaces** for indentation (configured in `.stylua.toml`)
- **Unix line endings** (`\n`)
- **Column width: 120**

### Quote Style

- **Prefer double quotes** where StyLua decides automatically (`quote_style = "AutoPreferDouble"`)

### Naming Conventions

- **Lua modules**: snake_case under `lua/tiny-term/` (e.g., `util.lua`, `terminal.lua`)
- **Module names**: `require("tiny-term.<module>")` format
- **Variables**: snake_case (e.g., `local win_width`, `auto_insert`)
- **Functions**: snake_case (e.g., `function Terminal.new()`, `function M.setup()`)
- **Constants**: UPPER_SNAKE_CASE for module-level constants (e.g., `local DEFAULTS = {}`)

### Module Pattern

```lua
local M = {}

function M.setup(opts)
  -- implementation
  return M
end

return M
```

- Use `local M = {}` for module tables
- Return `M` at end of file
- Private functions defined as `local function name()` above `M`
- Group imports at top of module

### Class-Like Objects (Terminal)

```lua
local Terminal = {}
Terminal.__index = Terminal

function Terminal.new(cmd, opts)
  return setmetatable({...}, Terminal)
end
```

### Methods vs Functions

- **Methods**: Use colon syntax (`:method()`) for terminal/object methods
- **Module functions**: Use dot syntax (`M.function()`)

### Imports & Dependencies

```lua
-- Group local imports at module top
local config = require("tiny-term.config")
local util = require("tiny-term.util")
local window = require("tiny-term.window")
```

### Type Annotations ( EmmyLua/LuaLS )

- Use `---@class ClassName` for class definitions
- Use `---@type Type` for type declarations
- Use `---@param Type param_name Description` for function params
- Use `---@return Type Description` for return values

```lua
---@class TinyTerm.Config
---@field shell string
---@field win table
---@field auto_insert boolean

---@param opts TinyTerm.Config|nil
---@return TinyTerm.Config
function M.setup(opts)
```

### Error Handling

- Use `pcall` for Neovim API calls that might fail
- Use `error()` for unrecoverable initialization errors
- Guard against nil with early returns

```lua
if not self.win or not vim.api.nvim_win_is_valid(self.win) then
  return false
end
```

### Control Flow

- Use guard clauses for nil checks: `if not x then return end`
- Avoid nested conditionals; prefer early returns
- Use `vim.tbl_deep_extend("force", ...)` for config merging

### Window/Buffer Operations

- Always validate windows/buffers with `nvim_win_is_valid()` and `nvim_buf_is_valid()`
- Use `vim.api.nvim_win_call()` when operations need window context
- Clean up autocmds with `pcall(vim.api.nvim_del_autocmd, ...)`

### Lua Idioms

- Use `opts = opts or {}` for optional tables
- Use `type(x) == "table"` for type checking
- Use `vim.tbl_contains()`, `vim.tbl_islist()` for table operations
- Use `table.insert()` and `table.concat()` for array operations

### Function Design

- Keep functions small and focused (< 50 lines ideal)
- Reuse helpers from `util.lua` and `window.lua`
- Document exported functions with EmmyLua annotations
- Single responsibility per function

### Whitespace

- No trailing whitespace
- One blank line between function groups
- No extra blank lines at file end

## Project Structure

```
lua/tiny-term/          # Core plugin modules
  init.lua              # Main module (exports public API)
  terminal.lua          # Terminal object and buffer management
  window.lua            # Window creation utilities
  config.lua            # Configuration system
  util.lua              # Helper functions
plugin/                 # Neovim commands and startup hooks
test/                  # Plenary/Busted specs (*_spec.lua)
doc/                   # Generated vimdoc
examples/              # Configuration snippets
```

## Testing Guidelines

- Use Plenary's Busted runner via Neovim headless
- Test files: `test/*_spec.lua` naming convention
- Follow **Arrange-Act-Assert** pattern
- Use `after_each` for cleanup
- Focus on behavior, not implementation details
- Mock UI/TTY when possible

## Commit & Pull Request Guidelines

- Commits: **Conventional Commit** style (`feat:`, `fix:`, `chore:`, `docs:`)
- PRs: Include behavior changes and link related issues
- User-facing changes: Include usage example or screenshot

## Documentation

- `doc/tiny-term.txt` is **auto-generated** (avoid manual edits)
- Update `README.md` for user-facing behavior changes
- Use `:help tiny-term.txt` in Neovim after changes
