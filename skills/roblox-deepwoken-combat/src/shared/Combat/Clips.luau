--!strict
--[[
	Clips
	Registers every weapon move as a PoseLibrary clip (R6 procedural skill), generated from
	the move timings so the animation's strike frame IS the hitbox window.
	Call Clips.registerAll() once on every client (the server only sets attributes).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Weapons = require(script.Parent.Weapons)
local PoseLibrary = require(ReplicatedStorage:WaitForChild("R6Procedural"):WaitForChild("PoseLibrary"))

local Clips = {}

local registered = false

local function toPose(spec: Weapons.PoseSpec): PoseLibrary.Pose
	return (spec :: any) :: PoseLibrary.Pose
end

function Clips.blockName(weapon: Weapons.Weapon): string
	return weapon.name .. "_Block"
end

function Clips.parryName(weapon: Weapons.Weapon): string
	return weapon.name .. "_Parry"
end

function Clips.registerAll()
	if registered then
		return
	end
	registered = true
	for _, name in { "Fists", "Sword" } do
		local weapon = Weapons.get(name)
		if weapon == nil then
			continue
		end
		local moves = table.clone(weapon.chain)
		table.insert(moves, weapon.critical)
		for _, move in moves do
			local windup, active, recovery = Weapons.timing(weapon, move)
			PoseLibrary.register(
				move.name,
				PoseLibrary.attack({
					windup = toPose(move.poses.windup),
					strike = toPose(move.poses.strike),
					follow = if move.poses.follow then toPose(move.poses.follow) else nil,
				}, { windup = windup, active = active, recovery = recovery })
			)
		end
		PoseLibrary.register(Clips.blockName(weapon), PoseLibrary.hold(toPose(weapon.blockPose), 0.08))
		PoseLibrary.register(Clips.parryName(weapon), PoseLibrary.reaction(toPose(weapon.parryPose), 0.05, 0.32))
	end
end

return Clips
