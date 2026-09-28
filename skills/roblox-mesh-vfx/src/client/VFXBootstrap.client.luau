--!strict
-- StarterPlayerScripts: boots the VFX client (remote listeners, pools, preloading).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXClient = require(ReplicatedStorage:WaitForChild("VFX"):WaitForChild("Client"))

VFXClient.start()
