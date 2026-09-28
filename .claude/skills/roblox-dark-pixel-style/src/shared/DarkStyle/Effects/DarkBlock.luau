--!strict
-- DarkBlock: guarded hit, grey steel spark and a puff of grit, tiny hitstop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = script.Parent.Parent
local Sprite3D = require(DarkStyle.Sprite3D)
local VFX = ReplicatedStorage:WaitForChild("VFX")
local CameraShaker = require(VFX:WaitForChild("CameraShaker"))
local Hitstop = require(VFX:WaitForChild("Hitstop"))
local Types = require(VFX:WaitForChild("Types"))

local DarkBlock = {} :: Types.Effect
DarkBlock.maxDistance = 220

function DarkBlock.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	Sprite3D.play("Spark", position, { scale = 1.1, rotation = ctx.rng:NextNumber(0, 90) })
	Sprite3D.play("Smoke", position - Vector3.new(0, 0.5, 0), { scale = 0.8, lightInfluence = 0.7 })
	if ctx.distance < 90 then
		Hitstop.apply({ params.source, params.target }, 0.04)
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and params.target == me then
		CameraShaker.addTrauma(0.08)
		CameraShaker.kick(params.cframe.LookVector, 0.3)
	end
end

return DarkBlock
