--!strict
--[[
	Fade
	Fades a whole effect (part + every Decal / Texture / Beam / Trail / ParticleEmitter /
	Light / Highlight below it) with ONE opacity value, preserving each child's authored
	transparency.

	The classic bug this fixes: tweening `MeshPart.Transparency` does NOT fade the
	Decals/Textures on it, so the glow texture "pops" out at the end of the effect.

	Usage:
		local snapshot = Fade.capture(effectModel)  -- once (e.g. when pooling)
		Fade.apply(snapshot, 0.5)                   -- 50% of authored opacity
		Fade.restore(snapshot)                      -- back to authored values
]]

type PartEntry = { kind: "part", inst: BasePart, base: number }
type DecalEntry = { kind: "decal", inst: Decal, base: number }
type BeamEntry = { kind: "beam", inst: Beam, base: { NumberSequenceKeypoint } }
type TrailEntry = { kind: "trail", inst: Trail, base: { NumberSequenceKeypoint } }
type ParticleEntry = { kind: "particle", inst: ParticleEmitter, base: { NumberSequenceKeypoint } }
type LightEntry = { kind: "light", inst: Light, base: number }
type HighlightEntry = { kind: "highlight", inst: Highlight, fill: number, outline: number }

type Entry = PartEntry | DecalEntry | BeamEntry | TrailEntry | ParticleEntry | LightEntry | HighlightEntry

export type Snapshot = {
	entries: { Entry },
	opacity: number,
}

local Fade = {}

local function scaleSequence(base: { NumberSequenceKeypoint }, opacity: number): NumberSequence
	local keypoints = table.create(#base)
	for i, kp in base do
		keypoints[i] = NumberSequenceKeypoint.new(kp.Time, 1 - (1 - kp.Value) * opacity, kp.Envelope * opacity)
	end
	return NumberSequence.new(keypoints)
end

local function captureOne(inst: Instance, entries: { Entry })
	if inst:IsA("BasePart") then
		table.insert(entries, { kind = "part", inst = inst, base = inst.Transparency })
	elseif inst:IsA("Decal") then -- also matches Texture (Texture extends Decal)
		table.insert(entries, { kind = "decal", inst = inst, base = inst.Transparency })
	elseif inst:IsA("Beam") then
		table.insert(entries, { kind = "beam", inst = inst, base = inst.Transparency.Keypoints })
	elseif inst:IsA("Trail") then
		table.insert(entries, { kind = "trail", inst = inst, base = inst.Transparency.Keypoints })
	elseif inst:IsA("ParticleEmitter") then
		table.insert(entries, { kind = "particle", inst = inst, base = inst.Transparency.Keypoints })
	elseif inst:IsA("Light") then
		table.insert(entries, { kind = "light", inst = inst, base = inst.Brightness })
	elseif inst:IsA("Highlight") then
		table.insert(
			entries,
			{ kind = "highlight", inst = inst, fill = inst.FillTransparency, outline = inst.OutlineTransparency }
		)
	end
end

function Fade.capture(root: Instance): Snapshot
	local entries: { Entry } = {}
	captureOne(root, entries)
	for _, descendant in root:GetDescendants() do
		captureOne(descendant, entries)
	end
	return { entries = entries, opacity = 1 }
end

-- opacity: 1 = authored look, 0 = fully invisible. Values above 1 are clamped.
-- (Branches look identical but each one is a different typed Instance kind.)
-- selene: allow(if_same_then_else)
function Fade.apply(snapshot: Snapshot, opacity: number)
	opacity = math.clamp(opacity, 0, 1)
	if math.abs(opacity - snapshot.opacity) < 1e-3 then
		return -- NumberSequence rebuilds are not free; skip no-op frames.
	end
	snapshot.opacity = opacity
	for _, entry in snapshot.entries do
		if entry.kind == "part" then
			entry.inst.Transparency = 1 - (1 - entry.base) * opacity
		elseif entry.kind == "decal" then
			entry.inst.Transparency = 1 - (1 - entry.base) * opacity
		elseif entry.kind == "beam" then
			entry.inst.Transparency = scaleSequence(entry.base, opacity)
		elseif entry.kind == "trail" then
			entry.inst.Transparency = scaleSequence(entry.base, opacity)
		elseif entry.kind == "particle" then
			entry.inst.Transparency = scaleSequence(entry.base, opacity)
		elseif entry.kind == "light" then
			entry.inst.Brightness = entry.base * opacity
		elseif entry.kind == "highlight" then
			entry.inst.FillTransparency = 1 - (1 - entry.fill) * opacity
			entry.inst.OutlineTransparency = 1 - (1 - entry.outline) * opacity
		end
	end
end

function Fade.restore(snapshot: Snapshot)
	snapshot.opacity = -1 -- force a full write
	Fade.apply(snapshot, 1)
end

return Fade
