--!strict
--[[
	DarkTelegraph: perilous-attack warning. A pulsing red pixel eye above the attacker and
	two dark-red body flashes. Its duration covers the windup: the window to DODGE.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DarkStyle = script.Parent.Parent
local Sprite3D = require(DarkStyle.Sprite3D)
local VFX = ReplicatedStorage:WaitForChild("VFX")
local Animator = require(VFX:WaitForChild("Animator"))
local Shapes = require(VFX:WaitForChild("Shapes"))
local Types = require(VFX:WaitForChild("Types"))

local DarkTelegraph = {} :: Types.Effect
DarkTelegraph.maxDistance = 350

local RED = Color3.fromRGB(200, 20, 20)

function DarkTelegraph.play(params: Types.EffectParams, _ctx: Types.EffectContext)
	local source = params.source
	local head = params.cframe.Position + Vector3.new(0, 3.6, 0)
	if source and source:IsA("Model") then
		local h = source:FindFirstChild("Head")
		if h and h:IsA("BasePart") then
			head = h.Position + Vector3.new(0, 2, 0)
		end
		Shapes.highlight(source, RED, 0.2, "VFX_DarkTelegraph", 0.1)
		Animator.delay(0.25, function()
			Shapes.highlight(source, RED, 0.25, "VFX_DarkTelegraph", 0.3)
		end, "ui")
	end
	Sprite3D.play("DangerEye", head, { scale = 1.4, lifetime = 0.7, loop = true, group = "ui" })
end

return DarkTelegraph
