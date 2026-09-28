--!nocheck
--[[
	Minimal test runner: `lune run tools/test/run.luau [filter]`
	Discovers every `*.spec.luau` under .claude/skills/*/tests and runs it.
	A spec returns `function(t)` and registers cases with `t.test(name, fn)`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local harness = require("./harness")

local ROOT = process.cwd
local SKILLS = `{ROOT}/.claude/skills`
local filter = process.args[1]

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local function describe(value): string
	return tostring(value)
end

local expect = {}

function expect.truthy(value, message: string?)
	if not value then
		error(message or `expected truthy, got {describe(value)}`, 2)
	end
end

function expect.eq(actual, expected, message: string?)
	if actual ~= expected then
		error(`{message or "not equal"}: expected {describe(expected)}, got {describe(actual)}`, 2)
	end
end

function expect.near(actual: number, expected: number, eps: number?, message: string?)
	if not near(actual, expected, eps) then
		error(`{message or "not near"}: expected {expected} +- {eps or 1e-6}, got {actual}`, 2)
	end
end

function expect.vecNear(actual, expected, eps: number?, message: string?)
	local e = eps or 1e-4
	if (actual - expected).Magnitude > e then
		error(`{message or "vectors differ"}: expected {describe(expected)}, got {describe(actual)}`, 2)
	end
end

function expect.throws(fn, message: string?)
	local ok = pcall(fn)
	if ok then
		error(message or "expected an error", 2)
	end
end

local passed, failed = 0, 0
local failures = {}

local function runSpec(path: string)
	local chunk = require(path)
	local cases = {}
	chunk({
		test = function(name: string, fn)
			table.insert(cases, { name = name, fn = fn })
		end,
		expect = expect,
		harness = harness,
		skillsRoot = SKILLS,
	})
	for _, case in cases do
		local label = `{string.match(path, "skills/(.+)$") or path}: {case.name}`
		if filter and not string.find(label, filter, 1, true) then
			continue
		end
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
			print(`  PASS  {label}`)
		else
			failed += 1
			table.insert(failures, `{label}\n        {err}`)
			print(`  FAIL  {label}\n        {err}`)
		end
	end
end

for _, skill in fs.readDir(SKILLS) do
	local testsDir = `{SKILLS}/{skill}/tests`
	if fs.isDir(testsDir) then
		local files = fs.readDir(testsDir)
		table.sort(files)
		for _, file in files do
			if string.match(file, "%.spec%.luau$") then
				-- Lune resolves requires relative to this file (tools/test/run.luau).
				runSpec(`../../.claude/skills/{skill}/tests/{string.gsub(file, "%.luau$", "")}`)
			end
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	print("\nFailures:\n  " .. table.concat(failures, "\n  "))
	process.exit(1)
end
