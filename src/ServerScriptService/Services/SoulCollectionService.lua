--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)
local SoulProfileStore = require(
	script.Parent:WaitForChild("SoulProfileStore")
)

local SoulCollectionService = {}

local PROFILE_VERSION = 1
local STARTING_SOUL_ESSENCE = 60
local STARTING_BASE_LEVEL = 1
local MAX_BASE_LEVEL = 3
local MAX_MACHINE_LEVEL = 5
local MAX_STARTER_UNITS_TO_SECURE = 3

local MACHINE_BASE_CAPACITY = 3
local MACHINE_CAPACITY_PER_LEVEL = 2
local BASE_CLONE_SECONDS = 60
local MACHINE_SPEED_PER_LEVEL = 0.20
local PROCESS_INTERVAL_SECONDS = 2
local SAVE_DEBOUNCE_SECONDS = 1

local BASE_UPGRADE_COST: { [number]: number } = {
	[2] = 100,
	[3] = 250,
}

local ZONES_FOLDER_NAME = "Zones"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"

type UnitRecord = {
	record_id: string,
	template_name: string,
	size_tier: string?,
	trait: string?,
	evolution_id: string?,
	ability_ids: { string },
	source_master_id: string?,
	deployed_master_id: string?,
	acquisition_kind: string?,
	command_cost: number?,
}

type MachineState = {
	machine_id: string,
	level: number,
	master_id: string?,
	master_snapshot: UnitRecord?,
	output_count: number,
	last_processed_at: number,
	paused: boolean,
}

type Profile = {
	version: number,
	revision: number,
	units: { UnitRecord },
	masters: { [string]: UnitRecord },
	machines: { MachineState },
	soul_essence: number,
	base_level: number,
	starter_secured_count: number,
	persistent: boolean,
	dirty: boolean,
	save_token: number,
}

local model_library_service = nil :: any
local unit_record_service = nil :: any
local profiles_by_user_id: { [number]: Profile } = {}
local did_start = false
local process_task: thread? = nil

local function log(message: string)
	print("[SoulCollectionService] " .. message)
end

local function warnf(message: string)
	warn("[SoulCollectionService] " .. message)
end

local function now_seconds(): number
	return os.time()
end

local function copy_record(raw: any): UnitRecord?
	if not unit_record_service then
		return nil
	end
	return unit_record_service.copy(raw)
end

local function normalize_record(raw: any): UnitRecord?
	if not unit_record_service then
		return nil
	end
	return unit_record_service.normalize(raw)
end

local function make_machine(
	index: number,
	now: number
): MachineState
	return {
		machine_id = ("machine-%d"):format(index),
		level = 1,
		master_id = nil,
		master_snapshot = nil,
		output_count = 0,
		last_processed_at = now,
		paused = false,
	}
end

local function create_default_profile(): Profile
	local now = now_seconds()
	return {
		version = PROFILE_VERSION,
		revision = 0,
		units = {},
		masters = {},
		machines = { make_machine(1, now) },
		soul_essence = STARTING_SOUL_ESSENCE,
		base_level = STARTING_BASE_LEVEL,
		starter_secured_count = 0,
		persistent = false,
		dirty = false,
		save_token = 0,
	}
end

local function sanitize_positive_int(
	value: any,
	default_value: number
): number
	if typeof(value) ~= "number" then
		return default_value
	end
	return math.max(0, math.floor(value))
end

local function sanitize_machine(
	raw: any,
	index: number,
	now: number
): MachineState
	local machine = make_machine(index, now)
	if typeof(raw) ~= "table" then
		return machine
	end

	if typeof(raw.machine_id) == "string" and raw.machine_id ~= "" then
		machine.machine_id = raw.machine_id
	end
	machine.level = math.clamp(
		sanitize_positive_int(raw.level, 1),
		1,
		MAX_MACHINE_LEVEL
	)
	if typeof(raw.master_id) == "string" and raw.master_id ~= "" then
		machine.master_id = raw.master_id
	end
	machine.master_snapshot = copy_record(raw.master_snapshot)
	machine.output_count = sanitize_positive_int(
		raw.output_count,
		0
	)
	if typeof(raw.last_processed_at) == "number" then
		machine.last_processed_at = math.floor(raw.last_processed_at)
	end
	machine.paused = raw.paused == true
	return machine
end

local function sanitize_units(raw: any): { UnitRecord }
	local units: { UnitRecord } = {}
	if typeof(raw) ~= "table" then
		return units
	end

	for _, item in ipairs(raw) do
		local record = normalize_record(item)
		if record then
			table.insert(units, record)
		end
	end
	return units
end

local function sanitize_masters(raw: any): { [string]: UnitRecord }
	local masters: { [string]: UnitRecord } = {}
	if typeof(raw) ~= "table" then
		return masters
	end

	for _, item in ipairs(raw) do
		local record = normalize_record(item)
		if record then
			masters[record.record_id] = record
		end
	end
	return masters
end

local function ensure_machine_count(profile: Profile)
	local required = math.clamp(
		profile.base_level,
		STARTING_BASE_LEVEL,
		MAX_BASE_LEVEL
	)
	while #profile.machines < required do
		table.insert(
			profile.machines,
			make_machine(#profile.machines + 1, now_seconds())
		)
	end
end

local function sanitize_profile(
	raw: any,
	persistent: boolean
): Profile
	if typeof(raw) ~= "table" then
		local fresh = create_default_profile()
		fresh.persistent = persistent
		return fresh
	end

	local profile = create_default_profile()
	profile.revision = sanitize_positive_int(raw.revision, 0)
	profile.units = sanitize_units(raw.units)
	profile.masters = sanitize_masters(raw.masters)
	profile.soul_essence = sanitize_positive_int(
		raw.soul_essence,
		STARTING_SOUL_ESSENCE
	)
	profile.base_level = math.clamp(
		sanitize_positive_int(raw.base_level, STARTING_BASE_LEVEL),
		STARTING_BASE_LEVEL,
		MAX_BASE_LEVEL
	)
	profile.starter_secured_count = math.clamp(
		sanitize_positive_int(raw.starter_secured_count, 0),
		0,
		MAX_STARTER_UNITS_TO_SECURE
	)
	profile.machines = {}

	if typeof(raw.machines) == "table" then
		for index, machine_raw in ipairs(raw.machines) do
			table.insert(
				profile.machines,
				sanitize_machine(
					machine_raw,
					index,
					now_seconds()
				)
			)
		end
	end

	ensure_machine_count(profile)
	profile.persistent = persistent
	return profile
end

local function get_profile(player: Player): Profile?
	return profiles_by_user_id[player.UserId]
end

local function get_safe_zone_region(): BasePart?
	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	local safe_world = zones and zones:FindFirstChild(
		SAFE_ZONE_MODEL_NAME
	)
	local region = safe_world and safe_world:FindFirstChild(
		SAFE_ZONE_REGION_NAME
	)
	if region and region:IsA("BasePart") then
		return region
	end
	return nil
end

local function is_in_part(
	part: BasePart,
	position: Vector3
): boolean
	local local_position = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	return math.abs(local_position.X) <= half.X
		and math.abs(local_position.Y) <= half.Y
		and math.abs(local_position.Z) <= half.Z
end

local function is_player_in_safe_zone(player: Player): boolean
	if player:GetAttribute("PvPZone") == "SafeZone" then
		return true
	end

	local character = player.Character
	local root = character and character:FindFirstChild(
		"HumanoidRootPart"
	)
	local region = get_safe_zone_region()
	if not (root and root:IsA("BasePart") and region) then
		return false
	end
	return is_in_part(region, root.Position)
end

local function get_record_command_cost(record: UnitRecord): number
	if typeof(record.command_cost) == "number" then
		return math.max(1, math.floor(record.command_cost))
	end

	if model_library_service
		and model_library_service.get_unit_stats
	then
		local stats = model_library_service.get_unit_stats(
			record.template_name
		)
		if stats and typeof(stats.CommandCost) == "number" then
			local cost = math.max(
				1,
				math.floor(stats.CommandCost)
			)
			if record.size_tier == "Giant" then
				cost = math.max(
					cost + 1,
					math.ceil(cost * 1.5)
				)
			end
			return cost
		end
	end
	return 1
end

local function get_clone_cost(record: UnitRecord): number
	local cost = get_record_command_cost(record) * 10
	if record.size_tier == "Giant" then
		cost += 8
	end
	if record.trait and record.trait ~= "None" then
		cost += 5
	end
	if record.evolution_id then
		cost += 10
	end
	return math.max(5, cost)
end

local function get_dissolve_value(record: UnitRecord): number
	local value = get_record_command_cost(record) * 6
	if record.size_tier == "Giant" then
		value += 5
	end
	if record.trait and record.trait ~= "None" then
		value += 3
	end
	if record.evolution_id then
		value += 5
	end
	return math.max(3, value)
end

local function get_machine_capacity(machine: MachineState): number
	return MACHINE_BASE_CAPACITY
		+ ((machine.level - 1) * MACHINE_CAPACITY_PER_LEVEL)
end

local function get_clone_seconds(
	machine: MachineState,
	record: UnitRecord
): number
	local base = BASE_CLONE_SECONDS
		* get_record_command_cost(record)
	local speed = 1
		+ ((machine.level - 1) * MACHINE_SPEED_PER_LEVEL)
	return math.max(20, math.floor(base / speed))
end

local function get_machine_upgrade_cost(
	machine: MachineState
): number
	return 60 * machine.level
end

local function get_base_upgrade_cost(profile: Profile): number?
	return BASE_UPGRADE_COST[profile.base_level + 1]
end

local function find_machine(
	profile: Profile,
	machine_id: string
): MachineState?
	for _, machine in ipairs(profile.machines) do
		if machine.machine_id == machine_id then
			return machine
		end
	end
	return nil
end

local function find_unit_index(
	profile: Profile,
	record_id: string
): number?
	for index, record in ipairs(profile.units) do
		if record.record_id == record_id then
			return index
		end
	end
	return nil
end

local function is_master_assigned_elsewhere(
	profile: Profile,
	master_id: string,
	excluded_machine_id: string?
): boolean
	for _, machine in ipairs(profile.machines) do
		if machine.machine_id ~= excluded_machine_id
			and machine.master_id == master_id
		then
			return true
		end
	end
	return false
end

local function process_machine(
	profile: Profile,
	machine: MachineState,
	now: number
): boolean
	local master_id = machine.master_id
	if not master_id then
		return false
	end

	local master = profile.masters[master_id]
	if not master then
		machine.master_id = nil
		machine.paused = true
		machine.last_processed_at = now
		return true
	end

	if not machine.master_snapshot then
		machine.master_snapshot = copy_record(master)
	end

	local capacity = get_machine_capacity(machine)
	local clone_cost = get_clone_cost(master)
	local has_room = machine.output_count < capacity
	local can_afford = profile.soul_essence >= clone_cost

	if machine.paused then
		if not (has_room and can_afford) then
			return false
		end
		machine.paused = false
		machine.last_processed_at = now
		return true
	end

	if not has_room or not can_afford then
		machine.paused = true
		machine.last_processed_at = now
		return true
	end

	local duration = get_clone_seconds(machine, master)
	local elapsed = math.max(0, now - machine.last_processed_at)
	local cycles = math.floor(elapsed / duration)
	if cycles <= 0 then
		return false
	end

	local storage_room = capacity - machine.output_count
	local affordable = math.floor(profile.soul_essence / clone_cost)
	local produced = math.min(cycles, storage_room, affordable)
	if produced <= 0 then
		machine.paused = true
		machine.last_processed_at = now
		return true
	end

	machine.output_count += produced
	profile.soul_essence -= produced * clone_cost
	machine.last_processed_at += produced * duration

	if produced < cycles
		or machine.output_count >= capacity
		or profile.soul_essence < clone_cost
	then
		machine.paused = true
		machine.last_processed_at = now
	end
	return true
end

local function process_profile(
	profile: Profile,
	now: number
): boolean
	local changed = false
	for _, machine in ipairs(profile.machines) do
		if process_machine(profile, machine, now) then
			changed = true
		end
	end
	return changed
end

local function copy_records(
	records: { UnitRecord }
): { UnitRecord }
	local result: { UnitRecord } = {}
	for _, record in ipairs(records) do
		local copied = copy_record(record)
		if copied then
			table.insert(result, copied)
		end
	end
	return result
end

local function masters_as_array(
	profile: Profile
): { UnitRecord }
	local result: { UnitRecord } = {}
	for _, record in pairs(profile.masters) do
		local copied = copy_record(record)
		if copied then
			table.insert(result, copied)
		end
	end
	table.sort(result, function(a, b)
		return a.record_id < b.record_id
	end)
	return result
end

local function build_persistence_snapshot(profile: Profile)
	local machines = {}
	for _, machine in ipairs(profile.machines) do
		table.insert(machines, {
			machine_id = machine.machine_id,
			level = machine.level,
			master_id = machine.master_id,
			master_snapshot = copy_record(
				machine.master_snapshot
			),
			output_count = machine.output_count,
			last_processed_at = machine.last_processed_at,
			paused = machine.paused,
		})
	end

	return {
		version = PROFILE_VERSION,
		revision = profile.revision,
		units = copy_records(profile.units),
		masters = masters_as_array(profile),
		machines = machines,
		soul_essence = profile.soul_essence,
		base_level = profile.base_level,
		starter_secured_count = profile.starter_secured_count,
	}
end

local function machine_client_snapshot(
	profile: Profile,
	machine: MachineState,
	now: number
)
	local master = if machine.master_id
		then profile.masters[machine.master_id]
		else nil
	local record = master or machine.master_snapshot

	local clone_cost = nil
	local clone_seconds = nil
	local seconds_remaining = nil
	if record then
		clone_cost = get_clone_cost(record)
		clone_seconds = get_clone_seconds(machine, record)
		if machine.master_id and not machine.paused then
			local elapsed = math.max(
				0,
				now - machine.last_processed_at
			)
			seconds_remaining = math.max(
				0,
				clone_seconds - elapsed
			)
		end
	end

	return {
		machineId = machine.machine_id,
		level = machine.level,
		masterId = machine.master_id,
		master = copy_record(record),
		outputCount = machine.output_count,
		capacity = get_machine_capacity(machine),
		cloneCost = clone_cost,
		cloneSeconds = clone_seconds,
		secondsRemaining = seconds_remaining,
		paused = machine.paused,
		upgradeCost = if machine.level < MAX_MACHINE_LEVEL
			then get_machine_upgrade_cost(machine)
			else nil,
	}
end

local function build_client_snapshot(
	player: Player,
	profile: Profile
)
	local now = now_seconds()
	local machines = {}
	for _, machine in ipairs(profile.machines) do
		table.insert(
			machines,
			machine_client_snapshot(profile, machine, now)
		)
	end

	return {
		kind = "SNAPSHOT",
		revision = profile.revision,
		persistent = profile.persistent,
		inSafeZone = is_player_in_safe_zone(player),
		soulEssence = profile.soul_essence,
		baseLevel = profile.base_level,
		baseUpgradeCost = get_base_upgrade_cost(profile),
		units = copy_records(profile.units),
		masters = masters_as_array(profile),
		machines = machines,
	}
end

local function update_player_attributes(
	player: Player,
	profile: Profile
)
	player:SetAttribute("SoulProfileLoaded", true)
	player:SetAttribute(
		"SoulProfilePersistent",
		profile.persistent
	)
	player:SetAttribute("SoulEssence", profile.soul_essence)
	player:SetAttribute("SoulBaseLevel", profile.base_level)
	player:SetAttribute("SoulMachineCount", #profile.machines)
end

local function send_snapshot(player: Player)
	local profile = get_profile(player)
	if not profile then
		return
	end

	update_player_attributes(player, profile)
	Remotes.soul_collection():FireClient(
		player,
		build_client_snapshot(player, profile)
	)
end

local function send_result(
	player: Player,
	ok: boolean,
	message: string
)
	Remotes.soul_collection():FireClient(player, {
		kind = "RESULT",
		ok = ok,
		message = message,
	})
end

local function save_profile_now(player: Player): boolean
	local profile = get_profile(player)
	if not profile or not profile.dirty then
		return true
	end

	process_profile(profile, now_seconds())
	local snapshot = build_persistence_snapshot(profile)
	local saved, persistent, revision, err =
		SoulProfileStore.save(
			player.UserId,
			snapshot,
			profile.revision
		)

	if saved then
		profile.revision = revision
		profile.persistent = persistent
		if persistent or RunService:IsStudio() then
			profile.dirty = false
		end
		update_player_attributes(player, profile)
		return true
	end

	profile.persistent = persistent
	update_player_attributes(player, profile)
	if err then
		warnf(
			("Save failed for %s: %s"):format(
				player.Name,
				err
			)
		)
	end
	return false
end

local function schedule_save(player: Player)
	local profile = get_profile(player)
	if not profile then
		return
	end

	profile.save_token += 1
	local token = profile.save_token
	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		local current = get_profile(player)
		if not current or current.save_token ~= token then
			return
		end
		save_profile_now(player)
	end)
end

local function mark_changed(
	player: Player,
	profile: Profile,
	should_send: boolean
)
	profile.dirty = true
	update_player_attributes(player, profile)
	schedule_save(player)
	if should_send then
		send_snapshot(player)
	end
end

local function load_profile(player: Player)
	local raw, persistent = SoulProfileStore.load(player.UserId)
	local profile = sanitize_profile(raw, persistent)
	profiles_by_user_id[player.UserId] = profile

	if process_profile(profile, now_seconds()) then
		profile.dirty = true
	end
	update_player_attributes(player, profile)
	send_snapshot(player)

	if profile.dirty then
		schedule_save(player)
	end

	log(("Loaded profile for %s."):format(player.Name))
end

local function require_safe_zone(
	player: Player
): (Profile?, string?)
	local profile = get_profile(player)
	if not profile then
		return nil, "Soul profile is still loading."
	end
	if not is_player_in_safe_zone(player) then
		return nil, "Soul Foundry is only available in the Sanctum."
	end
	return profile, nil
end

local function unit_stack_key(record: UnitRecord): string
	if unit_record_service and unit_record_service.stack_key then
		return unit_record_service.stack_key(record)
	end
	return table.concat({
		record.template_name,
		record.size_tier or "",
		record.trait or "",
	}, "|")
end

local function remove_unit_at(
	profile: Profile,
	index: number
): UnitRecord
	return table.remove(profile.units, index)
end

local function imprint_master(
	player: Player,
	record_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local index = find_unit_index(profile, record_id)
	if not index then
		return false, "Unit is not in your Soul Vault."
	end

	local record = profile.units[index]
	if record.deployed_master_id then
		return false, "That Master is already marked for deployment."
	end

	record = remove_unit_at(profile, index)
	record.acquisition_kind = "Master"
	profile.masters[record.record_id] = record
	mark_changed(player, profile, true)
	return true, "Soul Imprint registered as a Master."
end

local function dissolve_unit(
	player: Player,
	record_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local index = find_unit_index(profile, record_id)
	if not index then
		return false, "Unit is not in your Soul Vault."
	end

	local record = profile.units[index]
	if record.deployed_master_id then
		return false, "An at-risk Master cannot be dissolved."
	end

	record = remove_unit_at(profile, index)
	local gained = get_dissolve_value(record)
	profile.soul_essence += gained
	process_profile(profile, now_seconds())
	mark_changed(player, profile, true)
	return true, ("Dissolved for %d Soul Essence."):format(gained)
end

local function deploy_master(
	player: Player,
	master_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local master = profile.masters[master_id]
	if not master then
		return false, "Master not found."
	end

	for _, machine in ipairs(profile.machines) do
		if machine.master_id == master_id then
			process_machine(profile, machine, now_seconds())
			machine.master_id = nil
			machine.paused = true
			machine.last_processed_at = now_seconds()
		end
	end

	profile.masters[master_id] = nil
	local deployed = copy_record(master)
	if not deployed then
		return false, "Master record is invalid."
	end

	deployed.deployed_master_id = master_id
	deployed.acquisition_kind = "MasterAtRisk"
	table.insert(profile.units, deployed)
	mark_changed(player, profile, true)
	return true, "Master moved to the deployable Soul Vault."
end

local function shelve_master(
	player: Player,
	record_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local index = find_unit_index(profile, record_id)
	if not index then
		return false, "At-risk Master not found."
	end

	local record = profile.units[index]
	local master_id = record.deployed_master_id
	if not master_id then
		return false, "That unit is not an at-risk Master."
	end

	record = remove_unit_at(profile, index)
	record.record_id = master_id
	record.deployed_master_id = nil
	record.acquisition_kind = "Master"
	profile.masters[master_id] = record
	mark_changed(player, profile, true)
	return true, "Master returned to Soul Imprint storage."
end

local function assign_machine(
	player: Player,
	machine_id: string,
	master_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local machine = find_machine(profile, machine_id)
	local master = profile.masters[master_id]
	if not machine or not master then
		return false, "Machine or Master not found."
	end
	if machine.output_count > 0
		and machine.master_id ~= master_id
	then
		return false, "Collect finished clones before changing Master."
	end
	if is_master_assigned_elsewhere(
		profile,
		master_id,
		machine_id
	) then
		return false, "That Master is already assigned elsewhere."
	end

	machine.master_id = master_id
	machine.master_snapshot = copy_record(master)
	machine.last_processed_at = now_seconds()
	machine.paused = false
	process_machine(profile, machine, now_seconds())
	mark_changed(player, profile, true)
	return true, "Master assigned to cloning machine."
end

local function unassign_machine(
	player: Player,
	machine_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local machine = find_machine(profile, machine_id)
	if not machine then
		return false, "Machine not found."
	end

	process_machine(profile, machine, now_seconds())
	machine.master_id = nil
	machine.paused = true
	machine.last_processed_at = now_seconds()
	if machine.output_count <= 0 then
		machine.master_snapshot = nil
	end
	mark_changed(player, profile, true)
	return true, "Cloning machine unassigned."
end

local function collect_machine_output(
	player: Player,
	machine_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local machine = find_machine(profile, machine_id)
	if not machine then
		return false, "Machine not found."
	end

	process_machine(profile, machine, now_seconds())
	if machine.output_count <= 0 or not machine.master_snapshot then
		return false, "No finished clones to collect."
	end

	local count = machine.output_count
	for _ = 1, count do
		local clone = unit_record_service.make_clone(
			machine.master_snapshot
		)
		if clone then
			table.insert(profile.units, clone)
		end
	end

	machine.output_count = 0
	machine.last_processed_at = now_seconds()
	machine.paused = machine.master_id == nil
	if not machine.master_id then
		machine.master_snapshot = nil
	end
	mark_changed(player, profile, true)
	return true, ("Collected %d clone(s)."):format(count)
end

local function upgrade_machine(
	player: Player,
	machine_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end

	local machine = find_machine(profile, machine_id)
	if not machine then
		return false, "Machine not found."
	end
	if machine.level >= MAX_MACHINE_LEVEL then
		return false, "Machine is already fully upgraded."
	end

	local cost = get_machine_upgrade_cost(machine)
	if profile.soul_essence < cost then
		return false, ("Need %d Soul Essence."):format(cost)
	end

	process_machine(profile, machine, now_seconds())
	profile.soul_essence -= cost
	machine.level += 1
	machine.last_processed_at = now_seconds()
	machine.paused = false
	process_machine(profile, machine, now_seconds())
	mark_changed(player, profile, true)
	return true, ("Machine upgraded to level %d."):format(
		machine.level
	)
end

local function upgrade_base(
	player: Player
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end
	if profile.base_level >= MAX_BASE_LEVEL then
		return false, "Soul Foundry is already fully upgraded."
	end

	local cost = get_base_upgrade_cost(profile)
	if not cost or profile.soul_essence < cost then
		return false, ("Need %d Soul Essence."):format(
			cost or 0
		)
	end

	profile.soul_essence -= cost
	profile.base_level += 1
	ensure_machine_count(profile)
	mark_changed(player, profile, true)
	return true, ("Soul Foundry upgraded to level %d."):format(
		profile.base_level
	)
end

local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action == "REQUEST" then
		send_snapshot(player)
		return
	end

	if typeof(action) ~= "string" then
		send_result(player, false, "Invalid Soul Foundry request.")
		return
	end
	payload = if typeof(payload) == "table" then payload else {}

	local ok = false
	local message = "Unknown Soul Foundry action."

	if action == "IMPRINT_MASTER" then
		ok, message = imprint_master(
			player,
			tostring(payload.recordId or "")
		)
	elseif action == "DISSOLVE_UNIT" then
		ok, message = dissolve_unit(
			player,
			tostring(payload.recordId or "")
		)
	elseif action == "DEPLOY_MASTER" then
		ok, message = deploy_master(
			player,
			tostring(payload.masterId or "")
		)
	elseif action == "SHELVE_MASTER" then
		ok, message = shelve_master(
			player,
			tostring(payload.recordId or "")
		)
	elseif action == "ASSIGN_MACHINE" then
		ok, message = assign_machine(
			player,
			tostring(payload.machineId or ""),
			tostring(payload.masterId or "")
		)
	elseif action == "UNASSIGN_MACHINE" then
		ok, message = unassign_machine(
			player,
			tostring(payload.machineId or "")
		)
	elseif action == "COLLECT_OUTPUT" then
		ok, message = collect_machine_output(
			player,
			tostring(payload.machineId or "")
		)
	elseif action == "UPGRADE_MACHINE" then
		ok, message = upgrade_machine(
			player,
			tostring(payload.machineId or "")
		)
	elseif action == "UPGRADE_BASE" then
		ok, message = upgrade_base(player)
	end

	send_result(player, ok, message)
end

function SoulCollectionService.init(
	model_library_ref: any,
	unit_record_ref: any
)
	model_library_service = model_library_ref
	unit_record_service = unit_record_ref
end

function SoulCollectionService.get_deployable_units(
	player: Player
): { UnitRecord }
	local profile = get_profile(player)
	if not profile then
		return {}
	end
	return copy_records(profile.units)
end

function SoulCollectionService.append_extracted_units(
	player: Player,
	raw_units: { any }
): number
	local profile = get_profile(player)
	if not profile then
		return 0
	end

	local added = 0
	for _, raw in ipairs(raw_units) do
		local record = normalize_record(raw)
		if record then
			if record.deployed_master_id then
				local master_id = record.deployed_master_id
				record.record_id = master_id
				record.deployed_master_id = nil
				record.acquisition_kind = "Master"
				profile.masters[master_id] = record
				added += 1
			elseif record.acquisition_kind == "StarterLoan" then
				if profile.starter_secured_count
					< MAX_STARTER_UNITS_TO_SECURE
				then
					profile.starter_secured_count += 1
					record.acquisition_kind = "Starter"
					table.insert(profile.units, record)
					added += 1
				end
			else
				table.insert(profile.units, record)
				added += 1
			end
		end
	end

	if added > 0 then
		mark_changed(player, profile, true)
	end
	return added
end

function SoulCollectionService.take_all_deployable_units(
	player: Player
): { UnitRecord }?
	local profile = get_profile(player)
	if not profile or #profile.units == 0 then
		return nil
	end

	local selected = profile.units
	profile.units = {}
	mark_changed(player, profile, true)
	return selected
end

function SoulCollectionService.take_units_by_counts(
	player: Player,
	counts: { [string]: number }
): { UnitRecord }?
	local profile = get_profile(player)
	if not profile then
		return nil
	end

	local remaining: { [string]: number } = {}
	for key, count in pairs(counts) do
		if typeof(key) == "string"
			and typeof(count) == "number"
			and count > 0
		then
			remaining[key] = math.floor(count)
		end
	end

	local selected: { UnitRecord } = {}
	local kept: { UnitRecord } = {}
	for _, record in ipairs(profile.units) do
		local key = unit_stack_key(record)
		local count = remaining[key] or 0
		if count > 0 then
			table.insert(selected, record)
			remaining[key] = count - 1
		else
			table.insert(kept, record)
		end
	end

	if #selected == 0 then
		return nil
	end

	profile.units = kept
	mark_changed(player, profile, true)
	return selected
end

function SoulCollectionService.remove_units_by_key(
	player: Player,
	key: string,
	count: number
): number
	local profile = get_profile(player)
	if not profile or count <= 0 then
		return 0
	end

	local removed = 0
	local kept: { UnitRecord } = {}
	for _, record in ipairs(profile.units) do
		if removed < count and unit_stack_key(record) == key then
			removed += 1
		else
			table.insert(kept, record)
		end
	end

	if removed > 0 then
		profile.units = kept
		mark_changed(player, profile, true)
	end
	return removed
end

function SoulCollectionService.clear_deployable_units(player: Player)
	local profile = get_profile(player)
	if not profile or #profile.units == 0 then
		return
	end
	profile.units = {}
	mark_changed(player, profile, true)
end

function SoulCollectionService.push_snapshot(player: Player)
	send_snapshot(player)
end

function SoulCollectionService.save_now(player: Player): boolean
	return save_profile_now(player)
end

function SoulCollectionService.imprint_master(
	player: Player,
	record_id: string
): (boolean, string)
	return imprint_master(player, record_id)
end

function SoulCollectionService.deploy_master(
	player: Player,
	master_id: string
): (boolean, string)
	return deploy_master(player, master_id)
end

function SoulCollectionService.shelve_master(
	player: Player,
	record_id: string
): (boolean, string)
	return shelve_master(player, record_id)
end

function SoulCollectionService.assign_machine(
	player: Player,
	machine_id: string,
	master_id: string
): (boolean, string)
	return assign_machine(player, machine_id, master_id)
end

function SoulCollectionService.collect_machine_output(
	player: Player,
	machine_id: string
): (boolean, string)
	return collect_machine_output(player, machine_id)
end

function SoulCollectionService.upgrade_machine(
	player: Player,
	machine_id: string
): (boolean, string)
	return upgrade_machine(player, machine_id)
end

function SoulCollectionService.upgrade_base(
	player: Player
): (boolean, string)
	return upgrade_base(player)
end

function SoulCollectionService.get_snapshot_for_test(
	player: Player
): any?
	if not RunService:IsStudio() then
		return nil
	end
	local profile = get_profile(player)
	if not profile then
		return nil
	end
	return build_client_snapshot(player, profile)
end

function SoulCollectionService.debug_add_essence(
	player: Player,
	amount: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local profile = get_profile(player)
	if not profile then
		return false
	end

	profile.soul_essence = math.max(
		0,
		profile.soul_essence + math.floor(amount)
	)
	process_profile(profile, now_seconds())
	mark_changed(player, profile, true)
	return true
end

function SoulCollectionService.debug_advance_machine(
	player: Player,
	machine_id: string,
	seconds: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local profile = get_profile(player)
	local machine = profile and find_machine(
		profile,
		machine_id
	)
	if not profile or not machine then
		return false
	end

	machine.paused = false
	machine.last_processed_at -= math.max(0, seconds)
	if process_machine(profile, machine, now_seconds()) then
		mark_changed(player, profile, true)
	end
	return true
end

function SoulCollectionService.debug_shift_machine_time(
	player: Player,
	machine_id: string,
	seconds: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local profile = get_profile(player)
	local machine = profile and find_machine(
		profile,
		machine_id
	)
	if not profile or not machine then
		return false
	end

	machine.paused = false
	machine.last_processed_at -= math.max(0, seconds)
	profile.dirty = true
	return true
end

function SoulCollectionService.debug_reset_profile(
	player: Player
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local profile = create_default_profile()
	profiles_by_user_id[player.UserId] = profile
	profile.dirty = true
	update_player_attributes(player, profile)
	send_snapshot(player)
	return true
end

function SoulCollectionService.debug_simulate_offline(
	player: Player,
	seconds: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	if not save_profile_now(player) then
		return false
	end

	local snapshot = SoulProfileStore.get_session_copy_for_test(
		player.UserId
	)
	if typeof(snapshot) ~= "table"
		or typeof(snapshot.machines) ~= "table"
	then
		return false
	end

	for _, machine in ipairs(snapshot.machines) do
		if typeof(machine) == "table"
			and typeof(machine.last_processed_at) == "number"
		then
			machine.paused = false
			machine.last_processed_at -= math.max(0, seconds)
		end
	end

	if not SoulProfileStore.set_session_copy_for_test(
		player.UserId,
		snapshot
	) then
		return false
	end

	profiles_by_user_id[player.UserId] = nil
	load_profile(player)
	return get_profile(player) ~= nil
end

function SoulCollectionService.debug_reload_profile(
	player: Player
): boolean
	if not RunService:IsStudio() then
		return false
	end

	save_profile_now(player)
	profiles_by_user_id[player.UserId] = nil
	load_profile(player)
	return get_profile(player) ~= nil
end

function SoulCollectionService.start()
	if did_start then
		return
	end
	did_start = true

	Remotes.soul_collection().OnServerEvent:Connect(handle_remote)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load_profile, player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load_profile, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		save_profile_now(player)
		profiles_by_user_id[player.UserId] = nil
	end)

	process_task = task.spawn(function()
		while did_start do
			local now = now_seconds()
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = get_profile(player)
				if profile
					and process_profile(profile, now)
				then
					mark_changed(player, profile, true)
				end
			end
			task.wait(PROCESS_INTERVAL_SECONDS)
		end
	end)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save_profile_now(player)
		end
	end)

	log("Ready.")
end

function SoulCollectionService.stop()
	did_start = false
	if process_task then
		task.cancel(process_task)
		process_task = nil
	end
end

return SoulCollectionService
