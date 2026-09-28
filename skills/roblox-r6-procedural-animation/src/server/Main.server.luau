--!strict
-- ServerScriptService.R6ProceduralServer.Main: starts the head-look relay.
local LookRelay = require(script.Parent:WaitForChild("LookRelay"))

LookRelay.start()
