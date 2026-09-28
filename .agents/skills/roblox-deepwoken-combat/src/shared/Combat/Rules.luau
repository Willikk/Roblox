--!strict
--[[
	Rules
	The combat rulebook as pure functions (no services): what may start when, and how a
	hit resolves against the defender's state. Unit-tested under Lune; the server calls
	exactly these functions, so tests cover real gameplay logic.

	States: Idle, Attacking, Blocking, Parrying, Dodging, Stunned, GuardBroken.
	Outcomes: Hit, Blocked, Parried, GuardBreak, Dodged.
]]

local Config = require(script.Parent.Config)

export type State = "Idle" | "Attacking" | "Blocking" | "Parrying" | "Dodging" | "Stunned" | "GuardBroken"
export type Outcome = "Hit" | "Blocked" | "Parried" | "GuardBreak" | "Dodged"
export type Action = "M1" | "Critical" | "Feint" | "Parry" | "Block" | "Dodge"

export type Fighter = {
	state: State,
	stateUntil: number, -- when a timed state (stun, dodge, attack) ends
	phase: "windup" | "active" | "recovery" | "none", -- attack phase
	recoveryStart: number,
	parryStart: number,
	lastParryWhiff: number,
	iframesUntil: number,
	dodgeReadyAt: number,
	feintReadyAt: number,
	posture: number,
	lastPostureHit: number,
	combo: number,
	lastAttackEnd: number,
	hyperArmor: boolean,
}

export type AttackInfo = {
	perilous: boolean?,
	postureDamage: number,
}

local Rules = {}

function Rules.newFighter(): Fighter
	return {
		state = "Idle",
		stateUntil = 0,
		phase = "none",
		recoveryStart = 0,
		parryStart = -math.huge,
		lastParryWhiff = -math.huge,
		iframesUntil = -math.huge,
		dodgeReadyAt = 0,
		feintReadyAt = 0,
		posture = 0,
		lastPostureHit = -math.huge,
		combo = 0,
		lastAttackEnd = -math.huge,
		hyperArmor = false,
	}
end

local function locked(f: Fighter, now: number): boolean
	return (f.state == "Stunned" or f.state == "GuardBroken" or f.state == "Dodging") and now < f.stateUntil
end

-- Whether `action` may start now. Chains are allowed from the end of the previous
-- recovery minus the input buffer.
function Rules.canStart(f: Fighter, action: Action, now: number, cfg: Config.Config): boolean
	if locked(f, now) then
		return false
	end
	local attacking = f.state == "Attacking" and now < f.stateUntil
	if action == "M1" or action == "Critical" then
		if attacking then
			return f.phase == "recovery" and now >= f.recoveryStart - cfg.chainBuffer
		end
		return true
	elseif action == "Feint" then
		return attacking and f.phase == "windup" and now >= f.feintReadyAt
	elseif action == "Parry" then
		return not attacking and now - f.lastParryWhiff >= cfg.parryWhiffCooldown
	elseif action == "Block" then
		return not attacking
	elseif action == "Dodge" then
		-- Roll cancel: a dodge may interrupt your own windup.
		return now >= f.dodgeReadyAt and (not attacking or f.phase == "windup")
	end
	return false
end

-- Next chain index (1-based) for a new M1.
function Rules.nextCombo(f: Fighter, now: number, chainLength: number, cfg: Config.Config): number
	if now - f.lastAttackEnd <= cfg.chainResetTime and f.combo < chainLength and f.combo > 0 then
		return f.combo + 1
	end
	if f.state == "Attacking" and f.combo > 0 and f.combo < chainLength then
		return f.combo + 1 -- buffered input during recovery
	end
	return 1
end

-- Is the attacker inside the defender's guard cone?
function Rules.facing(
	defenderLook: Vector3,
	defenderPosition: Vector3,
	attackerPosition: Vector3,
	angleDeg: number
): boolean
	local toAttacker = attackerPosition - defenderPosition
	local flat = Vector3.new(toAttacker.X, 0, toAttacker.Z)
	local look = Vector3.new(defenderLook.X, 0, defenderLook.Z)
	if flat.Magnitude < 1e-3 or look.Magnitude < 1e-3 then
		return true
	end
	return look.Unit:Dot(flat.Unit) >= math.cos(math.rad(angleDeg))
end

-- Posture after natural regeneration.
function Rules.regenPosture(f: Fighter, now: number, dt: number, cfg: Config.Config): number
	if now - f.lastPostureHit < cfg.postureRegenDelay then
		return f.posture
	end
	return math.max(0, f.posture - cfg.postureRegenRate * dt)
end

--[[
	Resolves an attack landing on a defender at `now`. Returns the outcome and the
	defender's new posture. Order matters and mirrors Deepwoken:
	  i-frames > perilous (only dodge) > parry window > block (posture) > hit.
]]
function Rules.resolve(
	attack: AttackInfo,
	defender: Fighter,
	isFacing: boolean,
	now: number,
	cfg: Config.Config
): (Outcome, number)
	if now < defender.iframesUntil then
		return "Dodged", defender.posture
	end
	if attack.perilous then
		return "Hit", defender.posture
	end
	local guarding = defender.state == "Parrying" or defender.state == "Blocking"
	if guarding and isFacing then
		if defender.state == "Parrying" and now - defender.parryStart <= cfg.parryWindow then
			return "Parried", math.max(0, defender.posture - cfg.parryPostureReward)
		end
		local posture = defender.posture + attack.postureDamage
		if posture >= cfg.postureMax then
			return "GuardBreak", 0
		end
		return "Blocked", posture
	end
	return "Hit", defender.posture
end

return Rules
