--!strict
--[[
	Spring
	Analytic (closed-form) damped harmonic oscillator on Vector3.

	Unlike `v += (k*x - c*v) * dt` integrators, the exact solution is unconditionally
	stable: a 200 ms frame hitch never makes it explode. Scalars can be packed into the
	X/Y/Z components (e.g. pitch, roll, drop).

	  frequency    : undamped oscillations per second (Hz). Higher = snappier.
	  dampingRatio : 1 = critically damped (no overshoot), < 1 = bouncy, > 1 = sluggish.

	Usage:
		local spring = Spring.new(Vector3.zero, 6, 0.5)
		spring:impulse(Vector3.new(0, -30, 0)) -- kick the velocity
		RunService.PreRender:Connect(function(dt) local offset = spring:update(dt) end)
]]

export type Spring = {
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	frequency: number,
	dampingRatio: number,
	update: (self: Spring, dt: number) -> Vector3,
	impulse: (self: Spring, velocity: Vector3) -> (),
	reset: (self: Spring, position: Vector3?) -> (),
}

local Spring = {}
Spring.__index = Spring

local TAU = 2 * math.pi

function Spring.new(initial: Vector3, frequency: number, dampingRatio: number): Spring
	local self = setmetatable({
		position = initial,
		velocity = Vector3.zero,
		target = initial,
		frequency = frequency,
		dampingRatio = dampingRatio,
	}, Spring)
	return (self :: any) :: Spring
end

-- Pure step function, exposed for tests and for code that stores state elsewhere.
function Spring.step(
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	frequency: number,
	dampingRatio: number,
	dt: number
): (Vector3, Vector3)
	if dt <= 0 then
		return position, velocity
	end
	local omega = TAU * math.max(frequency, 1e-4)
	local zeta = math.max(dampingRatio, 0)
	local x0 = position - target
	local v0 = velocity

	local x: Vector3
	local v: Vector3
	if zeta < 0.9999 then
		-- Under-damped.
		local a = zeta * omega
		local wd = omega * math.sqrt(1 - zeta * zeta)
		local decay = math.exp(-a * dt)
		local c = math.cos(wd * dt)
		local s = math.sin(wd * dt)
		x = (x0 * c + (v0 + x0 * a) * (s / wd)) * decay
		v = (v0 * c - (v0 * a + x0 * (omega * omega)) * (s / wd)) * decay
	elseif zeta <= 1.0001 then
		-- Critically damped.
		local decay = math.exp(-omega * dt)
		local b = v0 + x0 * omega
		x = (x0 + b * dt) * decay
		v = (v0 - b * (omega * dt)) * decay
	else
		-- Over-damped.
		local root = math.sqrt(zeta * zeta - 1)
		local r1 = -omega * (zeta - root)
		local r2 = -omega * (zeta + root)
		local c1 = (v0 - x0 * r2) / (r1 - r2)
		local c2 = x0 - c1
		local e1 = math.exp(r1 * dt)
		local e2 = math.exp(r2 * dt)
		x = c1 * e1 + c2 * e2
		v = c1 * (r1 * e1) + c2 * (r2 * e2)
	end
	return target + x, v
end

function Spring.update(self: Spring, dt: number): Vector3
	self.position, self.velocity =
		Spring.step(self.position, self.velocity, self.target, self.frequency, self.dampingRatio, dt)
	return self.position
end

function Spring.impulse(self: Spring, velocity: Vector3)
	self.velocity += velocity
end

function Spring.reset(self: Spring, position: Vector3?)
	local p = position or self.target
	self.position = p
	self.target = p
	self.velocity = Vector3.zero
end

return Spring
