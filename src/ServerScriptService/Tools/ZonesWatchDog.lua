--!strict
-- ZonesWatchdog.lua
-- Debug tool to detect when Workspace.Zones (and key children) are removed
-- during Live Test. Rojo is not the cause (Workspace not mapped).
-- This helps identify whether a runtime script is deleting/reparenting Zones.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ZonesWatchdog = {}

local VERSION = "ZonesWatchdog v1.0"

local function log(message: string)
	print("[ZonesWatchdog] " .. message)
end

local function warn_log(message: string)
	warn("[ZonesWatchdog] " .. message)
end

local function exists(path: string): boolean
	local current: Instance = Workspace
	for seg in string.gmatch(path, "[^/]+") do
		local next_inst = current:FindFirstChild(seg)
		if not next_inst then
			return false
		end
		current = next_inst
	end
	return true
end

local function dump_state(prefix: string)
	local zones = Workspace:FindFirstChild("Zones")
	log(prefix .. " Zones exists: " .. tostring(zones ~= nil))

	if zones then
		local safe = zones:FindFirstChild("SafeZoneWorld")
		local arena = zones:FindFirstChild("ArenaWorld")
		log(prefix .. " SafeZoneWorld: " .. tostring(safe ~= nil))
		log(prefix .. " ArenaWorld: " .. tostring(arena ~= nil))

		if safe then
			log(prefix .. " SafeZoneRegion: "
				.. tostring(safe:FindFirstChild("SafeZoneRegion") ~= nil))
		end

		if arena then
			log(prefix .. " ArenaSpawnRegion: "
				.. tostring(arena:FindFirstChild("ArenaSpawnRegion") ~= nil))
		end
	end
end

local function hook_zone_events(zones: Instance)
	-- Logs if Zones is reparented or removed.
	zones.AncestryChanged:Connect(function(_, parent)
		warn_log("Zones.AncestryChanged -> parent=" .. tostring(parent))
		dump_state("After ancestry change:")
	end)

	-- Logs if key children are removed.
	zones.DescendantRemoving:Connect(function(inst)
		if inst.Name == "SafeZoneRegion"
			or inst.Name == "ArenaSpawnRegion"
			or inst.Name == "SafeZoneWorld"
			or inst.Name == "ArenaWorld"
		then
			warn_log("DescendantRemoving: " .. inst:GetFullName())
			dump_state("After descendant removing:")
		end
	end)
end

function ZonesWatchdog.start()
	if not RunService:IsStudio() then
		warn_log("Not running (only enabled in Studio).")
		return
	end

	log("Starting. " .. VERSION)
	dump_state("Initial:")

	-- Watch for Zones being added/removed at the Workspace level.
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Zones" then
			warn_log("Workspace.ChildAdded: Zones appeared.")
			hook_zone_events(child)
			dump_state("After Zones added:")
		end
	end)

	Workspace.ChildRemoved:Connect(function(child)
		if child.Name == "Zones" then
			warn_log("Workspace.ChildRemoved: Zones disappeared!")
			dump_state("After Zones removed:")
		end
	end)

	-- If Zones exists now, hook it.
	local zones = Workspace:FindFirstChild("Zones")
	if zones then
		hook_zone_events(zones)
	end

	-- Periodic check so we can see “exists then disappears” in timestamps.
	task.spawn(function()
		while true do
			local ok_zones = exists("Zones")
			local ok_safe = exists("Zones/SafeZoneWorld/SafeZoneRegion")
			local ok_arena = exists("Zones/ArenaWorld/ArenaSpawnRegion")

			log(("Heartbeat Zones=%s SafeRegion=%s ArenaRegion=%s"):format(
				tostring(ok_zones),
				tostring(ok_safe),
				tostring(ok_arena)
			))

			task.wait(2)
		end
	end)
end

return ZonesWatchdog
