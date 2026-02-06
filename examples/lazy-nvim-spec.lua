-- Example lazy.nvim plugin spec for tiny-term.nvim
-- This file demonstrates how to configure tiny-term.nvim in your Neovim config
-- Save this as lua/plugins/betterterm.lua in your Neovim config directory

return {
  "jellydn/tiny-term.nvim",
  opts = {
    -- Shell to use for terminals (default: vim.o.shell)
    -- shell = vim.o.shell,

    -- Window configuration
    win = {
      -- Position: "float" (default) or "bottom", "top", "left", "right"
      position = "float",

      -- Float window size (as fraction of editor)
      width = 0.8,
      height = 0.8,

      -- Border style (nil uses 'winborder' option from Neovim 0.11)
      -- You can also set explicit border: "single", "double", "rounded", "solid", etc.
      border = nil,

      -- Split size in rows/columns
      split_size = 15,

      -- Default keymaps for terminal windows
      -- Navigation keys work in split terminals, not in floats
      keys = {
        -- Double Esc to enter normal mode (handled by plugin)
        -- Window navigation (split terminals only)
        { "<C-h>", "<C-w>h", mode = "t", desc = "Move to window left" },
        { "<C-j>", "<C-w>j", mode = "t", desc = "Move to window below" },
        { "<C-k>", "<C-w>k", mode = "t", desc = "Move to window above" },
        { "<C-l>", "<C-w>l", mode = "t", desc = "Move to window right" },

        -- q to hide terminal (normal mode)
        {
          "q",
          function()
            local term = require("tiny-term").get()
            if term then
              term:hide()
            end
          end,
          mode = "n",
          desc = "Hide terminal",
        },

        -- gf to open file under cursor (normal mode)
        {
          "gf",
          function()
            local file = vim.fn.expand("<cfile>")
            if file ~= "" then
              local term = require("tiny-term").get()
              if term then
                term:hide()
              end
              vim.cmd("e " .. file)
            end
          end,
          mode = "n",
          desc = "Open file under cursor",
        },
      },
    },

    -- Start in insert mode when terminal opens
    start_insert = true,

    -- Enter insert mode when toggling terminal visible
    auto_insert = true,

    -- Close window when terminal process exits
    auto_close = true,
  },
  keys = {
    -- Toggle shell terminal (leader + ft)
    {
      "<leader>ft",
      function()
        require("tiny-term").toggle()
      end,
      desc = "Toggle terminal",
    },

    -- Toggle terminal with <C-/> (works in most terminals)
    {
      "<C-/>",
      function()
        require("tiny-term").toggle()
      end,
      desc = "Toggle terminal",
    },

    -- Toggle terminal with <C-_> (alternative for terminals that don't support <C-/>)
    {
      "<C-_>",
      function()
        local count = vim.v.count1
        require("tiny-term").toggle(nil, { count = count })
      end,
      desc = "Toggle terminal with count",
    },

    -- Toggle lazygit in a floating window
    {
      "<leader>gg",
      function()
        require("tiny-term").toggle("lazygit", {
          win = { position = "float" },
        })
      end,
      desc = "Toggle lazygit",
    },

    -- Toggle node in a bottom split
    {
      "<leader>gn",
      function()
        require("tiny-term").toggle("node", {
          win = { position = "bottom" },
        })
      end,
      desc = "Toggle node REPL",
    },
  },
}

-- ============================================================================
-- MIGRATION FROM betterTerm.nvim
-- ============================================================================
--
-- betterTerm.nvim keymap:
--   vim.keymap.set("n", "<C-/>", function()
--     require("betterTerm").open()
--   end)
--
-- tiny-term.nvim equivalent:
--   vim.keymap.set("n", "<C-/>", function()
--     require("tiny-term").toggle()
--   end)
--
-- Main differences:
-- - Use toggle() instead of open() for show/hide behavior
-- - Use win.position to control float vs split (not "style" option)
-- - Terminal IDs are based on cmd/cwd/count instead of numeric IDs

-- ============================================================================
-- MIGRATION FROM snacks.terminal
-- ============================================================================
--
-- If you're using snacks.nvim's terminal feature, you'll want to disable it:
--
-- In your snacks.lua plugin spec:
--
-- return {
--   "folke/snacks.nvim",
--   opts = {
--     bigfile = { enabled = true },
--     notifier = { enabled = true },
--     quickfile = { enabled = true },
--     words = { enabled = true },
--     -- Disable terminal functionality (replaced by tiny-term.nvim)
--     terminal = {
--       enabled = false,
--       -- Or keep it enabled but remove keymaps:
--       -- keys = {
--       --   toggle = "", -- Remove default <C-/> keymap
--       -- },
--     },
--   },
-- }

-- ============================================================================
-- ADVANCED CONFIGURATION
-- ============================================================================
--
-- Create custom terminal with specific working directory:
-- {
--   "<leader>tp",
--   function()
--     require("tiny-term").toggle(nil, {
--       cwd = vim.fn.getcwd(), -- Project-specific terminal
--       win = { position = "bottom" },
--     })
--   end,
--   desc = "Toggle project terminal",
-- }

-- Multiple numbered terminals:
-- {
--   "<leader>t1",
--   function()
--     require("tiny-term").toggle(nil, { count = 1 })
--   end,
--   desc = "Toggle terminal #1",
-- },
-- {
--   "<leader>t2",
--   function()
--     require("tiny-term").toggle(nil, { count = 2 })
--   end,
--   desc = "Toggle terminal #2",
-- },

-- Terminal with custom environment:
-- {
--   "<leader>td",
--   function()
--     require("tiny-term").toggle("docker-compose up", {
--       env = { COMPOSE_DOCKER_CLI_BUILD = "1" },
--       win = { position = "bottom" },
--     })
--   end,
--   desc = "Toggle docker-compose",
-- },
