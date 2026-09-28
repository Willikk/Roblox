--!strict
-- StarterPlayerScripts: procedural R6 motion for every visible R6 character.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Controller = require(ReplicatedStorage:WaitForChild("R6Procedural"):WaitForChild("Controller"))

Controller.start()
