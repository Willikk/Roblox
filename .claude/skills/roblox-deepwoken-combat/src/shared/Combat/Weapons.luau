--!strict
--[[
	Weapons
	Pure data: every move's timing, damage, posture damage, hitbox and procedural poses.
	The same table drives the server (hit windows), the animation (clips generated from the
	timings, see Clips.luau) and the VFX, so they can never drift apart.

	Pose angles (degrees, Part0 space) — see PoseLibrary conventions:
	  shoulders X+ = arm forward (90 horizontal, 170 overhead), right arm Z+ = outward,
	  left arm Z+ = inward; RootJoint X+ = lean back, Y+ = twist left.
	Weapon profiles follow Deepwoken classes: fists = light (fast, short, low damage),
	sword = medium (balanced).
]]

export type Rot = { number }
export type PoseSpec = { [string]: { rot: Vector3, pos: Vector3? } }

export type Move = {
	name: string, -- unique clip name, e.g. "Sword_M1_1"
	windup: number,
	active: number,
	recovery: number,
	damage: number,
	postureDamage: number,
	hitboxSize: Vector3, -- width, height, depth (depth = reach)
	hitboxForward: number, -- center distance in front of the root
	knockback: number?, -- studs/s applied to the victim on hit
	finisher: boolean?, -- last chain hit: longer stun + knockback
	perilous: boolean?, -- red flash: cannot be parried or blocked, only dodged
	hyperArmor: boolean?, -- not interrupted by hits during windup
	vfx: string, -- VFX effect played at the strike ("Slash" or "none")
	slashTilt: number?, -- degrees, slash plane roll (sword arcs)
	slashMirror: boolean?,
	poses: { windup: PoseSpec, strike: PoseSpec, follow: PoseSpec? },
}

export type Weapon = {
	name: string,
	speed: number, -- global timing multiplier (higher = faster)
	chain: { Move },
	critical: Move,
	blockPose: PoseSpec,
	parryPose: PoseSpec,
	hitEffect: string, -- VFX on a clean hit ("ImpactBurst" / "FistImpact")
	hasBlade: boolean,
}

local function r(x: number, y: number, z: number, pos: Vector3?): { rot: Vector3, pos: Vector3? }
	return { rot = Vector3.new(x, y, z), pos = pos }
end

local Weapons = {}

local function m(move: Move): Move
	return move
end

Weapons.Fists = (
	{
		name = "Fists",
		speed = 1.18,
		hitEffect = "FistImpact",
		hasBlade = false,
		chain = {
			m({
				name = "Fists_M1_1", -- left jab
				windup = 0.23,
				active = 0.09,
				recovery = 0.2,
				damage = 6,
				postureDamage = 9,
				hitboxSize = Vector3.new(4, 5, 5),
				hitboxForward = 3,
				vfx = "none",
				poses = {
					windup = { LeftShoulder = r(65, 0, 6), RightShoulder = r(85, 0, -22), RootJoint = r(0, -12, 0) },
					strike = {
						LeftShoulder = r(96, 0, 10),
						RightShoulder = r(80, 0, -25),
						RootJoint = r(-6, 16, 0, Vector3.new(0, 0, -0.25)),
					},
				},
			}),
			m({
				name = "Fists_M1_2", -- right cross
				windup = 0.24,
				active = 0.09,
				recovery = 0.21,
				damage = 7,
				postureDamage = 10,
				hitboxSize = Vector3.new(4, 5, 5),
				hitboxForward = 3,
				vfx = "none",
				poses = {
					windup = { RightShoulder = r(65, 0, 8), LeftShoulder = r(88, 0, 18), RootJoint = r(0, 16, 0) },
					strike = {
						RightShoulder = r(96, 0, -12),
						LeftShoulder = r(60, 0, 10),
						RootJoint = r(-8, -30, 0, Vector3.new(0, 0, -0.35)),
					},
				},
			}),
			m({
				name = "Fists_M1_3", -- left hook
				windup = 0.23,
				active = 0.1,
				recovery = 0.22,
				damage = 7,
				postureDamage = 11,
				hitboxSize = Vector3.new(6, 5, 5),
				hitboxForward = 2.8,
				vfx = "none",
				poses = {
					windup = { LeftShoulder = r(70, 0, -55), RightShoulder = r(85, 0, -20), RootJoint = r(0, 22, 0) },
					strike = { LeftShoulder = r(92, 0, 42), RightShoulder = r(75, 0, -15), RootJoint = r(-6, -32, 0) },
				},
			}),
			m({
				name = "Fists_M1_4", -- right uppercut (finisher)
				windup = 0.27,
				active = 0.11,
				recovery = 0.3,
				damage = 9,
				postureDamage = 14,
				hitboxSize = Vector3.new(4, 6, 5),
				hitboxForward = 3,
				knockback = 30,
				finisher = true,
				vfx = "none",
				poses = {
					windup = {
						RightShoulder = r(15, 0, 12),
						RootJoint = r(-12, -10, 0, Vector3.new(0, -0.45, 0)),
						LeftHip = r(20, 0, 0),
						RightHip = r(-10, 0, 0),
					},
					strike = {
						RightShoulder = r(168, 0, -12),
						LeftShoulder = r(40, 0, 0),
						RootJoint = r(10, -18, 0, Vector3.new(0, 0.25, -0.2)),
						Neck = r(14, 0, 0),
					},
				},
			}),
		},
		critical = m({
			name = "Fists_Critical", -- charged haymaker
			windup = 0.55,
			active = 0.12,
			recovery = 0.4,
			damage = 16,
			postureDamage = 40,
			hitboxSize = Vector3.new(5, 6, 6),
			hitboxForward = 3.4,
			knockback = 45,
			finisher = true,
			hyperArmor = true,
			vfx = "none",
			poses = {
				windup = {
					RightShoulder = r(40, 0, 75),
					LeftShoulder = r(80, 0, 30),
					RootJoint = r(4, 42, 0, Vector3.new(0, -0.2, 0.3)),
				},
				strike = {
					RightShoulder = r(96, 0, -28),
					LeftShoulder = r(30, 0, -20),
					RootJoint = r(-12, -42, 0, Vector3.new(0, -0.25, -0.7)),
					LeftHip = r(30, 0, 0),
					RightHip = r(-25, 0, 0),
				},
			},
		}),
		blockPose = {
			RightShoulder = r(122, 0, -34),
			LeftShoulder = r(122, 0, 34),
			Neck = r(-12, 0, 0),
			RootJoint = r(-6, 0, 0),
		},
		parryPose = { LeftShoulder = r(135, 0, -45), RightShoulder = r(110, 0, -30), RootJoint = r(4, 14, 0) },
	} :: any
) :: Weapon

Weapons.Sword = (
	{
		name = "Sword",
		speed = 1,
		hitEffect = "ImpactBurst",
		hasBlade = true,
		chain = {
			m({
				name = "Sword_M1_1", -- diagonal right-to-left
				windup = 0.28,
				active = 0.12,
				recovery = 0.26,
				damage = 11,
				postureDamage = 15,
				hitboxSize = Vector3.new(9, 6, 8),
				hitboxForward = 4,
				vfx = "Slash",
				slashTilt = 35,
				poses = {
					windup = { RightShoulder = r(150, 0, 55), RootJoint = r(0, -26, 0), Neck = r(0, 10, 0) },
					strike = {
						RightShoulder = r(62, 0, -38),
						LeftShoulder = r(-15, 0, 0),
						RootJoint = r(-8, 30, 0, Vector3.new(0, 0, -0.3)),
					},
					follow = { RightShoulder = r(40, 0, -48), RootJoint = r(-6, 34, 0) },
				},
			}),
			m({
				name = "Sword_M1_2", -- horizontal backhand left-to-right
				windup = 0.27,
				active = 0.12,
				recovery = 0.26,
				damage = 11,
				postureDamage = 15,
				hitboxSize = Vector3.new(10, 5, 8),
				hitboxForward = 4,
				vfx = "Slash",
				slashTilt = -8,
				slashMirror = true,
				poses = {
					-- Horizontal swing: raise the arm forward (X 90), sweep it with Y (left -> right).
					windup = { RightShoulder = r(92, 34, 0), RootJoint = r(0, 36, 0) },
					strike = { RightShoulder = r(92, -8, 0), RootJoint = r(-6, -32, 0, Vector3.new(0, 0, -0.3)) },
					follow = { RightShoulder = r(86, -30, 0), RootJoint = r(-4, -36, 0) },
				},
			}),
			m({
				name = "Sword_M1_3", -- overhead
				windup = 0.3,
				active = 0.12,
				recovery = 0.28,
				damage = 12,
				postureDamage = 17,
				hitboxSize = Vector3.new(6, 7, 8.5),
				hitboxForward = 4.2,
				vfx = "Slash",
				slashTilt = 90,
				poses = {
					windup = {
						RightShoulder = r(178, 0, 8),
						LeftShoulder = r(165, 0, -8),
						RootJoint = r(10, 0, 0),
						Neck = r(8, 0, 0),
					},
					strike = {
						RightShoulder = r(55, 0, -4),
						LeftShoulder = r(48, 0, 4),
						RootJoint = r(-20, 0, 0, Vector3.new(0, -0.25, -0.4)),
						LeftHip = r(18, 0, 0),
						RightHip = r(-12, 0, 0),
					},
				},
			}),
			m({
				name = "Sword_M1_4", -- lunging thrust (finisher)
				windup = 0.32,
				active = 0.12,
				recovery = 0.34,
				damage = 13,
				postureDamage = 20,
				hitboxSize = Vector3.new(4, 5, 10),
				hitboxForward = 5,
				knockback = 34,
				finisher = true,
				vfx = "none",
				poses = {
					windup = { RightShoulder = r(62, 0, 25), RootJoint = r(0, -32, 0, Vector3.new(0, 0, 0.45)) },
					strike = {
						RightShoulder = r(92, 0, -4),
						LeftShoulder = r(-25, 0, -10),
						RootJoint = r(-12, 16, 0, Vector3.new(0, -0.3, -0.9)),
						LeftHip = r(34, 0, 0),
						RightHip = r(-24, 0, 0),
					},
				},
			}),
		},
		critical = m({
			name = "Sword_Critical", -- perilous cleave (red flash: dodge it!)
			windup = 0.7,
			active = 0.14,
			recovery = 0.45,
			damage = 24,
			postureDamage = 0,
			hitboxSize = Vector3.new(10, 7, 9),
			hitboxForward = 4.5,
			knockback = 40,
			finisher = true,
			perilous = true,
			hyperArmor = true,
			vfx = "Slash",
			slashTilt = 70,
			poses = {
				windup = {
					RightShoulder = r(182, 0, 30),
					LeftShoulder = r(150, 0, -20),
					RootJoint = r(16, -22, 0, Vector3.new(0, 0, 0.3)),
				},
				strike = {
					RightShoulder = r(32, 0, -32),
					LeftShoulder = r(20, 0, 10),
					RootJoint = r(-26, 26, 0, Vector3.new(0, -0.5, -0.7)),
					LeftHip = r(34, 0, 0),
					RightHip = r(-26, 0, 0),
				},
			},
		}),
		blockPose = { RightShoulder = r(82, 0, -48), LeftShoulder = r(70, 0, -8), RootJoint = r(-6, 8, 0) },
		parryPose = { RightShoulder = r(112, 0, -62), LeftShoulder = r(40, 0, 0), RootJoint = r(2, 18, 0) },
	} :: any
) :: Weapon

-- Scaled timings for a move with its weapon speed.
function Weapons.timing(weapon: Weapon, move: Move): (number, number, number)
	local s = weapon.speed
	return move.windup / s, move.active / s, move.recovery / s
end

function Weapons.get(name: string): Weapon?
	local w = (Weapons :: any)[name]
	return if type(w) == "table" and w.chain then w else nil
end

return Weapons
