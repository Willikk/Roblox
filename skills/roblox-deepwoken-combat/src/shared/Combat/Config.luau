--!strict
--[[
	Config
	Every combat timing in one place (seconds at weapon speed 1). Defaults follow the
	Deepwoken / Sekiro model: parry is the cornerstone (tight window, whiff punished),
	blocking drains posture, a full posture bar = guard break, feints bait parries,
	dodges grant i-frames and can cancel your own windup.
]]

local Config = {
	-- Defense
	parryWindow = 0.18, -- active parry frames after tapping F
	parryWhiffCooldown = 0.65, -- a missed parry cannot be retried immediately (anti-spam)
	parryPostureReward = 12, -- posture recovered by a successful parry
	blockFacingAngle = 100, -- degrees: attacks from behind ignore block/parry
	blockWalkSpeed = 0.55, -- WalkSpeed multiplier while blocking

	-- Posture
	postureMax = 100,
	postureRegenDelay = 1.5,
	postureRegenRate = 18, -- per second
	guardBreakStun = 1.4,

	-- Offense
	chainResetTime = 0.9, -- time after a swing before the M1 chain resets to 1
	chainBuffer = 0.3, -- inputs this early in the previous recovery are queued
	hitStun = 0.45,
	finisherStun = 0.85, -- last hit of a chain
	parriedStun = 0.6, -- attacker stun when parried
	attackWalkSpeed = 0.6,
	stunWalkSpeed = 0.25,
	feintCooldown = 2.2,
	finisherKnockback = 38, -- studs/s

	-- Dodge
	dodgeDuration = 0.38,
	dodgeIFrames = 0.26,
	dodgeCooldown = 1.8,
	dodgeSpeed = 46,

	-- Networking / anti-cheat
	maxRewind = 0.25, -- lag compensation cap (seconds)
	historyLength = 1.5, -- position history kept per character
	hitboxPadding = 1.2, -- body radius added to the hitbox (studs)
	maxInputsPerSecond = 20,
	baseWalkSpeed = 16,
}

export type Config = typeof(Config)

return Config
