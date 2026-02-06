-- Tests for tiny-term.nvim utility functions
-- Run with: nvim --headless -c "PlenaryBustedDirectory test/"
-- Focus on behavior, not implementation details, using Arrange-Act-Assert pattern

local util = require("tiny-term.util")

-- ============================================================================
-- UTIL.PARSE() TESTS
-- ============================================================================

describe("util.parse()", function()
  describe("Basic parsing behavior", function()
    it("should parse simple command with no arguments", function()
      -- Arrange
      local cmd = "ls"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.is_true(vim.tbl_islist(result))
      assert.equals(1, #result)
      assert.equals("ls", result[1])
    end)

    it("should parse command with multiple arguments", function()
      -- Arrange
      local cmd = "git commit -m 'message'"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(4, #result)
      assert.equals("git", result[1])
      assert.equals("commit", result[2])
      assert.equals("-m", result[3])
      assert.equals("message", result[4])
    end)

    it("should handle tab separators", function()
      -- Arrange
      local cmd = "cmd1\tcmd2\tcmd3"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(3, #result)
      assert.equals("cmd1", result[1])
      assert.equals("cmd2", result[2])
      assert.equals("cmd3", result[3])
    end)

    it("should handle multiple spaces between arguments", function()
      -- Arrange
      local cmd = "echo    hello    world"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(3, #result)
      assert.equals("echo", result[1])
      assert.equals("hello", result[2])
      assert.equals("world", result[3])
    end)
  end)

  describe("Quote handling", function()
    it("should preserve double-quoted strings as single argument", function()
      -- Arrange
      local cmd = 'echo "hello world"'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals("echo", result[1])
      assert.equals("hello world", result[2])
    end)

    it("should handle multiple quoted strings in one command", function()
      -- Arrange
      local cmd = 'echo "first arg" "second arg"'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(3, #result)
      assert.equals("echo", result[1])
      assert.equals("first arg", result[2])
      assert.equals("second arg", result[3])
    end)

    it("should handle quoted strings with spaces before/after", function()
      -- Arrange
      local cmd = '  echo   "hello world"   '

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals("echo", result[1])
      assert.equals("hello world", result[2])
    end)

    it("should handle empty quoted strings", function()
      -- Arrange
      local cmd = 'cmd "" ""'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(3, #result)
      assert.equals("cmd", result[1])
      assert.equals("", result[2])
      assert.equals("", result[3])
    end)

    it("should handle single quoted string inside double quotes", function()
      -- Arrange
      local cmd = [[echo "it's a test"]]

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals([[it's a test]], result[2])
    end)
  end)

  describe("Escape sequence handling", function()
    it("should handle escaped quotes inside quoted strings", function()
      -- Arrange
      local cmd = [[echo "hello \"world\""]]

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals([[hello "world"]], result[2])
    end)

    it("should handle escaped backslashes inside quoted strings", function()
      -- Arrange
      local cmd = [[echo "path\\to\\file"]]

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals([[path\to\file]], result[2])
    end)

    it("should handle multiple escape sequences in one string", function()
      -- Arrange
      local cmd = [[echo "say \"hello\" and \"goodbye\""]]

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals([[say "hello" and "goodbye"]], result[2])
    end)

    it("should preserve backslashes outside quotes", function()
      -- Arrange
      local cmd = [[echo path\to\file]]

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals([[path\to\file]], result[2])
    end)
  end)

  describe("Edge cases", function()
    it("should return empty table for empty string", function()
      -- Arrange
      local cmd = ""

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.is_true(vim.tbl_islist(result))
      assert.equals(0, #result)
    end)

    it("should return empty table for whitespace-only string", function()
      -- Arrange
      local cmd = "   \t\t   "

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(0, #result)
    end)

    it("should handle unclosed quote gracefully", function()
      -- Arrange
      local cmd = 'echo "hello'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      -- Unclosed quote: the rest is treated as unquoted
      assert.equals(2, #result)
      assert.equals("echo", result[1])
      assert.equals("hello", result[2])
    end)

    it("should handle command ending with backslash", function()
      -- Arrange
      local cmd = "echo hello\\"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(2, #result)
      assert.equals("echo", result[1])
      assert.equals("hello\\", result[2])
    end)

    it("should handle special characters in arguments", function()
      -- Arrange
      local cmd = 'echo "$HOME" && ls'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(4, #result)
      assert.equals("$HOME", result[2])
      assert.equals("&&", result[3])
      assert.equals("ls", result[4])
    end)

    it("should handle very long commands", function()
      -- Arrange
      local cmd = "cmd " .. string.rep("arg ", 100)

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(101, #result)
      assert.equals("cmd", result[1])
      assert.equals("arg", result[100])
      assert.equals("arg", result[101])
    end)
  end)

  describe("Table input handling", function()
    it("should return table as-is when input is already a table", function()
      -- Arrange
      local cmd = { "git", "commit", "-m", "message" }

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(cmd, result) -- Same reference
      assert.equals(4, #result)
    end)

    it("should handle empty table input", function()
      -- Arrange
      local cmd = {}

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(cmd, result)
      assert.equals(0, #result)
    end)

    it("should handle table with empty strings", function()
      -- Arrange
      local cmd = { "cmd", "", "arg" }

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(cmd, result)
      assert.equals(3, #result)
      assert.equals("", result[2])
    end)
  end)

  describe("Real-world command examples", function()
    it("should parse git commit command", function()
      -- Arrange
      local cmd = 'git commit -m "fix: handle edge case in parser"'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(4, #result)
      assert.equals("git", result[1])
      assert.equals("commit", result[2])
      assert.equals("-m", result[3])
      assert.equals("fix: handle edge case in parser", result[4])
    end)

    it("should parse npm script command", function()
      -- Arrange
      local cmd = "npm run build -- --watch"

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(5, #result)
      assert.equals("npm", result[1])
      assert.equals("run", result[2])
      assert.equals("build", result[3])
      assert.equals("--", result[4])
      assert.equals("--watch", result[5])
    end)

    it("should parse docker command with multiple flags", function()
      -- Arrange
      local cmd = 'docker run -it --rm -v "$(pwd):/app" node:latest'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(7, #result)
      assert.equals("docker", result[1])
      assert.equals("run", result[2])
      assert.equals("-it", result[3])
      assert.equals("--rm", result[4])
      assert.equals("-v", result[5])
      assert.equals("$(pwd):/app", result[6])
      assert.equals("node:latest", result[7])
    end)

    it("should parse grep command with regex", function()
      -- Arrange
      local cmd = 'grep -r "pattern.*test" --include="*.lua" .'

      -- Act
      local result = util.parse(cmd)

      -- Assert
      assert.equals(5, #result)
      assert.equals("grep", result[1])
      assert.equals("-r", result[2])
      assert.equals("pattern.*test", result[3])
      assert.equals("--include=*.lua", result[4])
      assert.equals(".", result[5])
    end)
  end)
end)
