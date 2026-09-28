--!strict
-- ServerScriptService.VFXServer.Main: creates the VFX remotes and the batching loop.
local VFXService = require(script.Parent:WaitForChild("VFXService"))

VFXService.start()
