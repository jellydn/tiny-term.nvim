# tiny-term.nvim

<p align="center">
  <img src="logo.svg" alt="tiny-term.nvim logo" width="128" height="128">
</p>

[![License](https://img.shields.io/github/license/jellydn/tiny-term.nvim?style=for-the-badge&logo=starship&color=ee999f&logoColor=D9E0EE&labelColor=302D41)](https://github.com/jellydn/tiny-term.nvim/blob/main/LICENSE)
[![Stars](https://img.shields.io/github/stars/jellydn/tiny-term.nvim?style=for-the-badge&logo=starship&color=c69ff5&logoColor=D9E0EE&labelColor=302D41)](https://github.com/jellydn/tiny-term.nvim/stargazers)
[![Issues](https://img.shields.io/github/issues/jellydn/tiny-term.nvim?style=for-the-badge&logo=bilibili&color=F5E0DC&logoColor=D9E0EE&labelColor=302D41)](https://github.com/jellydn/tiny-term.nvim/issues)

A minimal, standalone Neovim 0.11+ terminal plugin that provides floating and split terminal windows with toggle support. Serves as a drop-in replacement for `Snacks.terminal` with the same API shape, so existing integrations work with minimal changes.

<!-- TODO: Add demo GIF/image -->
[![Demo](https://i.gyazo.com/placeholder.gif)](https://gyazo.com/placeholder)

## ✨ Features

- 🪟 **Floating and split terminals** - Choose between floating windows or split layouts (bottom, top, left, right)
- 🔄 **Toggle support** - Quickly show/hide terminals with keymaps like `<C-/>`
- 🔢 **Multiple terminals** - Manage multiple terminals with stable IDs based on command, cwd, and count
- ⌨️ **Double-Escape to normal mode** - Single `<Esc>` passes through, double exits to normal mode
- 🎯 **Snacks.terminal API compatible** - Drop-in replacement with `toggle()`, `open()`, `get()`, `list()`
- 📚 **Window stacking** - Multiple split terminals at the same position stack together
- 🏷️ **Winbar labels** - Visual labels for stacked terminals
- 🚪 **Auto-close on exit** - Terminal windows close automatically when processes exit
- ⚡ **Zero dependencies** - Lightweight and built for Neovim 0.11+

## ⚡️ Requirements

- Neovim >= **0.11.0**

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "jellydn/tiny-term.nvim",
  opts = {
    -- your configuration here
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "jellydn/tiny-term.nvim",
  config = function()
    require("tiny-term").setup()
  end,
}
```

## 🚀 Usage

The plugin provides both Lua API and Vim commands for terminal management.

### Basic Usage

```lua
-- Toggle shell terminal (default)
require("tiny-term").toggle()

-- Toggle terminal running a command
require("tiny-term").toggle("lazygit")

-- Open a new terminal (always shows)
require("tiny-term").open("npm run dev")

-- Get existing terminal or create new one
local term, created = require("tiny-term").get("htop")

-- List all active terminals
local terminals = require("tiny-term").list()
```

### Recommended Keymaps

```lua
-- Toggle shell terminal
vim.keymap.set("n", "<C-/>", function()
  require("tiny-term").toggle()
end, { desc = "Toggle terminal" })

-- Toggle terminal with count (e.g., 2<C-/> for terminal #2)
vim.keymap.set("n", "<C-_>", function()
  local count = vim.v.count1
  require("tiny-term").toggle(nil, { count = count })
end, { desc = "Toggle terminal with count" })
```

## ⌨️ Commands

| Command | Description |
| --------------------- | -------------------------------------------- |
| `:TinyTerm` | Toggle shell terminal |
| `:TinyTerm {cmd}` | Toggle terminal running `{cmd}` |
| `:TinyTermOpen {cmd}` | Open new terminal (always creates/shows) |
| `:TinyTermClose` | Close current terminal |
| `:TinyTermList` | List all active terminals |

## ⚙️ Configuration

```lua
require("tiny-term").setup({
  -- Shell to use for terminals (default: vim.o.shell)
  shell = vim.o.shell,

  -- Window configuration
  win = {
    -- Position: "float" (default) or "bottom", "top", "left", "right"
    position = "float",

    -- Float window size (as fraction of editor)
    width = 0.8,
    height = 0.8,

    -- Border style (nil uses 'winborder' option from Neovim 0.11)
    border = nil,

    -- Split size in rows/columns
    split_size = 15,

    -- Default keymaps for terminal windows
    keys = {
      { "<Esc><Esc>", "<C-\\><C-n>", mode = "t", desc = "Enter normal mode" },
      { "q", function() ... end, mode = "n", desc = "Hide terminal" },
      { "gf", function() ... end, mode = "n", desc = "Open file under cursor" },
    },
  },

  -- Start in insert mode when terminal opens
  start_insert = true,

  -- Enter insert mode when toggling terminal visible
  auto_insert = true,

  -- Close window when terminal process exits
  auto_close = true,
})
```

### Window Position Behavior

- **Without command** (`toggle()`, `toggle(nil)`) → Opens in **float** by default
- **With command** (`toggle("lazygit")`) → Opens in **bottom split** by default
- Override with `opts.win.position`: `toggle("lazygit", { win = { position = "float" } })`

### Terminal IDs

Terminals are identified by a deterministic ID based on:
- Command (or shell if nil)
- Current working directory
- Environment variables
- Vim count (`vim.v.count1`)

This allows toggling multiple terminals:
```lua
-- Terminal #1 (default)
require("tiny-term").toggle()

-- Terminal #2 (different count)
require("tiny-term").toggle(nil, { count = 2 })

-- Terminal for specific directory
require("tiny-term").toggle(nil, { cwd = "/path/to/project" })
```

## 🔧 API Reference

### Module Functions

#### `setup(opts?)`

Configure the plugin with user options.

```lua
require("tiny-term").setup({
  shell = "/bin/bash",
  win = { position = "bottom" },
})
```

#### `toggle(cmd?, opts?)`

Toggle terminal visibility. Shows if hidden, hides if visible.

```lua
-- Returns: Terminal object or nil
local term = require("tiny-term").toggle("lazygit")
```

#### `open(cmd?, opts?)`

Open a new terminal (always creates/shows window).

```lua
-- Returns: Terminal object
local term = require("tiny-term").open("htop")
```

#### `get(cmd?, opts?)`

Get existing terminal or create new one.

```lua
-- Returns: Terminal object, created boolean
local term, created = require("tiny-term").get("node", { create = true })
```

#### `list()`

List all active terminal objects.

```lua
-- Returns: Array of terminal objects
local terminals = require("tiny-term").list()
```

#### `tid(cmd?, opts?)`

Generate terminal ID for given command and options.

```lua
-- Returns: Terminal ID string
local id = require("tiny-term").tid("lazygit")
```

### Terminal Object Methods

Terminal objects returned by the API have the following methods:

| Method | Description |
| ------ | ----------- |
| `term:show()` | Show terminal window (creates if needed) |
| `term:hide()` | Hide terminal window (keeps buffer/process) |
| `term:toggle()` | Toggle visibility based on current state |
| `term:close()` | Kill process and delete buffer |
| `term:is_floating()` | Returns `true` if terminal window is floating |
| `term:is_visible()` | Returns `true` if terminal has valid visible window |
| `term:buf_valid()` | Returns `true` if terminal buffer is still valid |
| `term:focus()` | Focus terminal window and enter insert mode |

## 🔧 How It Works

- **Buffer management**: Uses `bufhidden = "hide"` so terminal buffers persist when windows close
- **Window tracking**: Windows are tracked separately from buffers; a terminal can exist without a window
- **Neovim 0.11 features**: Leverages `'winborder'`, improved `nvim_open_win()`, terminal reflow, and `hl-StatusLineTerm`
- **Double-Escape**: Uses `vim.uv.new_timer()` to detect double-esc within 200ms

## 👤 Author

**Huynh Duc Dung**

- Website: https://productsway.com/
- Twitter: [@jellydn](https://twitter.com/jellydn)
- GitHub: [@jellydn](https://github.com/jellydn)

## Show Your Support

If this plugin has been helpful, please give it a ⭐️.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/dunghd)
[![PayPal](https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/dunghd)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/dunghd)

### Star History

[![Star History Chart](https://api.star-history.com/svg?repos=jellydn/tiny-term.nvim&type=Date)](https://star-history.com/#jellydn/tiny-term.nvim&Date)

## 📝 License

MIT
