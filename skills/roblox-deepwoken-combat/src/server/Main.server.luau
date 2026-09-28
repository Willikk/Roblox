--!strict
-- ServerScriptService.CombatServer.Main: starts the combat authority (+ VFX remotes).
local CombatService = require(script.Parent:WaitForChild("CombatService"))

CombatService.start()
