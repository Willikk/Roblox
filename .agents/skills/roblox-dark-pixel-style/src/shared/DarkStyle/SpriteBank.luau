--!strict
--[[
	SpriteBank (client)
	Turns the SpriteGen library into displayable textures, once, at startup.

	Two sources, per sprite:
	  1. uploaded PNG (SpriteBank.assetIds[name] = "rbxassetid://..."), exported with
	     `lune run tools/export-sprites.luau` — works in every published game;
	  2. otherwise an EditableImage generated at runtime. Works in Studio; published
	     experiences need a 13+ ID-verified owner with "Enable Mesh / Image APIs" on
	     (Creator Dashboard). Only one EditableImage refreshes per frame, so sheets are
	     written once and animated with ImageRectOffset, never rewritten.
]]

local AssetService = game:GetService("AssetService")

local SpriteGen = require(script.Parent.SpriteGen)

export type Entry = {
	name: string,
	content: Content,
	frameSize: Vector2,
	frames: number,
	fps: number,
	loop: boolean,
}

local SpriteBank = {}

-- Paste uploaded sprite-sheet ids here (see builds/sprites/manifest.json for sizes).
SpriteBank.assetIds = {} :: { [string]: string }

local entries: { [string]: Entry } = {}
local loaded = false
local loading = false
local waiters: { () -> () } = {}
local warned = false
local images: { EditableImage } = {} -- strong references: generated textures stay alive

local function createEditable(sheet: any): EditableImage?
	local ok, result = pcall(function()
		local image = AssetService:CreateEditableImage({ Size = Vector2.new(sheet.w, sheet.h) })
		image:WritePixelsBuffer(Vector2.zero, Vector2.new(sheet.w, sheet.h), sheet.px)
		return image
	end)
	if ok then
		return result
	end
	if not warned then
		warned = true
		warn(
			"[DarkStyle] EditableImage unavailable (",
			result,
			"). Export the sprites with `lune run tools/export-sprites.luau`, upload the PNGs and fill SpriteBank.assetIds, or enable Mesh / Image APIs for this experience."
		)
	end
	return nil
end

-- Generates / resolves every sprite. Yields (one sheet per frame). Idempotent.
function SpriteBank.loadAsync()
	if loaded then
		return
	end
	if loading then
		local thread = coroutine.running()
		table.insert(waiters, function()
			task.spawn(thread)
		end)
		coroutine.yield()
		return
	end
	loading = true
	for _, builder in SpriteGen.builders() do
		local sprite = builder.build() -- one sprite per frame: no loading hitch
		local content: Content? = nil
		local asset = SpriteBank.assetIds[sprite.name]
		if asset then
			content = Content.fromUri(asset)
		else
			local image = createEditable(SpriteGen.sheet(sprite))
			if image then
				table.insert(images, image)
				content = Content.fromObject(image)
			end
		end
		if content then
			entries[sprite.name] = {
				name = sprite.name,
				content = content,
				frameSize = Vector2.new(sprite.w, sprite.h),
				frames = #sprite.frames,
				fps = sprite.fps,
				loop = sprite.loop,
			}
		end
		task.wait() -- spread the uploads: one EditableImage update per frame
	end
	loaded = true
	for _, resume in waiters do
		resume()
	end
	table.clear(waiters)
end

function SpriteBank.get(name: string): Entry?
	return entries[name]
end

-- Number of runtime-generated textures (0 when every sprite comes from uploaded PNGs).
function SpriteBank.generatedCount(): number
	return #images
end

function SpriteBank.isLoaded(): boolean
	return loaded
end

-- Shows `frame` (1-based) of `entry` on an ImageLabel, with nearest-neighbour scaling.
function SpriteBank.apply(label: ImageLabel, entry: Entry, frame: number)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = entry.content
	label.ImageRectSize = entry.frameSize
	label.ImageRectOffset = Vector2.new((math.clamp(frame, 1, entry.frames) - 1) * entry.frameSize.X, 0)
end

return SpriteBank
