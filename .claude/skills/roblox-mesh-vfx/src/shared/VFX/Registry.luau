--!strict
--[[
	Registry
	Stable effect name <-> network id table shared by server and clients.

	To add an effect: create `Effects/MyEffect.luau` (returning a Types.Effect) and append
	"MyEffect" at the END of the list (never reorder: ids are positional).
]]

local NAMES: { string } = {
	"Slash",
	"Shockwave",
	"CraterRocks",
	"ImpactBurst",
	"GroundSlam",
}

local Registry = {}

local idByName: { [string]: number } = {}
for id, name in NAMES do
	idByName[name] = id
end

function Registry.idOf(name: string): number
	local id = idByName[name]
	if id == nil then
		error(`[VFX.Registry] unknown effect "{name}" - add it to Registry.luau`, 2)
	end
	return id
end

function Registry.nameOf(id: number): string?
	return NAMES[id]
end

function Registry.names(): { string }
	return table.clone(NAMES)
end

return Registry
