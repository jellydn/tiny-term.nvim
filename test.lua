-- Test runner for tiny-term.nvim using Plenary
-- This file is used by LuaRocks test command

local result = os.execute("nvim --headless -c 'PlenaryBustedDirectory test/' -c 'qa!'")

if not result or result ~= 0 then
  print("Tests failed!")
  os.exit(1)
end

print("All tests passed!")
os.exit(0)
