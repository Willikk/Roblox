--!strict
--[[
	DarkSlash: brushed pixel crescent with ink outline, rotated to the swing plane.
	params.cframe = slash frame (as for Slash), params.color red -> blood slash (perilous),
	params.power scales the sprite, variant bit 0 = mirrored swing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = script.Parent.Parent
local Sprite3D = require(DarkStyle.Sprite3D)
local Types = require(ReplicatedStorage:WaitForChild("VFX"):WaitForChild("Types"))

local DarkSlash = {} :: Types.Effect
DarkSlash.maxDistance = 350

function DarkSlash.play(params: Types.EffectParams, _ctx: Types.EffectContext)
	local cf = params.cframe
	local mirrored = bit32.band(params.variant, 1) == 1
	local sprite = if params.color and params.color.R > params.color.G * 1.6 then "SlashBlood" else "SlashSteel"
	local rotation = Sprite3D.screenAngle(cf.RightVector) + (if mirrored then 180 else 0)
	Sprite3D.play(sprite, cf.Position + cf.LookVector * 1.2 + cf.UpVector * 0.8, {
		scale = 1.1 * math.sqrt(math.max(params.power, 0.3)) * params.scale,
		rotation = rotation,
		group = "world",
	})
end

return DarkSlash
