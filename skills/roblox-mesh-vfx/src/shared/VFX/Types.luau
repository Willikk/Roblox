--!strict
-- Shared type definitions for the VFX library.

export type EffectParams = {
	name: string,
	cframe: CFrame, -- effect frame: UpVector = surface / slash-plane normal, LookVector = forward
	scale: number, -- 1 = authored size
	color: Color3?, -- nil = authored color
	power: number, -- 0..5, drives counts / intensity / camera feedback
	variant: number, -- 0..255, effect-specific (mirror, style...)
	seed: number, -- 0..65535, identical on every client -> identical randomness
	source: Instance?, -- attacker character (optional)
	target: Instance?, -- victim character (optional)
}

export type EffectContext = {
	quality: number, -- 0..1 (adaptive quality / user setting)
	distance: number, -- camera distance to the effect origin
	isLocalSource: boolean, -- the local player caused it (camera shake, hitstop)
	isLocalTarget: boolean, -- the local player got hit
	rng: Random, -- seeded with params.seed
}

export type Effect = {
	maxDistance: number?, -- culled beyond this camera distance (default 400 studs)
	preload: (() -> ())?, -- build pools / fetch templates ahead of the first hit
	play: (params: EffectParams, ctx: EffectContext) -> (),
}

return {}
