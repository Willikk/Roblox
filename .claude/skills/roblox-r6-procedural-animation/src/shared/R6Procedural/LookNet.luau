--!strict
--[[
	LookNet
	Wire format for head-look replication (Motor6D/Transform changes made on a client
	never replicate, so the look angles are sent explicitly).

	client -> server : 4 bytes   i16 yaw, i16 pitch                (rate-limited, 15 Hz)
	server -> clients: 1 + 12*n  u8 count, then n x (f64 userId, i16 yaw, i16 pitch)
	                   batched at 15 Hz, <= 70 players per packet (841 bytes < 900).
	Angles are quantized to pi/32767 (~0.0055 deg).
]]

local LookNet = {}

LookNet.LOCAL_SIZE = 4
LookNet.ENTRY_SIZE = 12
LookNet.MAX_ENTRIES = 70

export type Entry = { userId: number, yaw: number, pitch: number }

local SCALE = 32767 / math.pi

local function quantize(angle: number): number
	if angle ~= angle then -- NaN
		return 0
	end
	return math.clamp(math.round(angle * SCALE), -32767, 32767)
end

function LookNet.encodeLocal(yaw: number, pitch: number): buffer
	local b = buffer.create(LookNet.LOCAL_SIZE)
	buffer.writei16(b, 0, quantize(yaw))
	buffer.writei16(b, 2, quantize(pitch))
	return b
end

function LookNet.decodeLocal(b: any): (number?, number?)
	if typeof(b) ~= "buffer" or buffer.len(b) ~= LookNet.LOCAL_SIZE then
		return nil, nil
	end
	return buffer.readi16(b, 0) / SCALE, buffer.readi16(b, 2) / SCALE
end

function LookNet.encodeBatch(entries: { Entry }): buffer
	local count = math.min(#entries, LookNet.MAX_ENTRIES)
	local b = buffer.create(1 + count * LookNet.ENTRY_SIZE)
	buffer.writeu8(b, 0, count)
	for i = 1, count do
		local e = entries[i]
		local offset = 1 + (i - 1) * LookNet.ENTRY_SIZE
		buffer.writef64(b, offset, e.userId)
		buffer.writei16(b, offset + 8, quantize(e.yaw))
		buffer.writei16(b, offset + 10, quantize(e.pitch))
	end
	return b
end

function LookNet.decodeBatch(b: any): { Entry }?
	if typeof(b) ~= "buffer" or buffer.len(b) < 1 then
		return nil
	end
	local count = buffer.readu8(b, 0)
	if count > LookNet.MAX_ENTRIES or buffer.len(b) ~= 1 + count * LookNet.ENTRY_SIZE then
		return nil
	end
	local entries = table.create(count)
	for i = 1, count do
		local offset = 1 + (i - 1) * LookNet.ENTRY_SIZE
		entries[i] = {
			userId = buffer.readf64(b, offset),
			yaw = buffer.readi16(b, offset + 8) / SCALE,
			pitch = buffer.readi16(b, offset + 10) / SCALE,
		}
	end
	return entries
end

return LookNet
