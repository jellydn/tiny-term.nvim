rockspec_format = "3.0"
package = "tiny-term.nvim"
version = "1.0.0-1"
description = {
  summary = "A minimal terminal toggle plugin for Neovim",
  detailed = [[
    tiny-term.nvim is a minimal terminal toggle plugin for Neovim 0.11+.
    It provides a drop-in replacement API compatible with Snacks.terminal.
  ]],
  license = "MIT",
  homepage = "https://github.com/jellydn/tiny-term.nvim",
  issues_url = "https://github.com/jellydn/tiny-term.nvim/issues",
}
dependencies = {
  "lua >= 5.1",
}
source = {
  url = "git+https://github.com/jellydn/tiny-term.nvim",
  tag = "v1.0.0",
}
build = {
  type = "builtin",
  modules = {
    ["tiny-term"] = "lua/tiny-term/init.lua",
  },
  copy_directories = {
    "plugin",
    "doc",
  },
}
test_dependencies = {
  "nlua",
}
test = {
  type = "command",
  test = "test.lua",
}
