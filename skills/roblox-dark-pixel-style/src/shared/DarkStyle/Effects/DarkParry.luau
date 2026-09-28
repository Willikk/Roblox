--!strict
--[[
	DarkParry: steel meets steel. Ember + steel pixel stars, a paper-edged ink burst,
	long hitstop with frozen VFX, and a short speed-line panel for the two fighters.
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
local Types = require(VFX:WaitForChild("Types"))

local DarkParry = {} :: Types.Effect
DarkParry.maxDistance = 300

function DarkParry.play(params: Types.EffectParams, ctx: Types.EffectContext)
	local position = params.cframe.Position
	Sprite3D.play("SparkEmber", position, { scale = 2.4, rotation = ctx.rng:NextNumber(0, 45), group = "ui" })
	Sprite3D.play("Spark", position + Vector3.new(0, 0.3, 0), { scale = 1.6, rotation = 45, group = "ui" })
	Sprite3D.play("InkBurst", position, { scale = 0.55, rotation = ctx.rng:NextNumber(0, 360), group = "ui" })
	if ctx.distance < 90 then
		Hitstop.apply({ params.source, params.target }, 0.14, { freezeVFX = true })
	end
	local me = Players.LocalPlayer and Players.LocalPlayer.Character
	if me and (params.source == me or params.target == me) then
		CameraShaker.addTrauma(0.2)
		CameraShaker.fovPunch(-5)
		if Settings.impactFrames then
			ImpactFrame.play({ burst = false, frames = 3 })
		end
	end
end

return DarkParry
