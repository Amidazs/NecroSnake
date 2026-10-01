--!strict
-- BackpackService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local BackpackService = {}

export type UnitSnapshot = {
	template_name: string,
	size_tier: string?,
	trait: string?,
}

export type LoadoutCounts = { [string]: number }

local backpack_by_user_id: { [number]: { UnitSnapshot } } = {}
local loadout_by_user_id: { [number]: LoadoutCounts } = {}

local did_start = false

local function log(message: string)
	print("[BackpackService] " .. message)
end

local function clear_for_user_id(user_id: number)
	backpack_by_user_id[user_id] = nil
	loadout_by_user_id[user_id] = nil
end

local function get_or_create_backpack(user_id: number): { UnitSnapshot }
	local existing = backpack_by_user_id[user_id]
	if existing then
		return existing
	end

	local fresh: { UnitSnapshot } = {}
	backpack_by_user_id[user_id] = fresh
	return fresh
end

local function unit_key(u: UnitSnapshot): string
	return table.concat({
		u.template_name,
		u.size_tier or "",
		u.trait or "",
	}, "|")
end

local function fire_update(player: Player)
	local snapshot = get_or_create_backpack(player.UserId)
	Remotes.backpack_update():FireClient(player, snapshot)
end

local function on_backpack_request(player: Player)
	fire_update(player)
end

local function on_set_loadout(player: Player, loadout_counts: LoadoutCounts)
	-- Copy the table so client mutations cannot affect server state by reference.
	local copied: LoadoutCounts = {}
	for key, value in pairs(loadout_counts) do
		if typeof(key) == "string" and typeof(value) == "number" then
			copied[key] = math.floor(value)
		end
	end
	loadout_by_user_id[player.UserId] = copied
end

function BackpackService.start()
	if did_start then
		return
	end

	did_start = true

	Players.PlayerRemoving:Connect(function(player: Player)
		clear_for_user_id(player.UserId)
	end)

	Remotes.backpack_request().OnServerEvent:Connect(on_backpack_request)
	Remotes.backpack_set_loadout().OnServerEvent:Connect(on_set_loadout)

	log("Ready.")
end

function BackpackService.set_backpack(player: Player, snapshot: { UnitSnapshot })
	backpack_by_user_id[player.UserId] = snapshot
	fire_update(player)
end

function BackpackService.store_snapshot_append(player: Player, snapshot: { UnitSnapshot })
	local backpack = get_or_create_backpack(player.UserId)

	for _, unit in ipairs(snapshot) do
		table.insert(backpack, unit)
	end

	fire_update(player)
end

function BackpackService.get_backpack(player: Player): { UnitSnapshot }?
	return backpack_by_user_id[player.UserId]
end

function BackpackService.has_units(player: Player): boolean
	local snapshot = backpack_by_user_id[player.UserId]
	return snapshot ~= nil and #snapshot > 0
end

function BackpackService.take_backpack(player: Player): { UnitSnapshot }?
	local snapshot = backpack_by_user_id[player.UserId]
	backpack_by_user_id[player.UserId] = nil
	fire_update(player)
	return snapshot
end

function BackpackService.clear_backpack(player: Player)
	clear_for_user_id(player.UserId)
	fire_update(player)
end

function BackpackService.push_update(player: Player)
	fire_update(player)
end

function BackpackService.get_loadout_counts(player: Player): LoadoutCounts?
	return loadout_by_user_id[player.UserId]
end

-- ✅ NEW: Remove up to `count` units matching the exact key.
function BackpackService.remove_units_by_key(
	player: Player,
	key: string,
	count: number
): number
	if count <= 0 then
		return 0
	end

	local backpack = get_or_create_backpack(player.UserId)
	local removed = 0
	local kept: { UnitSnapshot } = {}

	for _, u in ipairs(backpack) do
		if removed < count and unit_key(u) == key then
			removed += 1
		else
			table.insert(kept, u)
		end
	end

	backpack_by_user_id[player.UserId] = kept
	fire_update(player)

	return removed
end

-- ✅ NEW: Add units to backpack (append).
function BackpackService.add_units(player: Player, units: { UnitSnapshot })
	local backpack = get_or_create_backpack(player.UserId)

	for _, u in ipairs(units) do
		table.insert(backpack, u)
	end

	fire_update(player)
end


-- ✅ NEW: Remove units matching the player's loadout selection and return them.
-- This keeps remaining units in the backpack so they are not lost.
function BackpackService.take_loadout_units(player: Player): { UnitSnapshot }?
	local counts = loadout_by_user_id[player.UserId]
	if not counts then
		return nil
	end

	local backpack = get_or_create_backpack(player.UserId)
	local selected: { UnitSnapshot } = {}
	local kept: { UnitSnapshot } = {}

	local remaining_by_key: { [string]: number } = {}
	for key, count in pairs(counts) do
		if typeof(key) == "string" and typeof(count) == "number" and count > 0 then
			remaining_by_key[key] = math.floor(count)
		end
	end

	for _, unit in ipairs(backpack) do
		local key = unit_key(unit)
		local remaining = remaining_by_key[key]
		if remaining and remaining > 0 then
			table.insert(selected, unit)
			remaining_by_key[key] = remaining - 1
		else
			table.insert(kept, unit)
		end
	end

	backpack_by_user_id[player.UserId] = kept
	fire_update(player)

	if #selected == 0 then
		return nil
	end

	return selected
end

return BackpackService
