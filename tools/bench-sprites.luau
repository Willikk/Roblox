--!nocheck
-- Times each procedural sprite generator (runtime cost on a client, interpreter mode).
local process = require("@lune/process")
local harness = require("./test/harness")
local h = harness.new()
local root = h:mount(`{process.cwd}/.claude/skills/roblox-dark-pixel-style/src/shared/DarkStyle`, "DarkStyle")
local SpriteGen = h:require(root.SpriteGen)
local total = 0
for _, entry in SpriteGen.builders() do
	local t0 = os.clock()
	entry.build()
	local ms = (os.clock() - t0) * 1000
	total += ms
	print(string.format("%-12s %6.1f ms", entry.name, ms))
end
print(string.format("total        %6.1f ms", total))
