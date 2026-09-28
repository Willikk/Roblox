--!strict
--[[
	ActionPose
	Plays PoseLibrary clips (attacks, blocks, parries, reactions) on top of every other
	layer, synchronized across clients.

	Replication: the server sets two attributes on the character Model
	  R6_Action      = clip name ("" / nil = none)
	  R6_ActionStart = workspace:GetServerTimeNow() when it started
	  R6_ActionSpeed = playback speed (optional, default 1)
	Every client samples the clip at (GetServerTimeNow() - start) * speed, so all screens
	show the same frame. The local player can predict with ActionPose.playLocal(), which
	wins over the replicated value for the same clip until it ends.
]]

local R6Procedural = script.Parent.Parent
local PoseLibrary = require(R6Procedural.PoseLibrary)
local Rig = require(R6Procedural.Rig)
local Types = require(R6Procedural.Types)

type Override = { clip: string, start: number, speed: number }

local ActionPose = { name = "ActionPose" } :: Types.Layer & {
	playLocal: (model: Model, clip: string, speed: number?) -> (),
	stopLocal: (model: Model) -> (),
	now: () -> number,
}

local overrides: { [Model]: Override } = setmetatable({}, { __mode = "k" }) :: any

function ActionPose.now(): number
	return workspace:GetServerTimeNow()
end

function ActionPose.playLocal(model: Model, clip: string, speed: number?)
	overrides[model] = { clip = clip, start = ActionPose.now(), speed = speed or 1 }
end

function ActionPose.stopLocal(model: Model)
	overrides[model] = nil
end

local function pivotFor(rig: Rig.Rig, joint: PoseLibrary.JointName): Vector3
	if joint == "RootJoint" then
		return Vector3.new(0, rig.hipLineY, 0)
	elseif joint == "LeftHip" then
		return Vector3.new(-rig.hipHalfWidth, rig.hipLineY, 0)
	elseif joint == "RightHip" then
		return Vector3.new(rig.hipHalfWidth, rig.hipLineY, 0)
	end
	return rig:c0(joint).Position -- Neck, shoulders: the joint itself
end

local function current(model: Model): (string?, number, number)
	local now = ActionPose.now()
	local override = overrides[model]
	local name = model:GetAttribute("R6_Action")
	local start = model:GetAttribute("R6_ActionStart")
	local speed = model:GetAttribute("R6_ActionSpeed")
	if override then
		local clip = PoseLibrary.get(override.clip)
		local elapsed = (now - override.start) * override.speed
		if clip and (clip.loop or elapsed <= clip.duration) then
			-- Prediction wins unless the server started something else afterwards.
			if
				not (
					type(name) == "string"
					and name ~= override.clip
					and type(start) == "number"
					and start > override.start
				)
			then
				return override.clip, elapsed, 1
			end
		end
		overrides[model] = nil
	end
	if type(name) ~= "string" or name == "" or type(start) ~= "number" then
		return nil, 0, 0
	end
	local s = if type(speed) == "number" then speed else 1
	return name, (now - start) * s, 1
end

function ActionPose.update(rig, sensor, _dt, _cfg, ctx)
	local name, elapsed = current(rig.character)
	if name == nil then
		return
	end
	local clip = PoseLibrary.get(name)
	if clip == nil then
		return
	end
	local pose, weight = PoseLibrary.sample(clip, elapsed)
	weight *= ctx.weight("R6_ActionWeight") * math.max(sensor.stateWeight, 0.35)
	if weight <= 1e-3 then
		return
	end
	for key, entry in pose do
		local joint: any = key -- pose keys are joint names (validated by PoseLibrary conventions)
		rig:add(joint, PoseLibrary.jointCFrame(entry, pivotFor(rig, joint), weight))
	end
end

return ActionPose
