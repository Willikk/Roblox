--!strict
--[[
	Config
	Every tunable of the procedural R6 system, with the reasoning behind the defaults.
	Override at start: Controller.start({ lean = { speedLean = math.rad(8) } })

	Per-character runtime control uses Attributes on the character Model (multipliers
	0..1, default 1): R6_Lean, R6_Terrain, R6_HeadLook, R6_Landing, R6_Breathing,
	R6_Disabled (boolean). Set them from attack/stun code, e.g. HeadLook = 0 while a
	heavy attack animation must not be disturbed. Attributes set by the server replicate.
]]

local Config = {}

Config.defaults = {
	lod = {
		fullRateDistance = 60, -- studs from the camera: sensing every frame
		halfRateDistance = 120, -- sensing at 30 Hz
		lowRateDistance = 200, -- sensing at 15 Hz; beyond: procedural motion disabled
		offscreenInterval = 1 / 10, -- sensing rate for characters outside the view
	},

	sensing = {
		rayLength = 5.5, -- from root height: rest foot (3) + max step-down + margin
		lookAhead = 0.06, -- seconds of velocity used to shift foot rays forward
		groundTolerance = 0.75, -- extra distance still considered "grounded"
		velocitySharpness = 14, -- exp smoothing of position-derived velocity
		accelerationSharpness = 7,
		yawRateSharpness = 10,
	},

	lean = {
		referenceSpeed = 16, -- default WalkSpeed
		speedLean = math.rad(5), -- posture at referenceSpeed
		accelLean = 0.35, -- x atan(a / g)
		bankScale = 0.8, -- x atan(centripetal / g)
		slopeLean = 0.35, -- x slope angle (uphill -> lean in)
		maxForward = math.rad(16),
		maxBackward = math.rad(9),
		maxBank = math.rad(12),
		legCompensation = 0.9, -- 1 = legs stay perfectly vertical (bend at the waist)
		frequency = 2.6, -- spring Hz
		damping = 0.55, -- < 1 gives a small natural overshoot when stopping
	},

	terrain = {
		maxPelvisDrop = 1.2, -- studs; keep < 2 (torso collides with steps beyond)
		maxFootRaise = 1.5,
		maxTuck = 0.6, -- leg slides into the torso first (invisible), then bends
		plantFadeStart = 2.5, -- speed where foot planting starts fading (studs/s)
		plantFadeEnd = 9, -- fully faded: the walk cycle owns the legs
		runningDropWeight = 0.55, -- pelvis drop kept while running (stairs down)
		frequency = 5,
		damping = 0.9,
	},

	head = {
		maxYaw = math.rad(70),
		maxUp = math.rad(45),
		maxDown = math.rad(40),
		backCutoff = math.rad(115), -- target behind the character: relax to neutral
		torsoShare = 0.3, -- part of the yaw taken by the torso (legs counter-twist)
		leanCompensation = 0.8, -- keep the gaze level while leaning
		bankCompensation = 0.7,
		armPitchShare = 0, -- > 0: arms follow the aim pitch (guns, bows)
		frequency = 3.2,
		damping = 1,
		sendRate = 15, -- Hz, local look replication
		sendThreshold = math.rad(1),
	},

	landing = {
		minImpactSpeed = 22, -- studs/s of downward speed before a visible dip
		impulseScale = 0.09,
		maxDip = 1.1,
		frequency = 3,
		damping = 0.4,
	},

	breathing = {
		rate = 0.22, -- breaths per second
		torsoAngle = math.rad(1.1),
		armAngle = math.rad(1.6),
		idleSpeed = 1.5, -- fades out above this speed
	},
}

export type Config = typeof(Config.defaults)

-- Deep-merges `overrides` into a copy of the defaults.
function Config.resolve(overrides: { [string]: any }?): Config
	local function merge(base: any, extra: any): any
		local out = table.clone(base)
		if extra then
			for key, value in extra do
				if type(value) == "table" and type(out[key]) == "table" then
					out[key] = merge(out[key], value)
				else
					out[key] = value
				end
			end
		end
		return out
	end
	return merge(Config.defaults, overrides) :: Config
end

return Config
