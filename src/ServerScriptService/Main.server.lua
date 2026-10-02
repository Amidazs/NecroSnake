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

local FactionService = require(
	ServicesFolder:WaitForChild("FactionService")
)

local EvolutionService = require(
	ServicesFolder:WaitForChild("EvolutionService")
)

local WorldEventService = require(
	ServicesFolder:WaitForChild("WorldEventService")
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

local PvPService = require(
	ServicesFolder:WaitForChild("PvPService")
)

local ArmyRegenService = require(
	ServicesFolder:WaitForChild("ArmyRegenService")
)

local BackpackService = require(
	ServicesFolder:WaitForChild("BackpackService")
)

local UnitRecordService = require(
	ServicesFolder:WaitForChild("UnitRecordService")
)

local SoulCollectionService = require(
	ServicesFolder:WaitForChild("SoulCollectionService")
)

local NecromancerProgressionService = require(
	ServicesFolder:WaitForChild("NecromancerProgressionService")
)

local NecromancerSkillService = require(
	ServicesFolder:WaitForChild("NecromancerSkillService")
)

local FormationProfileService = require(
	ServicesFolder:WaitForChild("FormationProfileService")
)

local PartyService = require(
	ServicesFolder:WaitForChild("PartyService")
)

local MatchmakingService = require(
	ServicesFolder:WaitForChild("MatchmakingService")
)

local PlotService = require(
	ServicesFolder:WaitForChild("PlotService")
)

local TeleportService = require(
	ServicesFolder:WaitForChild("TeleportService")
)

local PlayerCombatService = require(
	ServicesFolder:WaitForChild("PlayerCombatService")
)

local PlayerMovementService = require(
	ServicesFolder:WaitForChild("PlayerMovementService")
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

	-- Remotes used by active necromancy / Banish
	Remotes.necromancy_result()
	Remotes.banish_request()
	Remotes.formation_profile()
	Remotes.soul_collection()
	Remotes.progression()
	Remotes.skills()
	Remotes.world_event()
	Remotes.party_action()
	Remotes.party_update()
	Remotes.matchmaking_action()
	Remotes.matchmaking_update()

	-- Fix weapon client infinite yield (expects this at ReplicatedStorage root)
	ensure_remote_event_root("NecroMVP_Swing")

	-- Start services
	ModelLibraryService.init()
	SoulCollectionService.init(
		ModelLibraryService,
		UnitRecordService
	)
	SoulCollectionService.start()
	NecromancerProgressionService.init(SoulCollectionService)
	NecromancerProgressionService.start()
	BackpackService.init(
		SoulCollectionService,
		UnitRecordService
	)
	BackpackService.start()

	FormationProfileService.init(ModelLibraryService)
	FormationProfileService.start()
	ArmyService.init(
		ModelLibraryService,
		FormationProfileService,
		UnitRecordService,
		FactionService,
		EvolutionService
	)
	PvPService.init(
		ArmyService,
		NecromancerProgressionService
	)
	PartyService.init(PvPService)
	PartyService.start()
	PvPService.set_party_service(PartyService)

	MatchmakingService.init(
		PartyService,
		BackpackService,
		SoulCollectionService,
		PvPService
	)
	MatchmakingService.start()

	PlotService.start()

	ArmyAIService.init(ArmyService, PvPService)
	ArmyRegenService.init(ArmyService)

	NPCService.init(
		ModelLibraryService,
		ArmyService,
		FactionService
	)
	CombatService.init(
		ArmyService,
		PvPService,
		NecromancerProgressionService
	)
	PlayerCombatService.init(PvPService)
	NecromancerSkillService.init(
		ArmyService,
		NecromancerProgressionService,
		PvPService
	)

	PvPService.start()
	NPCService.start()
	ArmyAIService.start()
	CombatService.start()
	ArmyRegenService.start()
	NecromancerSkillService.start()

	WorldEventService.init(
		ArmyService,
		EvolutionService
	)
	WorldEventService.start()

	TeleportService.init(
		ArmyService,
		BackpackService,
		PvPService,
		MatchmakingService,
		PlotService
	)
	TeleportService.start()
	PlayerMovementService.start()
	PlayerCombatService.start()
end

main()
