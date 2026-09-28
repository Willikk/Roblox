--!nocheck
-- Binary packet encoding: round-trip precision, size budget, hostile input.
return function(t)
	local expect = t.expect
	local h = t.harness.new()
	local VFX = h:mount(`{t.skillsRoot}/roblox-mesh-vfx/src/shared/VFX`, "VFX")
	local Net = h:require(VFX.Net)
	local Registry = h:require(VFX.Registry)
	local CFrame, Vector3, Color3 = t.harness.roblox.CFrame, t.harness.roblox.Vector3, t.harness.roblox.Color3

	local function randomRecord(rng)
		return {
			id = rng:NextInteger(1, 5),
			seed = rng:NextInteger(0, 65535),
			cframe = CFrame.new(rng:NextNumber(-5000, 5000), rng:NextNumber(-100, 800), rng:NextNumber(-5000, 5000))
				* CFrame.fromEulerAnglesYXZ(
					rng:NextNumber(-1.5, 1.5),
					rng:NextNumber(-3.1, 3.1),
					rng:NextNumber(-3.1, 3.1)
				),
			scale = math.round(rng:NextNumber(0.1, 20) * 100) / 100,
			color = if rng:NextNumber() > 0.5
				then Color3.fromRGB(rng:NextInteger(0, 255), rng:NextInteger(0, 255), rng:NextInteger(0, 255))
				else nil,
			power = math.round(rng:NextNumber(0, 5) * 50) / 50,
			variant = rng:NextInteger(0, 255),
			sourceIndex = rng:NextInteger(0, 3),
			targetIndex = rng:NextInteger(0, 3),
		}
	end

	t.test("a full packet fits the UnreliableRemoteEvent budget", function()
		expect.truthy(Net.MAX_PAYLOAD <= 900, `payload {Net.MAX_PAYLOAD} bytes`)
	end)

	t.test("records round-trip with sub-millimetre / sub-milliradian precision", function()
		local rng = t.harness.Random.new(11)
		for _ = 1, 50 do
			local records = {}
			for i = 1, rng:NextInteger(1, Net.MAX_RECORDS) do
				records[i] = randomRecord(rng)
			end
			local decoded = Net.decode(Net.encode(records))
			expect.truthy(decoded, "decoded")
			expect.eq(#decoded, #records)
			for i, a in records do
				local b = decoded[i]
				expect.eq(b.id, a.id)
				expect.eq(b.seed, a.seed)
				expect.eq(b.variant, a.variant)
				expect.eq(b.sourceIndex, a.sourceIndex)
				expect.eq(b.targetIndex, a.targetIndex)
				expect.near(b.scale, a.scale, 0.006)
				expect.near(b.power, a.power, 0.011)
				expect.vecNear(
					b.cframe.Position,
					a.cframe.Position,
					1e-3 * math.max(1, a.cframe.Position.Magnitude / 1000)
				)
				expect.vecNear(b.cframe.LookVector, a.cframe.LookVector, 5e-4, "look")
				expect.vecNear(b.cframe.UpVector, a.cframe.UpVector, 5e-4, "up")
				expect.eq(b.color == nil, a.color == nil, "color presence")
				if a.color then
					expect.near(b.color.R, a.color.R, 1 / 255 + 1e-6)
				end
			end
		end
	end)

	t.test("decode rejects hostile payloads", function()
		expect.eq(Net.decode("not a buffer"), nil)
		expect.eq(Net.decode(nil), nil)
		expect.eq(Net.decode(buffer.create(0)), nil)
		local wrongLength = buffer.create(1 + Net.RECORD_SIZE + 3)
		buffer.writeu8(wrongLength, 0, 1)
		expect.eq(Net.decode(wrongLength), nil)
		local tooMany = buffer.create(1 + Net.RECORD_SIZE * 200)
		buffer.writeu8(tooMany, 0, 200)
		expect.eq(Net.decode(tooMany), nil)
	end)

	t.test("encode refuses oversize batches and chunk splits them", function()
		local rng = t.harness.Random.new(5)
		local records = {}
		for i = 1, 70 do
			records[i] = randomRecord(rng)
		end
		expect.throws(function()
			Net.encode(records)
		end)
		local chunks = Net.chunk(records)
		expect.eq(#chunks, 3)
		expect.eq(#chunks[1], Net.MAX_RECORDS)
		expect.eq(#chunks[3], 70 - 2 * Net.MAX_RECORDS)
	end)

	t.test("registry ids are stable and unknown names fail loudly", function()
		expect.eq(Registry.idOf("Slash"), 1)
		expect.eq(Registry.nameOf(Registry.idOf("GroundSlam")), "GroundSlam")
		expect.throws(function()
			Registry.idOf("DoesNotExist")
		end)
		expect.truthy(#Registry.names() <= 255, "fits in a u8")
	end)
end
