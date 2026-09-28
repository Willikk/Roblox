--!strict
--[[
	Hitstop
	Fighting-game frame freeze: every animation playing on the attacker and the victim
	stops for a few frames on impact (and, optionally, every "world" VFX too).

	Fixes over the naive `track:AdjustSpeed(0); task.delay(d, AdjustSpeed(1))`:
	  * freezes ALL playing tracks (idle + attack + walk layers), not one track;
	  * restores each track's ORIGINAL speed (a 1.3x attack stays 1.3x);
	  * overlapping hitstops extend the freeze instead of un-freezing early;
	  * restores happen in RunService.PreAnimation, the documented place to change
	    AnimationTrack speed before the Animator steps.

	Typical durations: light M1 0.04-0.06 s, heavy / crit 0.08-0.12 s, parry 0.12-0.16 s.

	Usage:
		Hitstop.apply({ attackerCharacter, victimCharacter }, 0.07)
		Hitstop.apply({ attackerCharacter }, 0.1, { speed = 0.05, freezeVFX = true })
]]

local RunService = game:GetService("RunService")

local Animator = require(script.Parent.Animator)

export type Options = {
	speed: number?, -- playback speed during the freeze (0 = full stop, 0.05 = heavy slow-mo)
	freezeVFX: boolean?, -- also freeze Animator group "world" (slashes stop mid-swing)
}

type Frozen = {
	originalSpeed: number,
	releaseAt: number,
}

local Hitstop = {}

local frozen: { [AnimationTrack]: Frozen } = {}
local vfxReleaseAt = 0
local connection: RBXScriptConnection? = nil

local function findAnimator(target: Instance): Animator?
	if target:IsA("Animator") then
		return target
	end
	local controller: Instance? = target:FindFirstChildWhichIsA("Humanoid")
		or target:FindFirstChildWhichIsA("AnimationController")
	if controller == nil and (target:IsA("Humanoid") or target:IsA("AnimationController")) then
		controller = target
	end
	return if controller then controller:FindFirstChildWhichIsA("Animator") else nil
end

local function onPreAnimation()
	local now = os.clock()
	for track, state in frozen do
		if now >= state.releaseAt then
			frozen[track] = nil
			if track.IsPlaying then
				track:AdjustSpeed(state.originalSpeed)
			end
		end
	end
	if vfxReleaseAt > 0 and now >= vfxReleaseAt then
		vfxReleaseAt = 0
		Animator.setTimeScale("world", 1)
	end
	if next(frozen) == nil and vfxReleaseAt == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

function Hitstop.apply(targets: { Instance? }, duration: number, options: Options?)
	if duration <= 0 then
		return
	end
	local speed = if options and options.speed then options.speed else 0
	local releaseAt = os.clock() + duration

	for _, target in targets do
		local animator = target and findAnimator(target)
		if animator == nil then
			continue
		end
		for _, track in animator:GetPlayingAnimationTracks() do
			local state = frozen[track]
			if state then
				state.releaseAt = math.max(state.releaseAt, releaseAt)
			else
				frozen[track] = { originalSpeed = track.Speed, releaseAt = releaseAt }
				track:AdjustSpeed(speed)
			end
		end
	end

	if options and options.freezeVFX then
		vfxReleaseAt = math.max(vfxReleaseAt, releaseAt)
		Animator.setTimeScale("world", speed)
	end

	if connection == nil then
		connection = RunService.PreAnimation:Connect(onPreAnimation)
	end
end

-- Immediately releases everything (e.g. on character death / round end).
function Hitstop.releaseAll()
	for track, state in frozen do
		if track.IsPlaying then
			track:AdjustSpeed(state.originalSpeed)
		end
	end
	table.clear(frozen)
	if vfxReleaseAt > 0 then
		vfxReleaseAt = 0
		Animator.setTimeScale("world", 1)
	end
end

function Hitstop.isFrozen(track: AnimationTrack): boolean
	return frozen[track] ~= nil
end

return Hitstop
