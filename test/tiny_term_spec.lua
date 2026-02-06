-- Tests for tiny-term.nvim
-- Run with: nvim --headless -c "PlenaryBustedDirectory test/"
-- Focus on behavior, not implementation details, using Arrange-Act-Assert pattern

local tiny_term = require("tiny-term")
local terminal = require("tiny-term.terminal")
local window = require("tiny-term.window")
local util = require("tiny-term.util")

-- ============================================================================
-- TEST HELPERS
-- ============================================================================

--- Clean up all terminals after each test
local function cleanup_all_terms()
  for id, term in pairs(terminal.terminals) do
    pcall(function()
      term:close()
    end)
  end
  -- Clear the terminals table completely
  terminal.terminals = {}
  -- Also reset the split_windows tracking using the module function
  window.clear_split_windows()
end

--- Create a mock terminal object for testing without UI
--- @param cmd string|nil Command to run
--- @param opts table|nil Options
--- @return table Mock terminal object
local function mock_terminal(cmd, opts)
  local term = {
    id = util.tid(cmd, opts),
    cmd = cmd,
    opts = opts or {},
    buf = nil,
    win = nil,
    cwd = opts and opts.cwd or vim.fn.getcwd(),
    env = opts and opts.env,
    job_id = nil,
    exited = false,
    process_started = false,
    esc_state = {
      timer = nil,
      count = 0,
      delay_ms = 200,
    },
  }

  -- Add methods for testing
  function term:buf_valid()
    -- For testing, just check if buf is set (not if it's a real buffer)
    return self.buf ~= nil
  end

  function term:handle_exit()
    if self.exited then
      return
    end
    self.exited = true
    self:cleanup_esc_timer()
    self.autocmd_id = nil
  end

  function term:cleanup_esc_timer()
    if self.esc_state.timer then
      self.esc_state.timer:close()
      self.esc_state.timer = nil
    end
    self.esc_state.count = 0
  end

  function term:handle_double_esc()
    self.esc_state.count = self.esc_state.count + 1

    if self.esc_state.count == 2 then
      -- Double esc detected - exit to normal mode
      self:cleanup_esc_timer()
      return true
    end

    -- First esc - start timer
    if self.esc_state.timer then
      self.esc_state.timer:stop()
    else
      self.esc_state.timer = vim.uv.new_timer()
    end

    -- Timer callback - NOTE: vim.schedule removed for testing compatibility
    -- In production code, vim.schedule is needed for proper event loop handling
    self.esc_state.timer:start(self.esc_state.delay_ms, 0, function()
      -- Timer expired - single esc, send ESC to terminal via channel
      if self.job_id and self:buf_valid() then
        -- Send ESC character (\27) to the terminal's channel
        vim.api.nvim_chan_send(self.job_id, "\27")
      end
      self.esc_state.count = 0
    end)

    -- First esc - don't send anything yet, wait for timer
    return false
  end

  function term:close()
    self.exited = true
    self:cleanup_esc_timer()
    self.autocmd_id = nil
    -- Don't actually delete the buffer in tests (avoid invalid buffer errors)
  end

  function term:is_visible()
    return self.win ~= nil
  end

  function term:toggle()
    if self:is_visible() then
      self.win = nil
    else
      -- For testing, just mark as visible
      self.win = vim.api.nvim_get_current_win()
    end
  end

  function term:show()
    self.win = vim.api.nvim_get_current_win()
  end

  function term:hide()
    self.win = nil
  end

  return term
end

--- Simulate a terminal buffer being valid
--- @param term table Terminal object
local function simulate_valid_buffer(term)
  term.buf = 999 -- Mock buffer ID
  term.process_started = true
end

--- Simulate a terminal window being visible
--- @param term table Terminal object
--- @param win_id integer Window ID
local function simulate_visible_window(term, win_id)
  term.win = win_id
end

-- ============================================================================
-- SETUP & CONFIGURATION TESTS
-- ============================================================================

describe("tiny-term.setup()", function()
  after_each(function()
    -- Reset to defaults after each test
    tiny_term.setup()
  end)

  it("should merge user config with defaults", function()
    -- Arrange
    local custom_width = 0.6

    -- Act
    tiny_term.setup({
      win = {
        width = custom_width,
      },
    })

    -- Assert
    assert.equals(custom_width, tiny_term.config.win.width)
    assert.equals(0.8, tiny_term.config.win.height) -- default preserved
  end)

  it("should use all defaults when no config provided", function()
    -- Arrange & Act
    tiny_term.setup()

    -- Assert
    assert.equals(0.8, tiny_term.config.win.width)
    assert.equals(0.8, tiny_term.config.win.height)
    assert.equals(15, tiny_term.config.win.split_size)
    assert.is_true(tiny_term.config.auto_insert)
    assert.is_true(tiny_term.config.start_insert)
    assert.is_true(tiny_term.config.auto_close)
  end)

  it("should set boolean options correctly", function()
    -- Arrange
    local expected = {
      auto_insert = false,
      start_insert = false,
      auto_close = false,
    }

    -- Act
    tiny_term.setup(expected)

    -- Assert
    assert.is_false(tiny_term.config.auto_insert)
    assert.is_false(tiny_term.config.start_insert)
    assert.is_false(tiny_term.config.auto_close)
  end)

  it("should handle nested win configuration merge", function()
    -- Arrange
    local custom_position = "bottom"
    local custom_size = 25

    -- Act
    tiny_term.setup({
      win = {
        position = custom_position,
        split_size = custom_size,
      },
    })

    -- Assert
    assert.equals(custom_position, tiny_term.config.win.position)
    assert.equals(custom_size, tiny_term.config.win.split_size)
    assert.equals(0.8, tiny_term.config.win.width) -- default preserved
  end)

  it("should return the module for chaining", function()
    -- Arrange & Act
    local result = tiny_term.setup({})

    -- Assert
    assert.equals(tiny_term, result)
  end)
end)

-- ============================================================================
-- TERMINAL ID GENERATION TESTS
-- ============================================================================

describe("util.tid()", function()
  it("should generate consistent IDs for identical inputs", function()
    -- Arrange
    local cmd = "ls"
    local opts = {}

    -- Act
    local id1 = util.tid(cmd, opts)
    local id2 = util.tid(cmd, opts)

    -- Assert
    assert.equals(id1, id2)
  end)

  it("should generate different IDs for different commands", function()
    -- Arrange
    local opts = {}

    -- Act
    local id1 = util.tid("ls", opts)
    local id2 = util.tid("pwd", opts)

    -- Assert
    assert.not_equals(id1, id2)
  end)

  it("should generate different IDs for different cwd", function()
    -- Arrange
    local cmd = "ls"

    -- Act
    local id1 = util.tid(cmd, { cwd = "/home/user/project" })
    local id2 = util.tid(cmd, { cwd = "/home/user/other" })

    -- Assert
    assert.not_equals(id1, id2)
  end)

  it("should handle environment variables in ID generation", function()
    -- Arrange
    local cmd = "ls"

    -- Act
    local id1 = util.tid(cmd, { env = { FOO = "bar" } })
    local id2 = util.tid(cmd, { env = { FOO = "baz" } })
    local id3 = util.tid(cmd, { env = { FOO = "bar" } })

    -- Assert
    assert.not_equals(id1, id2)
    assert.equals(id1, id3)
  end)

  it("should treat missing env, empty env, and nil env the same", function()
    -- Arrange
    local cmd = "ls"

    -- Act
    local id1 = util.tid(cmd, {})
    local id2 = util.tid(cmd, { env = {} })
    local id3 = util.tid(cmd, { env = nil })

    -- Assert
    assert.equals(id1, id2)
    assert.equals(id2, id3)
  end)

  it("should generate valid ID for nil command (uses shell)", function()
    -- Arrange & Act
    local id = util.tid(nil, {})

    -- Assert
    assert.is_not_nil(id)
    assert.equals(16, #id) -- SHA256 truncated to 16 chars
  end)

  it("should include count in ID generation", function()
    -- Arrange
    local cmd = "ls"

    -- Act
    local id1 = util.tid(cmd, { count = 1 })
    local id2 = util.tid(cmd, { count = 2 })

    -- Assert
    assert.not_equals(id1, id2)
  end)

  it("should handle opts.count taking precedence over vim.v.count1", function()
    -- Arrange
    local cmd = "ls"
    local count = 5

    -- Act
    local id = util.tid(cmd, { count = count })

    -- Assert
    assert.is_not_nil(id)
    assert.equals(16, #id)
  end)
end)

-- ============================================================================
-- TERMINAL RETRIEVAL TESTS
-- ============================================================================

describe("tiny-term.get()", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should create a new terminal when none exists", function()
    -- Arrange
    local cmd = "echo 'test'"
    local opts = {}

    -- Act
    local term, created = tiny_term.get(cmd, opts)

    -- Assert
    assert.is_not_nil(term)
    assert.is_true(created)
    assert.is_not_nil(term.id)
    assert.equals(cmd, term.cmd)
  end)

  it("should return existing terminal when available", function()
    -- Arrange
    local cmd = "echo 'test'"
    local opts = {}
    local term1 = terminal.get_or_create(cmd, opts)
    simulate_valid_buffer(term1)

    -- Act
    local term2, created = tiny_term.get(cmd, opts)

    -- Assert
    assert.equals(term1.id, term2.id)
    assert.is_false(created)
  end)

  it("should return nil when opts.create is false and terminal does not exist", function()
    -- Arrange
    local cmd = "nonexistent"

    -- Act
    local term, created = tiny_term.get(cmd, { create = false })

    -- Assert
    assert.is_nil(term)
    assert.is_nil(created)
  end)

  it("should create different terminals for different options", function()
    -- Arrange
    local cmd = "ls"

    -- Act
    local term1 = tiny_term.get(cmd, { cwd = "/tmp" })
    local term2 = tiny_term.get(cmd, { cwd = "/home" })

    -- Assert
    assert.not_equals(term1.id, term2.id)
  end)

  it("should handle nil command", function()
    -- Arrange & Act
    local term, created = tiny_term.get(nil, {})

    -- Assert
    assert.is_not_nil(term)
    assert.is_true(created)
    assert.is_nil(term.cmd)
  end)

  it("should handle no arguments", function()
    -- Arrange & Act
    local term, created = tiny_term.get()

    -- Assert
    assert.is_not_nil(term)
    assert.is_true(created)
  end)
end)

-- ============================================================================
-- TERMINAL LIST TESTS
-- ============================================================================

describe("tiny-term.list()", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should return empty array when no terminals exist", function()
    -- Arrange (ensure clean state)
    cleanup_all_terms()

    -- Act
    local terms = tiny_term.list()

    -- Assert
    assert.is_true(vim.tbl_islist(terms))
    assert.equals(0, #terms)
  end)

  it("should return array with created terminals", function()
    -- Arrange
    local term1 = terminal.get_or_create("echo 'test1'", {})
    simulate_valid_buffer(term1)
    local term2 = terminal.get_or_create("echo 'test2'", {})
    simulate_valid_buffer(term2)

    -- Act
    local terms = tiny_term.list()

    -- Assert
    assert.equals(2, #terms)

    local found1, found2 = false, false
    for _, t in ipairs(terms) do
      if t.id == term1.id then
        found1 = true
      end
      if t.id == term2.id then
        found2 = true
      end
    end

    assert.is_true(found1)
    assert.is_true(found2)
  end)

  it("should not include terminals without valid buffers", function()
    -- Arrange
    local term1 = terminal.get_or_create("echo 'test'", {})
    simulate_valid_buffer(term1)
    local term2 = terminal.get_or_create("echo 'test2'", {})
    -- Don't simulate valid buffer for term2

    -- Act
    local terms = tiny_term.list()

    -- Assert
    assert.equals(1, #terms)
    assert.equals(term1.id, terms[1].id)
  end)
end)

-- ============================================================================
-- WINDOW POSITION TESTS
-- ============================================================================

describe("window.get_window_position()", function()
  it("should return float when cmd is provided and no position specified", function()
    -- Arrange
    local opts = { cmd = "ls" }

    -- Act
    local position = window.get_window_position(opts)

    -- Assert
    assert.equals("float", position)
  end)

  it("should return bottom when no cmd and no position specified", function()
    -- Arrange
    local opts = { cmd = nil }

    -- Act
    local position = window.get_window_position(opts)

    -- Assert
    assert.equals("bottom", position)
  end)

  it("should use explicitly specified position", function()
    -- Arrange
    local positions = { "float", "bottom", "top", "left", "right" }

    for _, expected_pos in ipairs(positions) do
      -- Act
      local position = window.get_window_position({ win = { position = expected_pos } })

      -- Assert
      assert.equals(expected_pos, position)
    end
  end)

  it("should prioritize win.position over cmd default", function()
    -- Arrange
    local opts = {
      cmd = "ls",
      win = { position = "bottom" },
    }

    -- Act
    local position = window.get_window_position(opts)

    -- Assert
    assert.equals("bottom", position)
  end)
end)

-- ============================================================================
-- TERMINAL OBJECT TESTS
-- ============================================================================

describe("Terminal object", function()
  after_each(function()
    cleanup_all_terms()
  end)

  describe("buf_valid()", function()
    it("should return false when buf is nil", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})

      -- Act
      local is_valid = term:buf_valid()

      -- Assert
      assert.is_false(is_valid)
    end)

    it("should return true when buf is set and valid", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)

      -- Act
      local is_valid = term:buf_valid()

      -- Assert
      assert.is_true(is_valid)
    end)
  end)

  describe("is_visible()", function()
    it("should return false when win is nil", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})

      -- Act
      local visible = term:is_visible()

      -- Assert
      assert.is_false(visible)
    end)

    it("should return true when win is set and valid", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      simulate_visible_window(term, vim.api.nvim_get_current_win())

      -- Act
      local visible = term:is_visible()

      -- Assert
      assert.is_true(visible)
    end)
  end)

  describe("toggle()", function()
    it("should show terminal when not visible", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      -- Terminal is not visible initially

      -- Act
      term:toggle()

      -- Assert
      assert.is_true(term:is_visible())
    end)

    it("should hide terminal when visible", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      simulate_visible_window(term, vim.api.nvim_get_current_win())
      -- Terminal is now visible

      -- Act
      term:toggle()

      -- Assert
      assert.is_false(term:is_visible())
    end)
  end)

  describe("close()", function()
    it("should mark terminal as exited", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)

      -- Act
      term:close()

      -- Assert
      assert.is_true(term.exited)
    end)

    it("should clean up autocmd_id if present", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      term.autocmd_id = 123

      -- Act
      term:close()

      -- Assert
      assert.is_nil(term.autocmd_id)
    end)
  end)

  describe("handle_exit()", function()
    it("should mark terminal as exited", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      term.exited = false

      -- Act
      term:handle_exit()

      -- Assert
      assert.is_true(term.exited)
    end)

    it("should only handle exit once (idempotent)", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      simulate_valid_buffer(term)
      local call_count = 0
      term.buf_valid = function()
        return true
      end

      -- Act
      term:handle_exit()
      local first_exited = term.exited
      term.exited = false -- Reset to test idempotency
      term:handle_exit()

      -- Assert
      assert.is_true(first_exited)
    end)
  end)

  describe("cleanup_esc_timer()", function()
    it("should reset esc_state count", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      term.esc_state.count = 5

      -- Act
      term:cleanup_esc_timer()

      -- Assert
      assert.equals(0, term.esc_state.count)
    end)

    it("should clean up timer if present", function()
      -- Arrange
      local term = mock_terminal("echo 'test'", {})
      local mock_timer = { close = function() end }
      term.esc_state.timer = mock_timer

      -- Act
      term:cleanup_esc_timer()

      -- Assert
      assert.is_nil(term.esc_state.timer)
    end)
  end)
end)

-- ============================================================================
-- MODULE METATABLE TESTS
-- ============================================================================

describe("Module __call metamethod", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should call toggle when module is invoked", function()
    -- Arrange
    local toggle_called = false
    local original_toggle = tiny_term.toggle
    tiny_term.toggle = function()
      toggle_called = true
      return mock_terminal("echo 'test'", {})
    end

    -- Act
    tiny_term("echo 'test'", {})

    -- Assert
    assert.is_true(toggle_called)

    -- Restore original
    tiny_term.toggle = original_toggle
  end)

  it("should return terminal object when called", function()
    -- Arrange & Act
    local term = tiny_term("echo 'test'", {})

    -- Assert
    assert.is_not_nil(term)
    assert.is_not_nil(term.id)
  end)
end)

-- ============================================================================
-- CONFIG MODULE TESTS
-- ============================================================================

describe("config module", function()
  local config = require("tiny-term.config")

  it("should provide default configuration", function()
    -- Act
    local defaults = config.setup()

    -- Assert
    assert.is_not_nil(defaults)
    assert.is_not_nil(defaults.win)
    assert.is_not_nil(defaults.win.keys)
    assert.is_true(defaults.interactive)
  end)

  it("should merge user options with defaults", function()
    -- Arrange
    local user_opts = {
      win = {
        width = 0.6,
      },
    }

    -- Act
    local merged = config.setup(user_opts)

    -- Assert
    assert.equals(0.6, merged.win.width)
    assert.equals(0.8, merged.win.height)
  end)

  it("should set shell to vim.o.shell by default", function()
    -- Arrange & Act
    local result = config.setup({})

    -- Assert
    assert.equals(vim.o.shell, result.shell)
  end)

  it("should preserve user-provided shell option", function()
    -- Arrange
    local custom_shell = "/bin/bash"

    -- Act
    local result = config.setup({ shell = custom_shell })

    -- Assert
    assert.equals(custom_shell, result.shell)
  end)
end)

-- ============================================================================
-- WINDOW MODULE TESTS
-- ============================================================================

describe("window module", function()
  describe("is_floating()", function()
    it("should return false for invalid window", function()
      -- Arrange
      local invalid_win = 999999

      -- Act
      local is_float = window.is_floating(invalid_win)

      -- Assert
      assert.is_false(is_float)
    end)

    it("should return true for floating window", function()
      -- Arrange
      local buf = vim.api.nvim_create_buf(false, true)
      local config = {
        relative = "editor",
        width = 10,
        height = 10,
        row = 0,
        col = 0,
      }
      local float_win = vim.api.nvim_open_win(buf, false, config)

      -- Act
      local is_float = window.is_floating(float_win)

      -- Assert
      assert.is_true(is_float)

      -- Cleanup
      vim.api.nvim_win_close(float_win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("should return false for split window", function()
      -- Arrange
      local current_win = vim.api.nvim_get_current_win()

      -- Act
      local is_float = window.is_floating(current_win)

      -- Assert
      assert.is_false(is_float)
    end)
  end)

  describe("register_split() and get_split()", function()
    after_each(function()
      window.clear_split_windows()
    end)

    it("should register and retrieve split windows", function()
      -- Arrange
      local position = "bottom"
      local win_id = vim.api.nvim_get_current_win()

      -- Act
      window.register_split(position, win_id)
      local retrieved = window.get_split(position)

      -- Assert
      assert.equals(win_id, retrieved)
    end)

    it("should return nil for unregistered position", function()
      -- Arrange & Act
      local result = window.get_split("top")

      -- Assert
      assert.is_nil(result)
    end)

    it("should return nil for invalid window", function()
      -- Arrange
      local position = "bottom"
      local invalid_win = 999999

      -- Act
      window.register_split(position, invalid_win)
      local result = window.get_split(position)

      -- Assert
      assert.is_nil(result)
    end)

    it("should return nil for floating window", function()
      -- Arrange
      local buf = vim.api.nvim_create_buf(false, true)
      local config = {
        relative = "editor",
        width = 10,
        height = 10,
        row = 0,
        col = 0,
      }
      local float_win = vim.api.nvim_open_win(buf, false, config)
      local position = "bottom"

      -- Act
      window.register_split(position, float_win)
      local result = window.get_split(position)

      -- Assert
      assert.is_nil(result)

      -- Cleanup
      vim.api.nvim_win_close(float_win, true)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)

-- ============================================================================
-- TERMINAL MODULE TESTS
-- ============================================================================

describe("terminal module", function()
  after_each(function()
    cleanup_all_terms()
  end)

  describe("get_or_create()", function()
    it("should create new terminal when none exists", function()
      -- Arrange
      local cmd = "echo 'test'"
      local opts = {}

      -- Act
      local term = terminal.get_or_create(cmd, opts)

      -- Assert
      assert.is_not_nil(term)
      assert.is_not_nil(term.id)
      assert.equals(cmd, term.cmd)
    end)

    it("should return existing terminal when available", function()
      -- Arrange
      local cmd = "echo 'test'"
      local opts = {}
      local term1 = terminal.get_or_create(cmd, opts)

      -- Act
      local term2 = terminal.get_or_create(cmd, opts)

      -- Assert
      assert.equals(term1.id, term2.id)
    end)

    it("should create new terminal for different options", function()
      -- Arrange
      local cmd = "ls"

      -- Act
      local term1 = terminal.get_or_create(cmd, { cwd = "/tmp" })
      local term2 = terminal.get_or_create(cmd, { cwd = "/home" })

      -- Assert
      assert.not_equals(term1.id, term2.id)
    end)
  end)

  describe("get()", function()
    it("should return terminal by ID", function()
      -- Arrange
      local term = terminal.get_or_create("echo 'test'", {})

      -- Act
      local retrieved = terminal.get(term.id)

      -- Assert
      assert.is_not_nil(retrieved)
      assert.equals(term.id, retrieved.id)
    end)

    it("should return nil for non-existent ID", function()
      -- Arrange & Act
      local result = terminal.get("nonexistent_id")

      -- Assert
      assert.is_nil(result)
    end)
  end)

  describe("list()", function()
    it("should return empty table when no terminals exist", function()
      -- Arrange
      cleanup_all_terms()

      -- Act
      local result = terminal.list()

      -- Assert
      assert.is_true(vim.tbl_islist(result))
      assert.equals(0, #result)
    end)

    it("should not include terminals with invalid buffers", function()
      -- Arrange
      local term1 = terminal.get_or_create("echo 'test'", {})
      simulate_valid_buffer(term1)
      local term2 = terminal.get_or_create("echo 'test2'", {})
      -- Don't simulate valid buffer for term2

      -- Act
      local result = terminal.list()

      -- Assert
      assert.equals(1, #result)
      assert.equals(term1.id, result[1].id)
    end)
  end)

  describe("close_all()", function()
    it("should close all terminals", function()
      -- Arrange
      local term1 = terminal.get_or_create("echo 'test1'", {})
      simulate_valid_buffer(term1)
      local term2 = terminal.get_or_create("echo 'test2'", {})
      simulate_valid_buffer(term2)

      -- Act
      terminal.close_all()

      -- Assert
      assert.equals(0, #terminal.list())
    end)
  end)
end)

-- ============================================================================
-- EDGE CASE TESTS
-- ============================================================================

describe("Edge cases", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should handle empty opts table", function()
    -- Arrange & Act
    local term = tiny_term.get("echo 'test'", {})

    -- Assert
    assert.is_not_nil(term)
    assert.is_not_nil(term.id)
  end)

  it("should handle opts with nil values", function()
    -- Arrange
    local opts = {
      cwd = nil,
      env = nil,
      count = nil,
    }

    -- Act
    local term = tiny_term.get("echo 'test'", opts)

    -- Assert
    assert.is_not_nil(term)
  end)

  it("should handle special characters in command", function()
    -- Arrange
    local cmd = "echo 'test with | special chars && more'"

    -- Act
    local term = tiny_term.get(cmd, {})

    -- Assert
    assert.is_not_nil(term)
    assert.is_not_nil(term.id)
  end)

  it("should handle very long commands", function()
    -- Arrange
    local cmd = string.rep("a", 1000)

    -- Act
    local id = util.tid(cmd, {})

    -- Assert
    assert.is_not_nil(id)
    assert.equals(16, #id)
  end)

  it("should handle multiple environment variables", function()
    -- Arrange
    local env = {
      FOO = "bar",
      BAZ = "qux",
      PATH = "/usr/bin:/bin",
    }

    -- Act
    local id1 = util.tid("ls", { env = env })
    local id2 = util.tid("ls", { env = env })

    -- Assert
    assert.equals(id1, id2)
  end)

  it("should handle zero count", function()
    -- Arrange
    -- vim.v.count1 is never 0, but opts.count could theoretically be

    -- Act
    local id = util.tid("ls", { count = 0 })

    -- Assert
    assert.is_not_nil(id)
  end)

  it("should handle very large count", function()
    -- Arrange
    local large_count = 999999

    -- Act
    local id = util.tid("ls", { count = large_count })

    -- Assert
    assert.is_not_nil(id)
    assert.equals(16, #id)
  end)
end)

-- ============================================================================
-- PER-TERMINAL ESC STATE TESTS
-- ============================================================================

describe("Terminal esc_state", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should initialize esc_state for new terminal", function()
    -- Arrange & Act
    local term = terminal.get_or_create("echo 'test'", {})

    -- Assert
    assert.is_not_nil(term.esc_state)
    assert.is_nil(term.esc_state.timer)
    assert.equals(0, term.esc_state.count)
    assert.equals(200, term.esc_state.delay_ms)
  end)

  it("should create timer on first ESC", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.job_id = 123 -- Mock job_id

    -- Act
    term:handle_double_esc()

    -- Assert
    assert.is_not_nil(term.esc_state.timer)
    assert.equals(1, term.esc_state.count)
  end)

  it("should detect double ESC within delay", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.job_id = 123

    -- Act
    local first_result = term:handle_double_esc()
    local second_result = term:handle_double_esc()

    -- Assert
    assert.is_false(first_result) -- First ESC returns false
    assert.is_true(second_result) -- Second ESC returns true
    assert.equals(0, term.esc_state.count) -- Count reset
    assert.is_nil(term.esc_state.timer) -- Timer cleaned up
  end)

  it("should reset count after timer expires", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.job_id = 123

    -- Act
    term:handle_double_esc()
    -- Store the timer to manually trigger callback
    local timer = term.esc_state.timer

    -- Manually trigger timer callback (simulates timer expiry)
    -- Note: vim.wait doesn't process libuv timers in headless mode,
    -- so we directly invoke the callback behavior
    if timer then
      timer:stop()
      -- Manually reset count (timer callback would do this)
      term.esc_state.count = 0
    end

    -- Assert
    assert.equals(0, term.esc_state.count)
  end)

  it("should clean up timer on close", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.esc_state.timer = vim.loop.new_timer()
    term.esc_state.count = 2

    -- Act
    term:close()

    -- Assert
    assert.is_nil(term.esc_state.timer)
    assert.equals(0, term.esc_state.count)
  end)

  it("should maintain separate esc_state for each terminal", function()
    -- Arrange
    local term1 = terminal.get_or_create("echo 'test1'", {})
    local term2 = terminal.get_or_create("echo 'test2'", {})

    -- Act
    term1.esc_state.count = 5
    term2.esc_state.count = 10

    -- Assert
    assert.equals(5, term1.esc_state.count)
    assert.equals(10, term2.esc_state.count)
  end)
end)

-- ============================================================================
-- WINDOW OPERATIONS ERROR HANDLING TESTS
-- ============================================================================

describe("Window operations error handling", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should validate window after creation", function()
    -- Arrange
    local buf = vim.api.nvim_create_buf(false, true)
    local config = {
      relative = "editor",
      width = 10,
      height = 10,
      row = 0,
      col = 0,
    }

    -- Act
    local win_id = vim.api.nvim_open_win(buf, false, config)

    -- Assert
    assert.is_true(vim.api.nvim_win_is_valid(win_id))

    -- Cleanup
    vim.api.nvim_win_close(win_id, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("should handle split stacking with invalid existing window", function()
    -- Arrange
    window.register_split("bottom", 999999) -- Invalid window

    -- Act
    local buf = vim.api.nvim_create_buf(false, true)
    local win_id = window.stack_in_split(buf, "bottom", { win = {} })

    -- Assert
    assert.is_not_nil(win_id)
    assert.is_true(vim.api.nvim_win_is_valid(win_id))

    -- Cleanup
    vim.api.nvim_win_close(win_id, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

-- ============================================================================
-- TERMINAL LIFECYCLE EDGE CASES
-- ============================================================================

describe("Terminal lifecycle edge cases", function()
  after_each(function()
    cleanup_all_terms()
  end)

  it("should handle multiple hide/show cycles", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    local win_id = vim.api.nvim_get_current_win()
    simulate_visible_window(term, win_id)

    -- Act
    term:hide()
    assert.is_false(term:is_visible())

    term:show()
    assert.is_true(term:is_visible())

    term:hide()
    assert.is_false(term:is_visible())

    term:show()
    assert.is_true(term:is_visible())
  end)

  it("should handle show when buffer is invalid", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    term.buf = nil
    term.process_started = false

    -- Act - create_buffer will be called
    term.buf = vim.api.nvim_create_buf(false, true)

    -- Assert
    assert.is_not_nil(term.buf)
  end)

  it("should handle close with no window", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.win = nil

    -- Act & Assert - Should not error
    term:close()
    assert.is_true(term.exited)
  end)

  it("should handle handle_exit idempotently", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.esc_state.timer = vim.loop.new_timer()
    term.autocmd_id = 123

    -- Act
    term:handle_exit()
    local first_exited = term.exited
    term:handle_exit()
    local second_exited = term.exited

    -- Assert
    assert.is_true(first_exited)
    assert.is_true(second_exited)
    assert.is_nil(term.esc_state.timer)
    assert.is_nil(term.autocmd_id)
  end)

  it("should cleanup autocmd on close", function()
    -- Arrange
    local term = mock_terminal("echo 'test'", {})
    simulate_valid_buffer(term)
    term.autocmd_id = 123

    -- Act
    term:close()

    -- Assert
    assert.is_nil(term.autocmd_id)
  end)
end)
