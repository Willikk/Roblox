--!strict
-- Shared types for procedural layers.

local Config = require(script.Parent.Config)
local Rig = require(script.Parent.Rig)
local Sensor = require(script.Parent.Sensor)

export type LookTarget = {
	yaw: number, -- root space, + = left
	pitch: number, -- + = up
}

export type FrameContext = {
	isLocal: boolean, -- the local player's own character
	lookTarget: LookTarget?, -- desired head look (camera, network, or NPC attribute)
	weight: (attribute: string) -> number, -- character attribute multiplier (default 1)
}

export type Layer = {
	name: string,
	update: (rig: Rig.Rig, sensor: Sensor.Sensor, dt: number, cfg: Config.Config, ctx: FrameContext) -> (),
}

return {}
