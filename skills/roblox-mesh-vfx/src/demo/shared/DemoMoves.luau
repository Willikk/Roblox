--!strict
--[[
	DemoMoves
	Move geometry shared by the demo client (prediction) and server (authority), so both
	compute the same frames from the same inputs. Real games keep this pattern: the
	client never sends positions, only intent (+ a seed); the server recomputes.
]]

local DemoMoves = {}

DemoMoves.COOLDOWNS = {
	Slash = 0.28,
	GroundSlam = 1.1,
}

-- Alternating diagonal slashes: variant bit 0 mirrors the sweep and the tilt.
function DemoMoves.slashFrame(root: CFrame, variant: number): CFrame
	local tilt = if bit32.band(variant, 1) == 1 then math.rad(-28) else math.rad(28)
	return root * CFrame.new(0, 0.6, -2.4) * CFrame.Angles(0, 0, tilt)
end

function DemoMoves.groundSlamFrame(root: CFrame): CFrame
	return root * CFrame.new(0, -2.5, -7)
end

-- Hit box in front of the attacker (server-side only in the demo).
function DemoMoves.hitBox(root: CFrame): (CFrame, Vector3)
	return root * CFrame.new(0, 0, -3.8), Vector3.new(6, 6, 6)
end

return DemoMoves
