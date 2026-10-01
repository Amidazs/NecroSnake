--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local ServicesFolder = ServerScriptService:WaitForChild("Services")

local ModelLibraryService = require(
	ServicesFolder:WaitForChild("ModelLibraryService")
)

local ArmyService = require(
	ServicesFolder:WaitForChild("ArmyService")
)

local ArmyAIService = require(
	ServicesFolder:WaitForChild("ArmyAIService")
)

local NPCService = require(
	ServicesFolder:WaitForChild("NPCService")
)

local CombatService = require(
	ServicesFolder:WaitForChild("CombatService")
)

local ArmyRegenService = require(
	ServicesFolder:WaitForChild("ArmyRegenService")
)

local BackpackService = require(
	ServicesFolder:WaitForChild("BackpackService")
)

local TeleportService = require(
	ServicesFolder:WaitForChild("TeleportService")
)

local PlayerCombatService = require(
	ServicesFolder:WaitForChild("PlayerCombatService")
)

local function ensure_remote_event_root(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local evt = Instance.new("RemoteEvent")
	evt.Name = name
	evt.Parent = ReplicatedStorage
	return evt
end

local function start_zones_watchdog()
	if not RunService:IsStudio() then
		return
	end

	local tools = ServerScriptService:FindFirstChild("Tools")
	if not tools then
		return
	end

	local watchdog_module = tools:FindFirstChild("ZonesWatchdog")
	if not watchdog_module then
		return
	end

	require(watchdog_module).start()
end


local function main()
	start_zones_watchdog()

	-- Remotes used by existing systems
	Remotes.get_or_create_event("RequestSummon")

	-- Remotes used by teleport UI/service
	Remotes.teleport_request()
	Remotes.teleport_result()

	-- Remotes used by backpack UI/service
	Remotes.backpack_update()
	Remotes.backpack_request()
	Remotes.backpack_set_loadout()


	-- Fix weapon client infinite yield (expects this at ReplicatedStorage root)
	ensure_remote_event_root("NecroMVP_Swing")

	-- Start services
	BackpackService.start()

	ModelLibraryService.init()
	ArmyService.init(ModelLibraryService)
	ArmyAIService.init(ArmyService)
	ArmyRegenService.init(ArmyService)

	NPCService.init(ModelLibraryService, ArmyService)
	CombatService.init(ArmyService)

	NPCService.start()
	ArmyAIService.start()
	CombatService.start()
	ArmyRegenService.start()

	TeleportService.init(ArmyService, BackpackService)
	TeleportService.start()
	PlayerCombatService.start()
end

main()
