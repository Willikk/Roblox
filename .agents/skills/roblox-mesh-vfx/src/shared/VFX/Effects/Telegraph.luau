--!strict
--[[
	Telegraph
	Perilous-attack warning (Deepwoken's red flash): the attacker's body flashes red twice
	and a red flare pops at the chest. Played when an unparryable move starts; the
	windup is the reaction time to DODGE. params.source = attacker.
]]

local VFX = script.Parent.Parent
local Animator = require(VFX.Animator)
local Shapes = require(VFX.Shapes)
local Types = require(VFX.Types)

local Telegraph = {} :: Types.Effect
Telegraph.maxDistance = 350

local RED = Color3.fromRGB(255, 40, 40)

function Telegraph.preload()
	Shapes.preload()
end

function Telegraph.play(params: Types.EffectParams, _ctx: Types.EffectContext)
	local source = params.source
	local chest = params.cframe.Position + Vector3.new(0, 0.8, 0)
	if source and source:IsA("Model") then
		local root = source:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			chest = root.Position + Vector3.new(0, 0.8, 0)
		end
		Shapes.highlight(source, RED, 0.22, "VFX_Telegraph", 0.05)
		Animator.delay(0.24, function()
			Shapes.highlight(source, RED, 0.3, "VFX_Telegraph", 0.25)
		end, "ui")
	end
	Shapes.flash(chest, RED, 2.2, 0.2, 10)
end

return Telegraph
