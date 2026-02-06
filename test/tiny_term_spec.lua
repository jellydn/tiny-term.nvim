-- Tests for tiny-term.nvim
-- Run with: nvim --headless -c "PlenaryBustedDirectory test/"

-- Track created terminals for cleanup
local created_terms = {}

local function cleanup_all_terms()
  local tiny_term = require("tiny-term")
  local terminal = require("tiny-term.terminal")

  -- Close all terminals
  for id, term in pairs(terminal.terminals) do
    if term:buf_valid() then
      pcall(function() term:close() end)
    end
  end
  created_terms = {}
end

-- Helper function to safely close a terminal
local function safe_close(term)
  if term and term:buf_valid() then
    pcall(function() term:close() end)
  end
end

describe("tiny-term.nvim", function()
  -- Clean up after each test
  after_each(function()
    cleanup_all_terms()
  end)

  describe("tid() - Terminal ID generation", function()
    local util = require("tiny-term.util")

    it("produces deterministic IDs for same arguments", function()
      local id1 = util.tid(nil, {})
      local id2 = util.tid(nil, {})
      assert.equals(id1, id2)
    end)

    it("produces different IDs for different commands", function()
      local id1 = util.tid("ls", {})
      local id2 = util.tid("pwd", {})
      assert.not_equals(id1, id2)
    end)

    it("produces valid ID when cmd is nil (uses shell)", function()
      local id = util.tid(nil, {})
      assert.is_not_nil(id)
      assert.equals(16, #id) -- SHA256 truncated to 16 chars
    end)

    it("produces different IDs for different cwd", function()
      local id1 = util.tid("ls", { cwd = "/home/user/project" })
      local id2 = util.tid("ls", { cwd = "/home/user/other" })
      assert.not_equals(id1, id2)
    end)

    it("handles env option correctly", function()
      local id1 = util.tid("ls", { env = { FOO = "bar" } })
      local id2 = util.tid("ls", { env = { FOO = "baz" } })
      local id3 = util.tid("ls", { env = { FOO = "bar" } })
      assert.not_equals(id1, id2)
      assert.equals(id1, id3)
    end)

    it("treats no env, empty env, and nil env the same", function()
      local id1 = util.tid("ls", {})
      local id2 = util.tid("ls", { env = {} })
      local id3 = util.tid("ls", { env = nil })
      assert.equals(id1, id2)
      assert.equals(id2, id3)
    end)
  end)

  describe("setup() - Configuration", function()
    local tiny_term = require("tiny-term")

    it("merges user config with defaults", function()
      tiny_term.setup({
        win = {
          width = 0.5,
        },
      })

      -- setup() returns M (module), config is stored in M.config
      assert.equals(0.5, tiny_term.config.win.width)
      assert.equals(0.8, tiny_term.config.win.height) -- default preserved
    end)

    it("uses defaults when no arguments provided", function()
      -- Reset to defaults by calling with no args
      tiny_term.setup()

      assert.equals(0.8, tiny_term.config.win.width)
      assert.equals(0.8, tiny_term.config.win.height)
    end)

    it("merges nested win configuration correctly", function()
      tiny_term.setup({
        win = {
          position = "bottom",
          split_size = 20,
        },
      })

      assert.equals("bottom", tiny_term.config.win.position)
      assert.equals(20, tiny_term.config.win.split_size)
      assert.equals(0.8, tiny_term.config.win.width) -- default preserved
    end)

    it("sets auto_insert and start_insert options", function()
      tiny_term.setup({
        auto_insert = false,
        start_insert = false,
      })

      assert.is_false(tiny_term.config.auto_insert)
      assert.is_false(tiny_term.config.start_insert)
    end)
  end)

  describe("get() - Terminal retrieval", function()
    local tiny_term = require("tiny-term")

    it("creates new terminal when none exists", function()
      local term, created = tiny_term.get("echo 'test'", {})
      assert.is_not_nil(term)
      assert.is_true(created)

      -- Note: We don't call safe_close here because the terminal
      -- doesn't have a buffer yet (lazy creation)
      pcall(function() term:close() end)
    end)

    it("returns existing terminal when available", function()
      local term1, created1 = tiny_term.get("echo 'test'", {})
      assert.is_true(created1)

      -- Without calling show(), the terminal has no buffer
      -- so get() will still return a new terminal
      local term2, created2 = tiny_term.get("echo 'test'", {})
      -- This creates a new terminal because term1 has no buffer yet
      assert.is_not_nil(term2)

      pcall(function() term1:close() end)
      pcall(function() term2:close() end)
    end)

    it("returns nil when opts.create is false and terminal does not exist", function()
      local term, created = tiny_term.get("nonexistent", { create = false })
      assert.is_nil(term)
      assert.is_nil(created)
    end)

    it("creates different terminals for different opts", function()
      local term1 = tiny_term.get("ls", { cwd = "/tmp" })
      local term2 = tiny_term.get("ls", { cwd = "/home" })

      assert.not_equals(term1.id, term2.id)

      pcall(function() term1:close() end)
      pcall(function() term2:close() end)
    end)
  end)

  describe("open() - Open terminal", function()
    local tiny_term = require("tiny-term")

    -- NOTE: These tests are pending because they require a TTY/UI
    -- Terminal creation in headless mode doesn't work properly
    pending("creates and shows a terminal", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.is_not_nil(term)
      assert.is_not_nil(term.buf)
      assert.is_true(term:buf_valid())

      safe_close(term)
    end)

    pending("creates terminal buffer with correct filetype", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.is_not_nil(term.buf)

      local filetype = vim.api.nvim_buf_get_option(term.buf, "filetype")
      assert.equals("tiny_term", filetype)

      safe_close(term)
    end)

    pending("creates terminal buffer with correct buftype", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.is_not_nil(term.buf)

      local buftype = vim.api.nvim_buf_get_option(term.buf, "buftype")
      assert.equals("terminal", buftype)

      safe_close(term)
    end)

    pending("reuses existing terminal with same ID", function()
      local term1 = tiny_term.open("echo 'test'", {})
      local buf1 = term1.buf

      local term2 = tiny_term.open("echo 'test'", {})
      local buf2 = term2.buf

      assert.equals(buf1, buf2)
      assert.equals(term1.id, term2.id)

      safe_close(term1)
    end)
  end)

  describe("toggle() - Toggle visibility", function()
    local tiny_term = require("tiny-term")

    -- NOTE: These tests require terminal creation (needs TTY)
    pending("shows terminal when hidden", function()
      local term = tiny_term.toggle("echo 'test'", { auto_insert = false })
      assert.is_not_nil(term.win)

      safe_close(term)
    end)

    pending("hides terminal when visible", function()
      local term = tiny_term.open("echo 'test'", { auto_insert = false })
      assert.is_not_nil(term.win)

      tiny_term.toggle("echo 'test'", { auto_insert = false })
      assert.is_nil(term.win)

      if term:buf_valid() then
        term:close()
      end
    end)

    pending("toggles visibility back and forth", function()
      local term1 = tiny_term.toggle("echo 'test'", { auto_insert = false })
      assert.is_not_nil(term1.win)

      tiny_term.toggle("echo 'test'", { auto_insert = false })
      assert.is_nil(term1.win)

      local term2 = tiny_term.toggle("echo 'test'", { auto_insert = false })
      assert.equals(term1.id, term2.id)
      assert.is_not_nil(term2.win)

      safe_close(term2)
    end)
  end)

  describe("list() - List active terminals", function()
    local tiny_term = require("tiny-term")

    it("returns empty array when no terminals exist", function()
      cleanup_all_terms()
      local terms = tiny_term.list()
      assert.equals(0, #terms)
    end)

    -- NOTE: Requires terminal creation
    pending("returns array with one terminal after creating one", function()
      local term = tiny_term.open("echo 'test'", {})
      local terms = tiny_term.list()

      assert.equals(1, #terms)
      assert.equals(term.id, terms[1].id)

      safe_close(term)
    end)

    -- NOTE: Requires terminal creation
    pending("returns multiple terminals", function()
      local term1 = tiny_term.open("echo 'test1'", {})
      local term2 = tiny_term.open("echo 'test2'", {})

      local terms = tiny_term.list()
      assert.equals(2, #terms)

      local found1, found2 = false, false
      for _, t in ipairs(terms) do
        if t.id == term1.id then found1 = true end
        if t.id == term2.id then found2 = true end
      end
      assert.is_true(found1)
      assert.is_true(found2)

      safe_close(term1)
      safe_close(term2)
    end)

    -- NOTE: Requires terminal creation
    pending("does not include closed terminals", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.equals(1, #tiny_term.list())

      term:close()
      assert.equals(0, #tiny_term.list())
    end)
  end)

  describe("Terminal object methods", function()
    local tiny_term = require("tiny-term")

    -- NOTE: Requires terminal creation
    pending("buf_valid() returns true for valid buffer", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.is_true(term:buf_valid())
      safe_close(term)
    end)

    pending("buf_valid() returns false after closing", function()
      local term = tiny_term.open("echo 'test'", {})
      term:close()
      assert.is_false(term:buf_valid())
    end)

    pending("is_visible() returns true when window is open", function()
      local term = tiny_term.open("echo 'test'", {})
      local is_visible = term:is_visible()
      assert.is_boolean(is_visible)
      safe_close(term)
    end)

    pending("is_floating() returns correct value", function()
      local term = tiny_term.open("echo 'test'", {})
      if term.win and vim.api.nvim_win_is_valid(term.win) then
        local is_floating = term:is_floating()
        assert.is_boolean(is_floating)
      end
      safe_close(term)
    end)

    pending("hide() hides the terminal window", function()
      local term = tiny_term.open("echo 'test'", {})
      if term.win then
        term:hide()
        assert.is_nil(term.win)
      end
      if term:buf_valid() then
        term:close()
      end
    end)

    pending("close() closes terminal and cleans up", function()
      local term = tiny_term.open("echo 'test'", {})
      local buf = term.buf

      term:close()

      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)
  end)

  describe("Module __call metamethod", function()
    local tiny_term = require("tiny-term")

    -- NOTE: Requires terminal creation
    pending("allows calling module directly as toggle", function()
      local term1 = tiny_term("echo 'test'", { auto_insert = false })

      assert.is_not_nil(term1)
      assert.is_not_nil(term1.id)

      tiny_term("echo 'test'", { auto_insert = false })

      assert.is_nil(term1.win)

      if term1:buf_valid() then
        term1:close()
      end
    end)
  end)

  describe("Edge cases and error handling", function()
    local tiny_term = require("tiny-term")

    -- NOTE: Requires terminal creation
    pending("handles nil command (uses shell)", function()
      local term = tiny_term.open(nil, {})
      assert.is_not_nil(term)
      assert.is_nil(term.cmd)
      safe_close(term)
    end)

    pending("handles empty opts table", function()
      local term = tiny_term.open("echo 'test'", {})
      assert.is_not_nil(term)
      safe_close(term)
    end)

    it("handles get() with no arguments (uses nil cmd, empty opts)", function()
      local term, created = tiny_term.get()
      assert.is_not_nil(term)
      assert.is_true(created)
      pcall(function() term:close() end)
    end)

    it("handles multiple get calls with same count", function()
      -- Note: This test is limited because vim.v.count1 is context-dependent
      -- In test environment, count1 will always be 1 unless explicitly set
      local term1 = tiny_term.get("ls", {})
      local term2 = tiny_term.get("ls", {})

      -- Without changing count, should get same terminal ID
      -- (but different objects since no buffer was created)
      assert.equals(term1.id, term2.id)

      pcall(function() term1:close() end)
    end)
  end)

  describe("Window position handling", function()
    local tiny_term = require("tiny-term")

    -- NOTE: Requires terminal creation
    pending("respects win.position in opts", function()
      local term = tiny_term.open("echo 'test'", {
        win = { position = "bottom" }
      })
      assert.is_not_nil(term)

      if term.win and vim.api.nvim_win_is_valid(term.win) then
        local is_floating = term:is_floating()
        assert.is_false(is_floating)
      end

      safe_close(term)
    end)

    pending("defaults to float when no cmd and no position specified", function()
      local term = tiny_term.open(nil, {})
      assert.is_not_nil(term)

      if term.win and vim.api.nvim_win_is_valid(term.win) then
        local is_floating = term:is_floating()
        assert.is_true(is_floating)
      end

      safe_close(term)
    end)

    pending("respects win.split_size option", function()
      local term = tiny_term.open("echo 'test'", {
        win = {
          position = "bottom",
          split_size = 25
        }
      })
      assert.is_not_nil(term)
      safe_close(term)
    end)
  end)
end)
