--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_FOLDER_NAME = "Remotes"

local Remotes = {}

function Remotes.get_folder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

function Remotes.get_or_create_event(name: string): RemoteEvent
	local folder = Remotes.get_folder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote_event = Instance.new("RemoteEvent")
	remote_event.Name = name
	remote_event.Parent = folder
	return remote_event
end

-- Teleport
function Remotes.teleport_request(): RemoteEvent
	return Remotes.get_or_create_event("TeleportRequest")
end

function Remotes.teleport_result(): RemoteEvent
	return Remotes.get_or_create_event("TeleportResult")
end

-- Backpack
function Remotes.backpack_update(): RemoteEvent
	return Remotes.get_or_create_event("BackpackUpdate")
end

function Remotes.backpack_request(): RemoteEvent
	return Remotes.get_or_create_event("BackpackRequest")
end

function Remotes.backpack_set_loadout(): RemoteEvent
	return Remotes.get_or_create_event("BackpackSetLoadout")
end

-- Active necromancy / army management
function Remotes.necromancy_result(): RemoteEvent
	return Remotes.get_or_create_event("NecromancyResult")
end

function Remotes.banish_request(): RemoteEvent
	return Remotes.get_or_create_event("BanishRequest")
end

function Remotes.combat_feedback(): RemoteEvent
	return Remotes.get_or_create_event("CombatFeedback")
end

function Remotes.army_command(): RemoteEvent
	return Remotes.get_or_create_event("ArmyCommand")
end

function Remotes.formation_profile(): RemoteEvent
	return Remotes.get_or_create_event("FormationProfile")
end

function Remotes.soul_collection(): RemoteEvent
	return Remotes.get_or_create_event("SoulCollection")
end

function Remotes.progression(): RemoteEvent
	return Remotes.get_or_create_event("NecromancerProgression")
end

function Remotes.skills(): RemoteEvent
	return Remotes.get_or_create_event("NecromancerSkills")
end

function Remotes.world_event(): RemoteEvent
	return Remotes.get_or_create_event("WorldEvent")
end

return Remotes
