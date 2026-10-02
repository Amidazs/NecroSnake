--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BackpackService = {}

export type UnitSnapshot = {
	record_id: string?,
	template_name: string,
	size_tier: string?,
	trait: string?,
	evolution_id: string?,
	ability_ids: { string }?,
	source_master_id: string?,
	deployed_master_id: string?,
	acquisition_kind: string?,
	command_cost: number?,
}

export type LoadoutCounts = { [string]: number }

local collection_service = nil :: any
local unit_record_service = nil :: any
local loadout_by_user_id: { [number]: LoadoutCounts } = {}
local did_start = false

local function log(message: string)
	print("[BackpackService] " .. message)
end

local function get_units(player: Player): { UnitSnapshot }
	if not collection_service
		or not collection_service.get_deployable_units
	then
		return {}
	end
	return collection_service.get_deployable_units(player)
end

local function fire_update(player: Player)
	Remotes.backpack_update():FireClient(
		player,
		get_units(player)
	)
end

local function copy_loadout(
	raw: any
): LoadoutCounts
	local copied: LoadoutCounts = {}
	if typeof(raw) ~= "table" then
		return copied
	end

	for key, value in pairs(raw) do
		if typeof(key) == "string"
			and typeof(value) == "number"
			and value > 0
		then
			copied[key] = math.floor(value)
		end
	end
	return copied
end

local function hook_player(player: Player)
	player:GetAttributeChangedSignal(
		"SoulProfileLoaded"
	):Connect(function()
		if player:GetAttribute("SoulProfileLoaded") == true then
			fire_update(player)
		end
	end)

	if player:GetAttribute("SoulProfileLoaded") == true then
		task.defer(fire_update, player)
	end
end

local function on_backpack_request(player: Player)
	fire_update(player)
end

local function on_set_loadout(
	player: Player,
	loadout_counts: any
)
	loadout_by_user_id[player.UserId] = copy_loadout(
		loadout_counts
	)
end

function BackpackService.init(
	collection_service_ref: any,
	unit_record_service_ref: any?
)
	collection_service = collection_service_ref
	unit_record_service = unit_record_service_ref
end

function BackpackService.start()
	if did_start then
		return
	end
	did_start = true

	for _, player in ipairs(Players:GetPlayers()) do
		hook_player(player)
	end

	Players.PlayerAdded:Connect(hook_player)
	Players.PlayerRemoving:Connect(function(player)
		loadout_by_user_id[player.UserId] = nil
	end)

	Remotes.backpack_request().OnServerEvent:Connect(
		on_backpack_request
	)
	Remotes.backpack_set_loadout().OnServerEvent:Connect(
		on_set_loadout
	)

	log("Ready.")
end

function BackpackService.set_backpack(
	player: Player,
	snapshot: { UnitSnapshot }
)
	if not collection_service then
		return
	end

	collection_service.clear_deployable_units(player)
	collection_service.append_extracted_units(
		player,
		snapshot
	)
	fire_update(player)
end

function BackpackService.store_snapshot_append(
	player: Player,
	snapshot: { UnitSnapshot }
)
	if not collection_service then
		return
	end

	collection_service.append_extracted_units(
		player,
		snapshot
	)
	fire_update(player)
end

function BackpackService.get_backpack(
	player: Player
): { UnitSnapshot }
	return get_units(player)
end

function BackpackService.has_units(player: Player): boolean
	return #get_units(player) > 0
end

function BackpackService.take_backpack(
	player: Player
): { UnitSnapshot }?
	if not collection_service then
		return nil
	end

	local snapshot =
		collection_service.take_all_deployable_units(player)
	fire_update(player)
	return snapshot
end

function BackpackService.clear_backpack(player: Player)
	if collection_service then
		collection_service.clear_deployable_units(player)
	end
	fire_update(player)
end

function BackpackService.push_update(player: Player)
	fire_update(player)
end

--[[
	Builds the same stacking key used by the Soul Collection.

	Args:
		record (UnitSnapshot): Unit record to identify.

	Returns:
		string: Stable stack key.
]]
local function get_unit_stack_key(
	record: UnitSnapshot
): string
	if unit_record_service
		and unit_record_service.stack_key
	then
		return unit_record_service.stack_key(record)
	end

	return table.concat({
		record.template_name,
		record.size_tier or "",
		record.trait or "",
		record.evolution_id or "",
		table.concat(record.ability_ids or {}, ","),
		record.deployed_master_id or "",
	}, "|")
end

--[[
	Returns one unit's weighted command cost.

	Args:
		record (UnitSnapshot): Unit to inspect.

	Returns:
		number: Positive command cost.
]]
local function get_record_command_cost(
	record: UnitSnapshot
): number
	if typeof(record.command_cost) == "number" then
		return math.max(1, record.command_cost)
	end
	return 1
end

function BackpackService.get_loadout_counts(
	player: Player
): LoadoutCounts?
	return loadout_by_user_id[player.UserId]
end

--[[
	Estimates the selected Arena loadout command cost.

	Args:
		player (Player): Player whose loadout should be scored.

	Returns:
		number: Selected loadout cost, or total Vault cost when no
			explicit loadout has been selected.
]]
function BackpackService.get_match_loadout_cost(
	player: Player
): number
	local units = get_units(player)
	local counts = loadout_by_user_id[player.UserId]

	if not counts or next(counts) == nil then
		local total = 0
		for _, record in ipairs(units) do
			total += get_record_command_cost(record)
		end
		return total
	end

	local remaining: LoadoutCounts = copy_loadout(counts)
	local total = 0
	for _, record in ipairs(units) do
		local key = get_unit_stack_key(record)
		local requested = remaining[key] or 0
		if requested > 0 then
			total += get_record_command_cost(record)
			remaining[key] = requested - 1
		end
	end
	return total
end

function BackpackService.remove_units_by_key(
	player: Player,
	key: string,
	count: number
): number
	if not collection_service then
		return 0
	end

	local removed = collection_service.remove_units_by_key(
		player,
		key,
		count
	)
	fire_update(player)
	return removed
end

function BackpackService.add_units(
	player: Player,
	units: { UnitSnapshot }
)
	if collection_service then
		collection_service.append_extracted_units(
			player,
			units
		)
	end
	fire_update(player)
end

function BackpackService.take_loadout_units(
	player: Player
): { UnitSnapshot }?
	if not collection_service then
		return nil
	end

	local counts = loadout_by_user_id[player.UserId]
	if not counts then
		return nil
	end

	local selected = collection_service.take_units_by_counts(
		player,
		counts
	)
	fire_update(player)
	return selected
end

return BackpackService
