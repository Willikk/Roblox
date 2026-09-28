--!strict
--[[
	Settings
	Art-direction switches shared by the dark effects.

	blood: "blood" (red), "ichor" (black blood, reads as dark fantasy and is gentler on
	content maturity) or "none". Any blood/gore in a Roblox experience must be declared
	in the Maturity & Compliance questionnaire (Creator Dashboard); keep "ichor"/"none"
	for broad audiences.
]]

local Settings = {
	blood = "blood" :: "blood" | "ichor" | "none",
	stepFps = 12, -- sprite motion / camera shake stepping
	impactFrames = true, -- manga impact panels on heavy hits
	poolLifetime = 9, -- seconds blood pools stay on the ground
}

function Settings.burstSprite(): string?
	if Settings.blood == "blood" then
		return "BloodBurst"
	elseif Settings.blood == "ichor" then
		return "IchorBurst"
	end
	return nil
end

return Settings
