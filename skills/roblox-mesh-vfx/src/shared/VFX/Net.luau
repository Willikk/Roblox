--!strict
--[[
	Net
	Compact binary encoding of effect events with the `buffer` library.

	One record = 31 bytes:
	  u8  effect id        u16 seed           f32 x3 position
	  i16 x3 rotation (YXZ euler, ~0.0001 rad precision)
	  u16 scale * 100      u8 x3 color        u8 flags (bit0 = has color)
	  u8  power * 50       u8 variant         u8 source index  u8 target index

	A packet = u8 count + N records. UnreliableRemoteEvent payloads above ~900 bytes are
	dropped, so a packet holds at most 28 records (869 bytes). Instances (source/target
	characters) travel in a separate array argument and are referenced by 1-based index
	(0 = none).

	Pure Luau (buffer + CFrame only): round-trip tested under Lune.
]]

local Net = {}

Net.RECORD_SIZE = 31
Net.MAX_RECORDS = 28
Net.MAX_PAYLOAD = 1 + Net.RECORD_SIZE * Net.MAX_RECORDS

export type Record = {
	id: number,
	seed: number,
	cframe: CFrame,
	scale: number,
	color: Color3?,
	power: number,
	variant: number,
	sourceIndex: number,
	targetIndex: number,
}

local ANGLE_SCALE = 32767 / math.pi

local function quantizeAngle(angle: number): number
	return math.clamp(math.round(angle * ANGLE_SCALE), -32767, 32767)
end

local function toByte(value: number): number
	return math.clamp(math.round(value), 0, 255)
end

function Net.writeRecord(b: buffer, offset: number, record: Record)
	local cf = record.cframe
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	local p = cf.Position

	buffer.writeu8(b, offset, record.id)
	buffer.writeu16(b, offset + 1, math.clamp(math.floor(record.seed), 0, 65535))
	buffer.writef32(b, offset + 3, p.X)
	buffer.writef32(b, offset + 7, p.Y)
	buffer.writef32(b, offset + 11, p.Z)
	buffer.writei16(b, offset + 15, quantizeAngle(rx))
	buffer.writei16(b, offset + 17, quantizeAngle(ry))
	buffer.writei16(b, offset + 19, quantizeAngle(rz))
	buffer.writeu16(b, offset + 21, math.clamp(math.round(record.scale * 100), 0, 65535))

	local color = record.color
	if color then
		buffer.writeu8(b, offset + 23, toByte(color.R * 255))
		buffer.writeu8(b, offset + 24, toByte(color.G * 255))
		buffer.writeu8(b, offset + 25, toByte(color.B * 255))
		buffer.writeu8(b, offset + 26, 1)
	else
		buffer.writeu8(b, offset + 23, 0)
		buffer.writeu8(b, offset + 24, 0)
		buffer.writeu8(b, offset + 25, 0)
		buffer.writeu8(b, offset + 26, 0)
	end

	buffer.writeu8(b, offset + 27, toByte(record.power * 50))
	buffer.writeu8(b, offset + 28, toByte(record.variant))
	buffer.writeu8(b, offset + 29, toByte(record.sourceIndex))
	buffer.writeu8(b, offset + 30, toByte(record.targetIndex))
end

function Net.readRecord(b: buffer, offset: number): Record
	local position =
		Vector3.new(buffer.readf32(b, offset + 3), buffer.readf32(b, offset + 7), buffer.readf32(b, offset + 11))
	local rx = buffer.readi16(b, offset + 15) / ANGLE_SCALE
	local ry = buffer.readi16(b, offset + 17) / ANGLE_SCALE
	local rz = buffer.readi16(b, offset + 19) / ANGLE_SCALE

	local color: Color3? = nil
	if bit32.band(buffer.readu8(b, offset + 26), 1) == 1 then
		color =
			Color3.fromRGB(buffer.readu8(b, offset + 23), buffer.readu8(b, offset + 24), buffer.readu8(b, offset + 25))
	end

	return {
		id = buffer.readu8(b, offset),
		seed = buffer.readu16(b, offset + 1),
		cframe = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(rx, ry, rz),
		scale = buffer.readu16(b, offset + 21) / 100,
		color = color,
		power = buffer.readu8(b, offset + 27) / 50,
		variant = buffer.readu8(b, offset + 28),
		sourceIndex = buffer.readu8(b, offset + 29),
		targetIndex = buffer.readu8(b, offset + 30),
	}
end

-- Encodes up to MAX_RECORDS records (callers chunk bigger batches with Net.chunk).
function Net.encode(records: { Record }): buffer
	local count = #records
	assert(count <= Net.MAX_RECORDS, "too many records for one packet; use Net.chunk")
	local b = buffer.create(1 + count * Net.RECORD_SIZE)
	buffer.writeu8(b, 0, count)
	for i, record in records do
		Net.writeRecord(b, 1 + (i - 1) * Net.RECORD_SIZE, record)
	end
	return b
end

-- Decodes a packet. Returns nil for malformed input (never trust the network).
function Net.decode(b: any): { Record }?
	if typeof(b) ~= "buffer" then
		return nil
	end
	local length = buffer.len(b)
	if length < 1 then
		return nil
	end
	local count = buffer.readu8(b, 0)
	if count > Net.MAX_RECORDS or length ~= 1 + count * Net.RECORD_SIZE then
		return nil
	end
	local records = table.create(count)
	for i = 1, count do
		records[i] = Net.readRecord(b, 1 + (i - 1) * Net.RECORD_SIZE)
	end
	return records
end

-- Splits a record list into packet-sized lists.
function Net.chunk(records: { Record }): { { Record } }
	local chunks = {}
	for start = 1, #records, Net.MAX_RECORDS do
		table.insert(chunks, table.move(records, start, math.min(start + Net.MAX_RECORDS - 1, #records), 1, {}))
	end
	return chunks
end

return Net
