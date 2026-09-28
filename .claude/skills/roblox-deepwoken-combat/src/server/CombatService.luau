--!strict
--[[
	CombatService (server authority)
	Deepwoken-style melee: M1 chains, criticals (perilous = red flash, dodge only), feints,
	parry (tap F) / block (hold F) with posture and guard breaks, dodges with i-frames and
	roll-cancel, hitstun, finisher knockback, lag-compensated hitboxes.

	Clients send INTENT only ("M1", clientTime). The server checks Rules, runs the timers,
	rewinds defenders to the attacker's view (capped), resolves outcomes with Rules.resolve,
	applies damage/stun, and drives:
	  * animation: attributes R6_Action / R6_ActionStart read by every client (ActionPose);
	  * VFX: VFXService (Slash, ImpactBurst, FistImpact, Parry, Block, GuardBreak, Telegraph);
	  * HUD: attributes Posture, PostureMax, CombatState, Weapon.

	NPCs use the same code path: CombatService.act(model, action, arg).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat:WaitForChild("Config"))
local Hitbox = require(Combat:WaitForChild("Hitbox"))
local Rules = require(Combat:WaitForChild("Rules"))
local Weapons = require(Combat:WaitForChild("Weapons"))
local VFXService = require(ServerScriptService:WaitForChild("VFXServer"):WaitForChild("VFXService"))

type Entity = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	player: Player?,
	fighter: Rules.Fighter,
	weapon: Weapons.Weapon,
	actionId: number,
	history: Hitbox.History,
	guardHeld: boolean,
	inputWindowStart: number,
	inputCount: number,
	lastPostureSent: number,
}

local CombatService = {}
CombatService.NPC_TAG = "CombatNPC"

local cfg = Config
local entities: { [Model]: Entity } = {}
local knockbackRemote: RemoteEvent? = nil
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setAction(e: Entity, clip: string)
	e.model:SetAttribute("R6_Action", clip)
	e.model:SetAttribute("R6_ActionStart", now())
end

local function updateWalkSpeed(e: Entity)
	local f = e.fighter
	local mult = 1
	if f.state == "Attacking" then
		mult = cfg.attackWalkSpeed
	elseif f.state == "Blocking" or f.state == "Parrying" then
		mult = cfg.blockWalkSpeed
	elseif f.state == "Stunned" or f.state == "GuardBroken" then
		mult = cfg.stunWalkSpeed
	end
	e.humanoid.WalkSpeed = cfg.baseWalkSpeed * mult
	e.model:SetAttribute("CombatState", f.state)
end

local function setState(e: Entity, state: Rules.State, duration: number?)
	e.fighter.state = state
	e.fighter.stateUntil = if duration then now() + duration else math.huge
	if state ~= "Attacking" then
		e.fighter.phase = "none"
		e.fighter.hyperArmor = false
	end
	updateWalkSpeed(e)
end

local function knockback(e: Entity, velocity: Vector3)
	if e.player then
		if knockbackRemote then
			knockbackRemote:FireClient(e.player, velocity)
		end
	else
		e.root:ApplyImpulse(velocity * e.root.AssemblyMass)
	end
end

local function flatDirection(from: Vector3, to: Vector3): Vector3
	local d = to - from
	d = Vector3.new(d.X, 0, d.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.zAxis
end

-- Interrupts whatever the entity was doing (pending strikes are cancelled by actionId).
local function stun(e: Entity, duration: number, clip: string, state: Rules.State?)
	e.actionId += 1
	e.guardHeld = false
	setState(e, state or "Stunned", duration)
	setAction(e, clip)
end

local function slashFrame(root: CFrame, move: Weapons.Move): CFrame
	return root * CFrame.new(0, 0.6, -2.4) * CFrame.Angles(0, 0, math.rad(move.slashTilt or 0))
end

local function resolveHit(a: Entity, d: Entity, move: Weapons.Move, isCritical: boolean)
	local t = now()
	local isFacing = Rules.facing(d.root.CFrame.LookVector, d.root.Position, a.root.Position, cfg.blockFacingAngle)
	local outcome, posture =
		Rules.resolve({ perilous = move.perilous, postureDamage = move.postureDamage }, d.fighter, isFacing, t, cfg)
	d.fighter.posture = posture
	local direction = flatDirection(a.root.Position, d.root.Position)
	local hitPosition = d.root.Position - direction * 0.9 + Vector3.new(0, 0.6, 0)
	local hitFrame = CFrame.lookAt(hitPosition, hitPosition + direction)

	if outcome == "Dodged" then
		return
	elseif outcome == "Parried" then
		d.fighter.lastParryWhiff = -math.huge -- a successful parry is never punished
		stun(a, cfg.parriedStun, "Parried")
		VFXService.play(
			Config.effect("Parry", "Parry"),
			{ cframe = hitFrame, source = d.model, target = a.model, power = 1.5 }
		)
	elseif outcome == "Blocked" then
		d.fighter.lastPostureHit = t
		knockback(d, direction * 10)
		VFXService.play(
			Config.effect("Block", "Block"),
			{ cframe = hitFrame, source = a.model, target = d.model, power = 1 }
		)
	elseif outcome == "GuardBreak" then
		d.fighter.lastPostureHit = t
		stun(d, cfg.guardBreakStun, "GuardBroken", "GuardBroken")
		knockback(d, direction * 18)
		VFXService.play(
			Config.effect("GuardBreak", "GuardBreak"),
			{ cframe = hitFrame, source = a.model, target = d.model, power = 2 }
		)
	else -- Hit
		d.humanoid:TakeDamage(move.damage)
		local armored = d.fighter.hyperArmor and d.fighter.phase == "windup"
		if not armored then
			stun(d, if move.finisher then cfg.finisherStun else cfg.hitStun, "Stagger")
		end
		if move.knockback then
			knockback(d, direction * move.knockback + Vector3.new(0, move.knockback * 0.35, 0))
		end
		local heavy = move.finisher == true or isCritical
		VFXService.play(Config.effect("Hit", a.weapon.hitEffect), {
			cframe = hitFrame,
			source = a.model,
			target = d.model,
			power = math.clamp(move.damage / 8, 0.6, 3),
			variant = if heavy then 1 else 0,
		})
	end
	d.model:SetAttribute("Posture", math.floor(d.fighter.posture + 0.5))
end

local function strike(e: Entity, move: Weapons.Move, rewindTime: number, isCritical: boolean)
	local box = Hitbox.boxFor(e.root.CFrame, move.hitboxForward)
	if move.vfx == "Slash" then
		VFXService.play(Config.effect("Slash", "Slash"), {
			cframe = slashFrame(e.root.CFrame, move),
			power = if isCritical then 2.2 else 1.2,
			variant = if move.slashMirror then 1 else 0,
			color = if move.perilous then Color3.fromRGB(255, 70, 60) else nil,
			source = e.model,
		}, { exclude = e.player }) -- the attacker predicted it
	end
	for model, d in entities do
		if model == e.model or d.humanoid.Health <= 0 then
			continue
		end
		local past = Hitbox.sample(d.history, rewindTime) or d.root.CFrame
		if Hitbox.contains(box, move.hitboxSize, past.Position, cfg.hitboxPadding) then
			resolveHit(e, d, move, isCritical)
		end
	end
end

local function startAttack(e: Entity, critical: boolean, clientTime: number?)
	local f = e.fighter
	local t = now()
	if not Rules.canStart(f, if critical then "Critical" else "M1", t, cfg) then
		return
	end
	local weapon = e.weapon
	local move: Weapons.Move
	if critical then
		move = weapon.critical
		f.combo = 0
	else
		local index = Rules.nextCombo(f, t, #weapon.chain, cfg)
		move = weapon.chain[index]
		f.combo = index
	end
	local windup, active, recovery = Weapons.timing(weapon, move)
	e.actionId += 1
	local id = e.actionId
	e.guardHeld = false
	setState(e, "Attacking", windup + active + recovery)
	f.phase = "windup"
	f.recoveryStart = t + windup + active
	f.hyperArmor = move.hyperArmor == true
	setAction(e, move.name)
	if move.perilous then
		VFXService.play(
			Config.effect("Telegraph", "Telegraph"),
			{ cframe = e.root.CFrame, source = e.model, power = 1 }
		)
	end

	-- Lag compensation: rewind defenders to what the attacker saw at strike time, capped.
	local sent = if type(clientTime) == "number" and clientTime == clientTime then clientTime else t
	local offset = math.clamp(t - sent, 0, cfg.maxRewind)

	task.delay(windup, function()
		if e.actionId ~= id then
			return -- feinted, dodged or interrupted
		end
		f.phase = "active"
		strike(e, move, now() - offset, critical)
	end)
	task.delay(windup + active, function()
		if e.actionId == id then
			f.phase = "recovery"
		end
	end)
	task.delay(windup + active + recovery, function()
		if e.actionId == id then
			f.lastAttackEnd = now()
			if move.finisher then
				f.combo = 0
			end
			setState(e, "Idle")
		end
	end)
end

local function feint(e: Entity)
	local t = now()
	if not Rules.canStart(e.fighter, "Feint", t, cfg) then
		return
	end
	e.actionId += 1
	e.fighter.feintReadyAt = t + cfg.feintCooldown
	setState(e, "Idle")
	setAction(e, "")
end

local function guardDown(e: Entity)
	local t = now()
	e.guardHeld = true
	if not Rules.canStart(e.fighter, "Parry", t, cfg) then
		if Rules.canStart(e.fighter, "Block", t, cfg) then
			setState(e, "Blocking")
			setAction(e, e.weapon.name .. "_Block")
		end
		return
	end
	e.fighter.parryStart = t
	setState(e, "Parrying")
	setAction(e, e.weapon.name .. "_Parry")
end

local function guardUp(e: Entity)
	e.guardHeld = false
	if e.fighter.state == "Blocking" then
		setState(e, "Idle")
		setAction(e, "")
	end
end

local function dodge(e: Entity, direction: Vector3?)
	local f = e.fighter
	local t = now()
	if not Rules.canStart(f, "Dodge", t, cfg) then
		return
	end
	e.actionId += 1 -- roll cancel
	e.guardHeld = false
	local dir = if direction and direction.Magnitude > 0.1
		then flatDirection(Vector3.zero, direction)
		else -e.root.CFrame.LookVector
	setState(e, "Dodging", cfg.dodgeDuration)
	f.iframesUntil = t + cfg.dodgeIFrames
	f.dodgeReadyAt = t + cfg.dodgeCooldown
	local localDir = e.root.CFrame:VectorToObjectSpace(dir)
	local clip = if math.abs(localDir.X) > math.abs(localDir.Z)
		then (if localDir.X < 0 then "DodgeLeft" else "DodgeRight")
		else "DodgeBack"
	setAction(e, clip)
	if e.player == nil then
		e.root:ApplyImpulse(dir * cfg.dodgeSpeed * e.root.AssemblyMass) -- NPCs; players move themselves
	end
end

local function equipBlade(e: Entity)
	local existing = e.model:FindFirstChild("CombatBlade")
	if existing then
		existing:Destroy()
	end
	if not e.weapon.hasBlade then
		return
	end
	local arm = e.model:FindFirstChild("Right Arm")
	if arm == nil or not arm:IsA("BasePart") then
		return
	end
	local spec = e.weapon.blade
	local size = if spec then spec.size else Vector3.new(0.14, 0.45, 4.4)
	local blade = Instance.new("Part")
	blade.Name = "CombatBlade"
	blade.Size = size
	blade.Material = if spec then spec.material else Enum.Material.Metal
	blade.Color = if spec then spec.color else Color3.fromRGB(200, 205, 215)
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.Massless = true
	local weld = Instance.new("Weld")
	weld.Part0 = arm
	weld.Part1 = blade
	weld.C0 = CFrame.new(0, -1.05, -size.Z / 2 + 0.2) -- held in the fist, blade forward
	weld.Parent = blade
	-- Trail between base and tip; clients enable it during active frames.
	local base = Instance.new("Attachment")
	base.Name = "TrailBase"
	base.Position = Vector3.new(0, 0, size.Z * 0.36)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "TrailTip"
	tip.Position = Vector3.new(0, 0, -size.Z * 0.5)
	tip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = 0.16
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(215, 235, 255))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Enabled = false
	trail.Parent = blade
	blade.Parent = e.model
end

local function equip(e: Entity, weaponName: string)
	local weapon = Weapons.get(weaponName)
	if weapon == nil or e.fighter.state ~= "Idle" then
		return
	end
	e.weapon = weapon
	e.fighter.combo = 0
	e.model:SetAttribute("Weapon", weapon.name)
	equipBlade(e)
end

-- Public API: same entry point for players (via remote) and NPC AI.
function CombatService.act(model: Model, action: string, arg: any)
	local e = entities[model]
	if e == nil or e.humanoid.Health <= 0 then
		return
	end
	if action == "M1" then
		startAttack(e, false, arg)
	elseif action == "Critical" then
		startAttack(e, true, arg)
	elseif action == "Feint" then
		feint(e)
	elseif action == "GuardDown" then
		guardDown(e)
	elseif action == "GuardUp" then
		guardUp(e)
	elseif action == "Dodge" then
		dodge(e, if typeof(arg) == "Vector3" then arg else nil)
	elseif action == "Equip" and type(arg) == "string" then
		equip(e, arg)
	end
end

function CombatService.register(model: Model, player: Player?)
	local humanoid = model:WaitForChild("Humanoid", 10)
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if humanoid == nil or root == nil or not humanoid:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	local e: Entity = {
		model = model,
		humanoid = humanoid,
		root = root,
		player = player,
		fighter = Rules.newFighter(),
		weapon = Weapons.Fists,
		actionId = 0,
		history = Hitbox.newHistory(math.ceil(cfg.historyLength * 60)),
		guardHeld = false,
		inputWindowStart = 0,
		inputCount = 0,
		lastPostureSent = -1,
	}
	entities[model] = e
	model:SetAttribute("PostureMax", cfg.postureMax)
	model:SetAttribute("Posture", 0)
	model:SetAttribute("Weapon", e.weapon.name)
	updateWalkSpeed(e)
	humanoid.Died:Connect(function()
		entities[model] = nil
	end)
	model.Destroying:Connect(function()
		entities[model] = nil
	end)
end

local function allowInput(e: Entity): boolean
	local t = os.clock()
	if t - e.inputWindowStart >= 1 then
		e.inputWindowStart, e.inputCount = t, 0
	end
	e.inputCount += 1
	return e.inputCount <= cfg.maxInputsPerSecond
end

local VALID_ACTIONS =
	{ M1 = true, Critical = true, Feint = true, GuardDown = true, GuardUp = true, Dodge = true, Equip = true }

local function onHeartbeat(dt: number)
	local t = now()
	for _, e in entities do
		Hitbox.push(e.history, t, e.root.CFrame)
		local f = e.fighter
		-- Timed states expire.
		if (f.state == "Stunned" or f.state == "GuardBroken" or f.state == "Dodging") and t >= f.stateUntil then
			setState(e, "Idle")
			if e.guardHeld then
				guardDown(e)
			end
		elseif f.state == "Parrying" and t - f.parryStart > cfg.parryWindow then
			if e.guardHeld then
				setState(e, "Blocking")
				setAction(e, e.weapon.name .. "_Block")
			else
				f.lastParryWhiff = f.parryStart -- tapped and missed: short lockout
				setState(e, "Idle")
			end
		end
		-- Posture.
		f.posture = Rules.regenPosture(f, t, dt, cfg)
		local rounded = math.floor(f.posture + 0.5)
		if rounded ~= e.lastPostureSent then
			e.lastPostureSent = rounded
			e.model:SetAttribute("Posture", rounded)
		end
	end
end

function CombatService.start()
	if started then
		return
	end
	started = true
	VFXService.start()

	local folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	local input = Instance.new("RemoteEvent")
	input.Name = "Input"
	input.Parent = folder
	local kb = Instance.new("RemoteEvent")
	kb.Name = "Knockback"
	kb.Parent = folder
	folder.Parent = ReplicatedStorage
	knockbackRemote = kb

	input.OnServerEvent:Connect(function(player: Player, action: unknown, arg: unknown)
		local character = player.Character
		local e = character and entities[character]
		if e == nil or type(action) ~= "string" or not VALID_ACTIONS[action] or not allowInput(e) then
			return
		end
		if typeof(arg) == "Vector3" then
			local v = arg :: Vector3
			if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then
				return
			end
		elseif type(arg) == "number" and arg ~= arg then
			return
		end
		CombatService.act(character :: Model, action, arg)
	end)

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			CombatService.register(character, player)
		end)
		if player.Character then
			task.spawn(CombatService.register, player.Character, player)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	for _, model in CollectionService:GetTagged(CombatService.NPC_TAG) do
		if model:IsA("Model") then
			task.spawn(CombatService.register, model, nil)
		end
	end
	CollectionService:GetInstanceAddedSignal(CombatService.NPC_TAG):Connect(function(model)
		if model:IsA("Model") then
			CombatService.register(model, nil)
		end
	end)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return CombatService
