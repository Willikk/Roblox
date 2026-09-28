--!strict
--[[
	DarkGuardBreak: the guard shatters. Big ink burst, scattered ember stars, grit smoke,
	dark-red flash on the victim, long frozen hitstop and a full impact frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = script.Parent.Parent
local ImpactFrame = require(DarkStyle.ImpactFrame)
local Settings = require(DarkStyle.Settings)
local Sprite3D = require(DarkStyle.Sprite3D)
local VFX = ReplicatedStorage:WaitForChild("VFX")
local CameraShaker = require(VFX:WaitForChild("CameraShaker"))
local Hitstop = require(VFX:WaitForChild("Hitstop"))
local Shapes = require(VFX:WaitForChild("Shapes"))
local Types = require(VFX:WaitForChild("Types"))
local VFXMath = require(VFX:WaitForChild("VFXMath"))

local DarkGuardBreak = {} :: Types.Effect
DarkGuardBreak.maxDistance = 320

function DarkGuardBreak.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	local rng = ctx.rng
	Sprite3D.play("InkBurst", position, { scale = 1.1, rotation = rng:NextNumber(0, 360), group = "ui" })
	for _ = 1, 4 do
		local offset = VFXMath.randomInCone(rng, Vector3.yAxis, math.rad(80)) * rng:NextNumber(1, 2.5)
		Sprite3D.play("SparkEmber", position + offset, { scale = 1.3, rotation = rng:NextNumber(0, 90), group = "ui" })
	end
	Sprite3D.play("Smoke", position - Vector3.new(0, 1, 0), { scale = 1.4, lightInfluence = 0.7 })
	if params.target then
		Shapes.highlight(params.target, Color3.fromRGB(150, 20, 18), 0.5, "VFX_DarkGuardBreak", 0.15)
	end
	if ctx.distance < 100 then
		Hitstop.apply({ params.source, params.target }, 0.18, { freezeVFX = true })
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and (params.source == me or params.target == me) then
		CameraShaker.addTrauma(if params.target == me then 0.55 else 0.3)
		CameraShaker.kick(params.cframe.LookVector, 1.3)
		if Settings.impactFrames then
			ImpactFrame.play({ burst = true, frames = 4 })
		end
	end
end

return DarkGuardBreak
