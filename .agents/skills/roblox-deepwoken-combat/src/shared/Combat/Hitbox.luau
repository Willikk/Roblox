--!strict
--[[
	Hitbox
	Lag-compensated melee hit detection (pure math, tested).

	The server records every fighter's root CFrame each Heartbeat (History). When a swing
	becomes active it rewinds the DEFENDERS to the time the attacker saw them
	(clamped to Config.maxRewind so exploiters cannot hit from the past), then tests them
	against an oriented box in front of the attacker (+ body padding).
]]

local Hitbox = {}

-- Oriented box test: `point` inside `size` box at `boxCFrame`, grown by `padding`.
function Hitbox.contains(boxCFrame: CFrame, size: Vector3, point: Vector3, padding: number): boolean
	local p = boxCFrame:PointToObjectSpace(point)
	local h = size / 2 + Vector3.new(padding, padding, padding)
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- Box CFrame for a move: centered `forward` studs in front of the attacker root.
function Hitbox.boxFor(rootCFrame: CFrame, forward: number): CFrame
	return rootCFrame * CFrame.new(0, 0, -forward)
end

export type History = {
	times: { number },
	frames: { CFrame },
	head: number, -- index of the newest sample
	count: number,
	capacity: number,
}

function Hitbox.newHistory(capacity: number): History
	return {
		times = table.create(capacity, 0),
		frames = table.create(capacity, CFrame.new()),
		head = 0,
		count = 0,
		capacity = capacity,
	}
end

function Hitbox.push(h: History, time: number, cframe: CFrame)
	h.head = h.head % h.capacity + 1
	h.times[h.head] = time
	h.frames[h.head] = cframe
	h.count = math.min(h.count + 1, h.capacity)
end

-- CFrame at `time` (interpolated), clamped to the recorded range.
function Hitbox.sample(h: History, time: number): CFrame?
	if h.count == 0 then
		return nil
	end
	local newest = h.head
	if time >= h.times[newest] then
		return h.frames[newest]
	end
	local index = newest
	for _ = 1, h.count - 1 do
		local previous = (index - 2) % h.capacity + 1
		local t0, t1 = h.times[previous], h.times[index]
		if time >= t0 then
			local k = if t1 > t0 then (time - t0) / (t1 - t0) else 0
			return h.frames[previous]:Lerp(h.frames[index], k)
		end
		index = previous
	end
	return h.frames[index] -- older than the buffer: oldest sample
end

return Hitbox
