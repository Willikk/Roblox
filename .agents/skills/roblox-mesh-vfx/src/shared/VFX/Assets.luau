--!strict
--[[
	Assets
	Template lookup, preloading and shared raycast filters.

	Expected (optional) hierarchy - every effect falls back to procedural geometry when a
	template is missing, so the library works in an empty baseplate:

	ReplicatedStorage
	└── Assets
	    └── VFX
	        ├── Meshes
	        │   ├── Slashes      MeshPart "Slash", "SlashCore"      (arc in XZ plane, opens to -Z)
	        │   ├── Shockwaves   MeshPart "Shockwave"               (ring in XZ plane, Y = up)
	        │   └── Spikes       MeshPart "Rock1", "Rock2", ...     (optional crater rocks)
	        ├── Particles        ParticleEmitter "Sparks", "Dust", "Embers" (optional overrides)
	        ├── Textures         Decal/Texture templates, flipbook frames
	        └── Sounds
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = {}

local cache: { [string]: Instance } = {}
local vfxFolder: Folder? = nil

local function root(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("VFX")
end

-- Finds `ReplicatedStorage.Assets.VFX.<path>` where path is "Meshes/Slashes/Slash".
function Assets.find(path: string): Instance?
	local cached = cache[path]
	if cached and cached.Parent then
		return cached
	end
	local node = root()
	for segment in string.gmatch(path, "[^/]+") do
		if node == nil then
			break
		end
		node = node:FindFirstChild(segment)
	end
	-- Only cache hits: assets may stream in later (StreamingEnabled / delayed loading).
	if node then
		cache[path] = node
	end
	return node
end

function Assets.findPart(path: string): BasePart?
	local inst = Assets.find(path)
	return if inst and inst:IsA("BasePart") then inst else nil
end

-- Client-only container for effect instances (never replicated: created locally).
function Assets.workspaceFolder(): Folder
	local folder = vfxFolder
	if folder and folder.Parent then
		return folder
	end
	local existing = workspace:FindFirstChild("VFX")
	if existing and existing:IsA("Folder") then
		vfxFolder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "VFX"
	created.Parent = workspace
	vfxFolder = created
	return created
end

--[[
	Preloads every mesh/texture/sound under Assets.VFX so the FIRST hit does not hitch
	while the engine downloads the asset. Call once from the client bootstrap.
]]
function Assets.preloadAsync()
	local r = root()
	if r then
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync({ r })
		end)
		if not ok then
			warn("[VFX.Assets] preload failed:", err)
		end
	end
end

--[[
	RaycastParams for ground detection: ignores every character and every effect
	(so shockwaves never align to a player or to another effect) and respects
	CanCollide (so invisible trigger volumes are ignored too).
]]
function Assets.groundParams(extraIgnore: { Instance }?): RaycastParams
	local ignore: { Instance } = { Assets.workspaceFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	if extraIgnore then
		for _, inst in extraIgnore do
			table.insert(ignore, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

-- Color + material of whatever the ray hit (Terrain or BasePart), for debris/dust.
function Assets.surfaceLook(result: RaycastResult): (Color3, Enum.Material)
	local hit = result.Instance
	if hit:IsA("Terrain") then
		local ok, color = pcall(function()
			return hit:GetMaterialColor(result.Material)
		end)
		return if ok then color else Color3.fromRGB(110, 105, 100), result.Material
	elseif hit:IsA("BasePart") then
		return hit.Color, hit.Material
	end
	return Color3.fromRGB(110, 105, 100), Enum.Material.Slate
end

return Assets
