--!nocheck
--[[
	Lune test harness for the Roblox skills.

	Loads the REAL module sources (no copies) inside a sandbox that provides:
	  * every Roblox datatype implemented by @lune/roblox (CFrame, Vector3, Color3, ...);
	  * a deterministic `Random` (Lune has none);
	  * a mock Instance tree for `script` / `script.Parent.X` built from the folders;
	  * `game:GetService(...)` mocks whose signals can be fired by tests;
	  * `workspace` with a recording BulkMoveTo and a scriptable Raycast.

	Usage in a spec:
		local h = harness.new()
		local VFX = h:mount("<abs path to src/shared/VFX>", "VFX")
		local Ease = h:require(VFX.Ease)
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Harness = {}
Harness.__index = Harness

-- xorshift32 based Random with the Roblox API surface the skills use.
local MockRandom = {}
MockRandom.__index = MockRandom

function MockRandom.new(seed)
	local s = math.floor(tonumber(seed) or os.clock() * 1e6) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ state = s }, MockRandom)
end

local function nextU32(self)
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

function MockRandom:NextNumber(min, max)
	local u = nextU32(self) / 4294967296
	if min then
		return min + (max - min) * u
	end
	return u
end

function MockRandom:NextInteger(min, max)
	return min + (nextU32(self) % (max - min + 1))
end

-- Minimal RBXScriptSignal replacement.
local function newSignal()
	local signal = { listeners = {} }
	function signal:Connect(fn)
		local entry = { fn = fn, connected = true }
		table.insert(self.listeners, entry)
		return {
			Connected = true,
			Disconnect = function(conn)
				entry.connected = false
				conn.Connected = false
			end,
		}
	end
	function signal:Fire(...)
		for _, entry in table.clone(self.listeners) do
			if entry.connected then
				entry.fn(...)
			end
		end
	end
	function signal:ConnectedCount()
		local n = 0
		for _, entry in self.listeners do
			if entry.connected then
				n += 1
			end
		end
		return n
	end
	return signal
end
Harness.newSignal = newSignal

-- Mock Instance node used for `script` trees.
local function newNode(name, parent, path, isModule)
	local node = { __children = {}, __path = path, __isModule = isModule }
	node.Name = name
	node.Parent = parent
	function node:FindFirstChild(childName)
		return self.__children[childName]
	end
	function node:WaitForChild(childName)
		local child = self.__children[childName]
		assert(child, `mock WaitForChild: {childName} missing under {self.Name}`)
		return child
	end
	function node:GetChildren()
		local list = {}
		for _, child in self.__children do
			table.insert(list, child)
		end
		return list
	end
	function node:IsA(className)
		if className == "ModuleScript" then
			return self.__isModule == true
		end
		return className == "Folder" and not self.__isModule
	end
	return setmetatable(node, {
		__index = function(self, key)
			local child = rawget(self, "__children")[key]
			if child == nil then
				error(`mock Instance: {key} is not a valid member of {rawget(self, "Name")}`, 2)
			end
			return child
		end,
	})
end

function Harness.new()
	local self = setmetatable({}, Harness)
	self.cache = {}
	self.warnings = {}
	self.bulkMoves = {}
	self.raycastResult = nil
	self.clock = 0

	local run = {
		PreRender = newSignal(),
		PreAnimation = newSignal(),
		PreSimulation = newSignal(),
		PostSimulation = newSignal(),
		Heartbeat = newSignal(),
		RenderStepped = newSignal(),
		Stepped = newSignal(),
	}
	function run:IsClient()
		return true
	end
	function run:IsServer()
		return false
	end
	function run:BindToRenderStep() end
	function run:UnbindFromRenderStep() end
	self.RunService = run

	local services = {
		RunService = run,
		Players = {
			LocalPlayer = nil,
			GetPlayers = function()
				return {}
			end,
			PlayerAdded = newSignal(),
			PlayerRemoving = newSignal(),
		},
		GuiService = { ReducedMotionEnabled = false },
	}
	self.services = services

	self.game = {
		GetService = function(_, name)
			local service = services[name]
			if service == nil then
				service = { Name = name }
				services[name] = service
			end
			return service
		end,
	}

	local harness = self
	self.workspace = {
		BulkMoveTo = function(_, parts, cframes, mode)
			table.insert(harness.bulkMoves, { parts = table.clone(parts), cframes = table.clone(cframes), mode = mode })
			for i, part in parts do
				part.CFrame = cframes[i]
			end
		end,
		Raycast = function()
			return harness.raycastResult
		end,
		CurrentCamera = nil,
		Gravity = 196.2,
		GetAttribute = function()
			return nil
		end,
	}
	return self
end

function Harness:environment(scriptNode)
	local env = {}
	for key, value in roblox do
		if type(key) == "string" and string.match(key, "^%u") then
			env[key] = value
		end
	end
	env.Random = MockRandom
	env.game = self.game
	env.workspace = self.workspace
	env.script = scriptNode
	env.warn = function(...)
		table.insert(self.warnings, table.concat(table.pack(...) :: any, " "))
	end
	env.require = function(target)
		return self:require(target)
	end
	return env
end

-- Mounts a folder of .luau files as a mock Instance tree and returns its root node.
function Harness:mount(dir: string, name: string, parent)
	local root = newNode(name, parent, nil, false)
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			root.__children[entry] = self:mount(full, entry, root)
		elseif string.match(entry, "%.luau$") then
			local moduleName = string.gsub(entry, "%.luau$", "")
			if not string.match(moduleName, "%.") then -- skip .server/.client scripts
				root.__children[moduleName] = newNode(moduleName, root, full, true)
			end
		end
	end
	return root
end

function Harness:require(node)
	local path = rawget(node, "__path")
	assert(path, "require target is not a mounted module")
	local cached = self.cache[path]
	if cached ~= nil then
		return cached.value
	end
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = self:environment(node) })
	local value = chunk()
	self.cache[path] = { value = value }
	return value
end

-- Advances every frame signal once (PreAnimation -> PreSimulation -> Heartbeat -> PreRender).
function Harness:step(dt: number)
	self.clock += dt
	local run = self.RunService
	run.PreAnimation:Fire(dt)
	run.PreSimulation:Fire(dt)
	run.PostSimulation:Fire(dt)
	run.Heartbeat:Fire(dt)
	run.PreRender:Fire(dt)
end

Harness.Random = MockRandom
Harness.roblox = roblox

return Harness
