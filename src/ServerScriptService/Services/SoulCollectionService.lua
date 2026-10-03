--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)
local PlotUpgradeConfig = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("PlotUpgradeConfig")
)
local CodexKnowledgeConfig = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("CodexKnowledgeConfig")
)
local NecromancerSkills = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("NecromancerSkills")
)
local SoulProfileStore = require(
	script.Parent:WaitForChild("SoulProfileStore")
)

local SoulCollectionService = {}

local PROFILE_VERSION = 4
local STARTING_SOUL_ESSENCE = 60
local STARTING_BASE_LEVEL = 1
local MAX_BASE_LEVEL = PlotUpgradeConfig.get_max_level()
local MAX_MACHINE_LEVEL = 5
local MAX_STARTER_UNITS_TO_SECURE = 3

local MACHINE_BASE_CAPACITY = 3
local MACHINE_CAPACITY_PER_LEVEL = 2
local BASE_CLONE_SECONDS = 60
local MACHINE_SPEED_PER_LEVEL = 0.20
local PROCESS_INTERVAL_SECONDS = 2
local SAVE_DEBOUNCE_SECONDS = 1
local BOSS_CLONE_COST_MULTIPLIER = 3
local BOSS_CLONE_TIME_MULTIPLIER = 3

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

type ProgressionState = {
	xp: number,
	level: number,
	rebirth_count: number,
	prestige_marks: number,
	raise_successes: number,
	equipped_skills: { string },
}

type Profile = {
	version: number,
	revision: number,
	units: { UnitRecord },
	masters: { [string]: UnitRecord },
	machines: { MachineState },
	soul_essence: number,
	base_level: number,
	plot_upgrades: { [string]: number },
	codex_raises: { [string]: number },
	learned_skillbooks: { [string]: boolean },
	starter_secured_count: number,
	progression: ProgressionState,
	persistent: boolean,
	dirty: boolean,
	save_token: number,
}

local model_library_service = nil :: any
local unit_record_service = nil :: any
local plot_service = nil :: any
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

local function create_default_progression(): ProgressionState
	return {
		xp = 0,
		level = 1,
		rebirth_count = 0,
		prestige_marks = 0,
		raise_successes = 0,
		equipped_skills = {},
	}
end

--[[
	Creates level-one defaults for every Sanctum plot facility.

	Args:
		None.

	Returns:
		{ [string]: number }: Facility levels keyed by identifier.
]]
local function create_default_plot_upgrades(): { [string]: number }
	local upgrades: { [string]: number } = {}
	for _, facility_id in ipairs(
		PlotUpgradeConfig.get_facility_order()
	) do
		upgrades[facility_id] = 1
	end
	return upgrades
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
		plot_upgrades = create_default_plot_upgrades(),
		codex_raises = {},
		learned_skillbooks = {},
		starter_secured_count = 0,
		progression = create_default_progression(),
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

--[[
	Sanitizes persisted Sanctum facility levels.

	Legacy profiles only contain base_level. Their Plot level is raised to
	match the old Foundry level so existing progression is never lost.

	Args:
		raw (any): Persisted plot_upgrades table.
		legacy_base_level (number): Existing Soul Foundry level.

	Returns:
		{ [string]: number }: Valid facility levels.
]]
local function sanitize_plot_upgrades(
	raw: any,
	legacy_base_level: number
): { [string]: number }
	local upgrades = create_default_plot_upgrades()
	local max_level = PlotUpgradeConfig.get_max_level()

	if typeof(raw) == "table" then
		for _, facility_id in ipairs(
			PlotUpgradeConfig.get_facility_order()
		) do
			local value = raw[facility_id]
			if typeof(value) == "number" then
				upgrades[facility_id] = math.clamp(
					math.floor(value),
					1,
					max_level
				)
			end
		end
	end

	upgrades.SoulFoundry = math.max(
		upgrades.SoulFoundry,
		math.clamp(
			legacy_base_level,
			STARTING_BASE_LEVEL,
			MAX_BASE_LEVEL
		)
	)
	upgrades.Plot = math.max(
		upgrades.Plot,
		upgrades.SoulFoundry
	)

	for _, facility_id in ipairs(
		PlotUpgradeConfig.get_facility_order()
	) do
		if facility_id ~= "Plot" then
			upgrades[facility_id] = math.min(
				upgrades[facility_id],
				upgrades.Plot
			)
		end
	end

	return upgrades
end

local function sanitize_skill_list(raw: any): { string }
	local skills: { string } = {}
	if typeof(raw) ~= "table" then
		return skills
	end

	local seen: { [string]: boolean } = {}
	for _, skill_id in ipairs(raw) do
		if typeof(skill_id) == "string"
			and skill_id ~= ""
			and not seen[skill_id]
			and #skills < 3
		then
			seen[skill_id] = true
			table.insert(skills, skill_id)
		end
	end
	return skills
end

--[[
	Sanitizes per-template Codex Raise counts.

	Args:
		raw (any): Persisted Codex count table.

	Returns:
		{ [string]: number }: Valid non-negative counts.
]]
local function sanitize_codex_raises(
	raw: any
): { [string]: number }
	local result: { [string]: number } = {}
	if typeof(raw) ~= "table" then
		return result
	end

	for template_name, count in pairs(raw) do
		if typeof(template_name) == "string"
			and template_name ~= ""
			and typeof(count) == "number"
		then
			result[template_name] = math.max(
				0,
				math.floor(count)
			)
		end
	end
	return result
end

--[[
	Sanitizes learned battlefield skillbooks.

	Args:
		raw (any): Persisted skillbook collection.

	Returns:
		{ [string]: boolean }: Learned skill IDs.
]]
local function sanitize_skillbooks(
	raw: any
): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if typeof(raw) ~= "table" then
		return result
	end

	for key, value in pairs(raw) do
		local skill_id = nil
		if typeof(key) == "string" and value == true then
			skill_id = key
		elseif typeof(value) == "string" then
			skill_id = value
		end

		if skill_id then
			local definition = NecromancerSkills.get(skill_id)
			if definition and definition.requires_skillbook then
				result[skill_id] = true
			end
		end
	end
	return result
end

local function sanitize_progression(raw: any): ProgressionState
	local progression = create_default_progression()
	if typeof(raw) ~= "table" then
		return progression
	end

	progression.xp = sanitize_positive_int(raw.xp, 0)
	progression.level = math.max(
		1,
		sanitize_positive_int(raw.level, 1)
	)
	progression.rebirth_count = sanitize_positive_int(
		raw.rebirth_count,
		0
	)
	progression.prestige_marks = sanitize_positive_int(
		raw.prestige_marks,
		0
	)
	progression.raise_successes = sanitize_positive_int(
		raw.raise_successes,
		0
	)
	progression.equipped_skills = sanitize_skill_list(
		raw.equipped_skills
	)
	return progression
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
	local legacy_base_level = math.clamp(
		sanitize_positive_int(
			raw.base_level,
			STARTING_BASE_LEVEL
		),
		STARTING_BASE_LEVEL,
		MAX_BASE_LEVEL
	)
	profile.plot_upgrades = sanitize_plot_upgrades(
		raw.plot_upgrades,
		legacy_base_level
	)
	profile.base_level = profile.plot_upgrades.SoulFoundry
	profile.codex_raises = sanitize_codex_raises(
		raw.codex_raises
	)
	profile.learned_skillbooks = sanitize_skillbooks(
		raw.learned_skillbooks
	)
	profile.starter_secured_count = math.clamp(
		sanitize_positive_int(raw.starter_secured_count, 0),
		0,
		MAX_STARTER_UNITS_TO_SECURE
	)
	profile.progression = sanitize_progression(raw.progression)
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

--[[
	Returns one persisted plot facility level.

	Args:
		profile (Profile): Player Soul profile.
		facility_id (string): Plot facility identifier.

	Returns:
		number: Facility level from one to the configured maximum.
]]
local function get_plot_upgrade_level(
	profile: Profile,
	facility_id: string
): number
	local value = profile.plot_upgrades[facility_id]
	if typeof(value) ~= "number" then
		return 1
	end
	return math.clamp(
		math.floor(value),
		1,
		PlotUpgradeConfig.get_max_level()
	)
end

--[[
	Sets a plot facility level and keeps legacy Foundry state synchronized.

	Args:
		profile (Profile): Player Soul profile.
		facility_id (string): Plot facility identifier.
		level (number): New level.

	Returns:
		None.
]]
local function set_plot_upgrade_level(
	profile: Profile,
	facility_id: string,
	level: number
)
	local safe_level = math.clamp(
		math.floor(level),
		1,
		PlotUpgradeConfig.get_max_level()
	)
	profile.plot_upgrades[facility_id] = safe_level
	if facility_id == "SoulFoundry" then
		profile.base_level = safe_level
	end
end

--[[
	Counts safely stored Masters in the profile.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		number: Number of stored Masters.
]]
local function count_masters(profile: Profile): number
	local count = 0
	for _ in pairs(profile.masters) do
		count += 1
	end
	return count
end

--[[
	Copies the facility-level map for persistence or client snapshots.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		{ [string]: number }: Independent facility-level table.
]]
local function copy_plot_upgrades(
	profile: Profile
): { [string]: number }
	local result: { [string]: number } = {}
	for _, facility_id in ipairs(
		PlotUpgradeConfig.get_facility_order()
	) do
		result[facility_id] = get_plot_upgrade_level(
			profile,
			facility_id
		)
	end
	return result
end

--[[
	Copies learned battlefield skillbooks in stable order.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		{ string }: Learned skill IDs.
]]
local function copy_skillbooks(profile: Profile): { string }
	local result: { string } = {}
	for skill_id, learned in pairs(profile.learned_skillbooks) do
		if learned then
			table.insert(result, skill_id)
		end
	end
	table.sort(result)
	return result
end

--[[
	Builds client-safe Codex entries from Raise knowledge.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		{ any }: Sorted Codex entry payload.
]]
local function build_codex_entries(profile: Profile): { any }
	local entries = {}
	local codex_level = get_plot_upgrade_level(
		profile,
		"Codex"
	)

	for template_name, raise_count in pairs(profile.codex_raises) do
		local next_milestone =
			CodexKnowledgeConfig.get_next_milestone(
				raise_count,
				codex_level
			)
		table.insert(entries, {
			templateName = template_name,
			raiseCount = raise_count,
			defenseBonus =
				CodexKnowledgeConfig.get_defense_bonus(
					raise_count,
					codex_level
				),
			nextRaiseCount = next_milestone
				and next_milestone.raise_count
				or nil,
			nextDefenseBonus = next_milestone
				and next_milestone.defense_bonus
				or nil,
		})
	end

	table.sort(entries, function(left, right)
		if left.raiseCount == right.raiseCount then
			return left.templateName < right.templateName
		end
		return left.raiseCount > right.raiseCount
	end)
	return entries
end

--[[
	Returns unit templates the player genuinely owns.

	Stored units, Masters and assigned cloning templates all count as owned.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		{ string }: Sorted unique template names.
]]
local function owned_template_names(profile: Profile): { string }
	local seen: { [string]: boolean } = {}
	for _, record in ipairs(profile.units) do
		seen[record.template_name] = true
	end
	for _, record in pairs(profile.masters) do
		seen[record.template_name] = true
	end
	for _, machine in ipairs(profile.machines) do
		local record = machine.master_snapshot
		if record then
			seen[record.template_name] = true
		end
	end

	local result: { string } = {}
	for template_name in pairs(seen) do
		table.insert(result, template_name)
	end
	table.sort(result)
	return result
end

--[[
	Refreshes Codex defence on currently deployed owned units.

	Args:
		player (Player): Codex owner.
		template_name (string): Unit template whose bonus changed.
		old_bonus (number): Previously active bonus.
		new_bonus (number): Newly active bonus.

	Returns:
		None.
]]
local function refresh_live_codex_bonus(
	player: Player,
	template_name: string,
	new_bonus: number
)
	local armies = Workspace:FindFirstChild("PlayerArmies")
	if not armies then
		return
	end

	for _, instance in ipairs(armies:GetDescendants()) do
		if instance:IsA("Model")
			and instance:GetAttribute("ArmyOwnerUserId")
				== player.UserId
			and instance:GetAttribute("TemplateName")
				== template_name
		then
			local current = instance:GetAttribute("Defense")
			if typeof(current) ~= "number" then
				current = 0
			end
			local applied_bonus = instance:GetAttribute(
				"CodexDefenseBonus"
			)
			if typeof(applied_bonus) ~= "number" then
				applied_bonus = 0
			end
			instance:SetAttribute(
				"Defense",
				math.clamp(
					current - applied_bonus + new_bonus,
					0,
					0.9
				)
			)
			instance:SetAttribute(
				"CodexDefenseBonus",
				new_bonus
			)
		end
	end
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

local function is_boss_record(record: UnitRecord): boolean
	if not model_library_service
		or not model_library_service.get_unit_stats
	then
		return false
	end
	local stats = model_library_service.get_unit_stats(
		record.template_name
	)
	return stats ~= nil and stats.IsBoss == true
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
	if is_boss_record(record) then
		cost *= BOSS_CLONE_COST_MULTIPLIER
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

--[[
	Returns Soul Essence produced by the physical Soul Crucible.

	Args:
		profile (Profile): Player Soul profile.
		record (UnitRecord): Stored unit being sacrificed.

	Returns:
		number: Soul Essence reward.
]]
local function get_sacrifice_value(
	profile: Profile,
	record: UnitRecord
): number
	local level = get_plot_upgrade_level(
		profile,
		"SoulCrucible"
	)
	local multiplier =
		PlotUpgradeConfig.get_sacrifice_multiplier(level)
	return math.max(
		1,
		math.floor(
			get_dissolve_value(record) * multiplier + 0.5
		)
	)
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
	if is_boss_record(record) then
		base *= BOSS_CLONE_TIME_MULTIPLIER
	end
	local speed = 1
		+ ((machine.level - 1) * MACHINE_SPEED_PER_LEVEL)
	return math.max(20, math.floor(base / speed))
end

local function get_machine_upgrade_cost(
	profile: Profile,
	machine: MachineState
): number
	local base_cost = 60 * machine.level
	local forge_level = get_plot_upgrade_level(
		profile,
		"UpgradeForge"
	)
	return PlotUpgradeConfig.apply_forge_discount(
		base_cost,
		forge_level
	)
end

local function get_base_upgrade_cost(profile: Profile): number?
	return PlotUpgradeConfig.get_upgrade_cost(
		"SoulFoundry",
		get_plot_upgrade_level(profile, "SoulFoundry"),
		get_plot_upgrade_level(profile, "UpgradeForge")
	)
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

local function copy_progression(
	progression: ProgressionState
): ProgressionState
	return {
		xp = progression.xp,
		level = progression.level,
		rebirth_count = progression.rebirth_count,
		prestige_marks = progression.prestige_marks,
		raise_successes = progression.raise_successes,
		equipped_skills = sanitize_skill_list(
			progression.equipped_skills
		),
	}
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
		plot_upgrades = copy_plot_upgrades(profile),
		codex_raises = table.clone(profile.codex_raises),
		learned_skillbooks = copy_skillbooks(profile),
		starter_secured_count = profile.starter_secured_count,
		progression = copy_progression(profile.progression),
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
	local clone_progress = 0
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
			clone_progress = math.clamp(
				elapsed / math.max(1, clone_seconds),
				0,
				1
			)
		elseif machine.output_count > 0 then
			clone_progress = 1
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
		cloneProgress = clone_progress,
		paused = machine.paused,
		upgradeCost = if machine.level < MAX_MACHINE_LEVEL
			then get_machine_upgrade_cost(profile, machine)
			else nil,
	}
end

--[[
	Builds Soul Crucible options for stored non-Master units.

	Args:
		profile (Profile): Player Soul profile.

	Returns:
		{ any }: Sacrifice options with server-calculated rewards.
]]
local function build_sacrifice_options(
	profile: Profile
): { any }
	local options = {}
	for _, record in ipairs(profile.units) do
		if not record.deployed_master_id then
			table.insert(options, {
				recordId = record.record_id,
				templateName = record.template_name,
				sizeTier = record.size_tier,
				trait = record.trait,
				evolutionId = record.evolution_id,
				value = get_sacrifice_value(
					profile,
					record
				),
			})
		end
	end
	return options
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

	local plot_upgrades = copy_plot_upgrades(profile)
	local upgrade_options = {}
	local forge_level = get_plot_upgrade_level(
		profile,
		"UpgradeForge"
	)

	for _, facility_id in ipairs(
		PlotUpgradeConfig.get_facility_order()
	) do
		local level = plot_upgrades[facility_id]
		table.insert(upgrade_options, {
			id = facility_id,
			name = PlotUpgradeConfig.get_name(facility_id),
			level = level,
			effect = PlotUpgradeConfig.get_effect_text(
				facility_id,
				level
			),
			nextEffect = if level
					< PlotUpgradeConfig.get_max_level()
				then PlotUpgradeConfig.get_effect_text(
					facility_id,
					level + 1
				)
				else nil,
			upgradeCost =
				PlotUpgradeConfig.get_upgrade_cost(
					facility_id,
					level,
					forge_level
				),
			plotCap = plot_upgrades.Plot,
		})
	end

	return {
		kind = "SNAPSHOT",
		revision = profile.revision,
		persistent = profile.persistent,
		inSafeZone = is_player_in_safe_zone(player),
		soulEssence = profile.soul_essence,
		baseLevel = profile.base_level,
		baseUpgradeCost = get_base_upgrade_cost(profile),
		plotUpgrades = plot_upgrades,
		plotUpgradeOptions = upgrade_options,
		codexEntries = build_codex_entries(profile),
		learnedSkillbooks = copy_skillbooks(profile),
		sacrificeOptions = build_sacrifice_options(profile),
		ownedTemplates = owned_template_names(profile),
		progression = copy_progression(profile.progression),
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

	local plot_level = get_plot_upgrade_level(profile, "Plot")
	local formation_level = get_plot_upgrade_level(
		profile,
		"Formation"
	)
	local skill_level = get_plot_upgrade_level(
		profile,
		"SkillReliquary"
	)
	local codex_level = get_plot_upgrade_level(profile, "Codex")
	local crucible_level = get_plot_upgrade_level(
		profile,
		"SoulCrucible"
	)
	local master_level = get_plot_upgrade_level(
		profile,
		"MasterGallery"
	)
	local trophy_level = get_plot_upgrade_level(
		profile,
		"TrophyHall"
	)
	local forge_level = get_plot_upgrade_level(
		profile,
		"UpgradeForge"
	)

	player:SetAttribute("PlotLevel", plot_level)
	player:SetAttribute(
		"SoulFoundryLevel",
		get_plot_upgrade_level(profile, "SoulFoundry")
	)
	player:SetAttribute("FormationLevel", formation_level)
	player:SetAttribute("SkillReliquaryLevel", skill_level)
	player:SetAttribute("CodexLevel", codex_level)
	player:SetAttribute("SoulCrucibleLevel", crucible_level)
	player:SetAttribute("MasterGalleryLevel", master_level)
	player:SetAttribute("TrophyHallLevel", trophy_level)
	player:SetAttribute("UpgradeForgeLevel", forge_level)
	player:SetAttribute(
		"ArmyCommandRange",
		PlotUpgradeConfig.get_command_range(formation_level)
	)
	player:SetAttribute(
		"SkillCooldownMultiplier",
		PlotUpgradeConfig.get_skill_cooldown_multiplier(
			skill_level
		)
	)
	local sacrifice_multiplier =
		PlotUpgradeConfig.get_sacrifice_multiplier(
			crucible_level
		)
	player:SetAttribute(
		"SoulSacrificeMultiplier",
		sacrifice_multiplier
	)
	player:SetAttribute(
		"DissolveEssenceMultiplier",
		sacrifice_multiplier
	)
	player:SetAttribute(
		"MasterStorageCapacity",
		PlotUpgradeConfig.get_master_capacity(master_level)
	)
	player:SetAttribute(
		"BossTrophySlots",
		PlotUpgradeConfig.get_trophy_slots(trophy_level)
	)
	player:SetAttribute(
		"PlotUpgradeDiscount",
		PlotUpgradeConfig.get_forge_discount(forge_level)
	)
end

local function send_snapshot(player: Player)
	local profile = get_profile(player)
	if not profile then
		return
	end

	update_player_attributes(player, profile)
	local snapshot = build_client_snapshot(player, profile)
	if plot_service
		and plot_service.refresh_collection_visuals
	then
		plot_service.refresh_collection_visuals(
			player,
			snapshot
		)
	end
	Remotes.soul_collection():FireClient(
		player,
		snapshot
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

	local gallery_level = get_plot_upgrade_level(
		profile,
		"MasterGallery"
	)
	local capacity = PlotUpgradeConfig.get_master_capacity(
		gallery_level
	)
	if count_masters(profile) >= capacity then
		return false, (
			"Master Gallery is full (%d/%d). Upgrade it first."
		):format(count_masters(profile), capacity)
	end

	record = remove_unit_at(profile, index)
	record.acquisition_kind = "Master"
	profile.masters[record.record_id] = record
	mark_changed(player, profile, true)
	return true, "Soul Imprint registered as a Master."
end

local function sacrifice_unit(
	player: Player,
	record_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end
	if not plot_service
		or not plot_service.is_player_near_station
		or not plot_service.is_player_near_station(
			player,
			"SoulCrucible",
			22
		)
	then
		return false, "Use your Soul Crucible to sacrifice units."
	end

	local index = find_unit_index(profile, record_id)
	if not index then
		return false, "Unit is not in your Soul Vault."
	end

	local record = profile.units[index]
	if record.deployed_master_id then
		return false, "An at-risk Master cannot be sacrificed."
	end

	record = remove_unit_at(profile, index)
	local gained = get_sacrifice_value(profile, record)
	profile.soul_essence += gained
	process_profile(profile, now_seconds())
	mark_changed(player, profile, true)
	return true, ("Sacrificed for %d Soul Essence."):format(gained)
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

	local cost = get_machine_upgrade_cost(profile, machine)
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

--[[
	Upgrades one physical Sanctum facility.

	Every facility except the Plot itself is capped by Plot level. Soul
	Essence is the single upgrade currency, and the Upgrade Forge discounts
	all other facility purchases.

	Args:
		player (Player): Player buying the upgrade.
		facility_id (string): Facility identifier.

	Returns:
		boolean, string: Success and user-facing result.
]]
local function upgrade_facility(
	player: Player,
	facility_id: string
): (boolean, string)
	local profile, err = require_safe_zone(player)
	if not profile then
		return false, err or "Profile unavailable."
	end
	if not PlotUpgradeConfig.is_valid_facility(facility_id) then
		return false, "Unknown Sanctum facility."
	end

	local current_level = get_plot_upgrade_level(
		profile,
		facility_id
	)
	local max_level = PlotUpgradeConfig.get_max_level()
	if current_level >= max_level then
		return false, (
			"%s is already fully upgraded."
		):format(PlotUpgradeConfig.get_name(facility_id))
	end

	local plot_level = get_plot_upgrade_level(profile, "Plot")
	if facility_id ~= "Plot"
		and current_level >= plot_level
	then
		return false, (
			"Upgrade your Sanctum Plot to level %d first."
		):format(current_level + 1)
	end

	local forge_level = get_plot_upgrade_level(
		profile,
		"UpgradeForge"
	)
	local cost = PlotUpgradeConfig.get_upgrade_cost(
		facility_id,
		current_level,
		forge_level
	)
	if not cost then
		return false, "That facility cannot be upgraded."
	end
	if profile.soul_essence < cost then
		return false, ("Need %d Soul Essence."):format(cost)
	end

	profile.soul_essence -= cost
	local new_level = current_level + 1
	set_plot_upgrade_level(
		profile,
		facility_id,
		new_level
	)

	if facility_id == "SoulFoundry" then
		ensure_machine_count(profile)
	end

	mark_changed(player, profile, true)
	return true, ("%s upgraded to level %d."):format(
		PlotUpgradeConfig.get_name(facility_id),
		new_level
	)
end

local function upgrade_base(
	player: Player
): (boolean, string)
	return upgrade_facility(player, "SoulFoundry")
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
	elseif action == "SACRIFICE_UNIT"
		or action == "DISSOLVE_UNIT"
	then
		ok, message = sacrifice_unit(
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
	elseif action == "UPGRADE_FACILITY" then
		ok, message = upgrade_facility(
			player,
			tostring(payload.facilityId or "")
		)
	elseif action == "UPGRADE_BASE" then
		ok, message = upgrade_base(player)
	elseif RunService:IsStudio()
		and action == "DEBUG_RESET_PROFILE"
	then
		local profile = create_default_profile()
		profiles_by_user_id[player.UserId] = profile
		profile.dirty = true
		update_player_attributes(player, profile)
		send_snapshot(player)
		ok = true
		message = "Studio Soul profile reset."
	elseif RunService:IsStudio()
		and action == "DEBUG_ADD_ESSENCE"
	then
		local profile = get_profile(player)
		local amount = tonumber(payload.amount) or 0
		if profile then
			profile.soul_essence = math.max(
				0,
				profile.soul_essence + math.floor(amount)
			)
			mark_changed(player, profile, true)
			ok = true
			message = "Studio Soul Essence adjusted."
		else
			message = "Profile unavailable."
		end
	elseif RunService:IsStudio()
		and action == "DEBUG_RELOAD_PROFILE"
	then
		if save_profile_now(player) then
			profiles_by_user_id[player.UserId] = nil
			load_profile(player)
			ok = true
			message = "Studio Soul profile reloaded."
		else
			message = "Studio profile save failed."
		end
	end

	send_result(player, ok, message)
end

function SoulCollectionService.init(
	model_library_ref: any,
	unit_record_ref: any,
	plot_service_ref: any?
)
	model_library_service = model_library_ref
	unit_record_service = unit_record_ref
	plot_service = plot_service_ref
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

function SoulCollectionService.get_progression_state(
	player: Player
): ProgressionState?
	local profile = get_profile(player)
	if not profile then
		return nil
	end
	return copy_progression(profile.progression)
end

function SoulCollectionService.commit_progression_state(
	player: Player,
	raw: any
): boolean
	local profile = get_profile(player)
	if not profile then
		return false
	end
	profile.progression = sanitize_progression(raw)
	mark_changed(player, profile, false)
	return true
end

function SoulCollectionService.is_player_in_safe_zone(
	player: Player
): boolean
	return is_player_in_safe_zone(player)
end

function SoulCollectionService.imprint_master(
	player: Player,
	record_id: string
): (boolean, string)
	return imprint_master(player, record_id)
end

function SoulCollectionService.sacrifice_unit(
	player: Player,
	record_id: string
): (boolean, string)
	return sacrifice_unit(player, record_id)
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

function SoulCollectionService.upgrade_facility(
	player: Player,
	facility_id: string
): (boolean, string)
	return upgrade_facility(player, facility_id)
end

function SoulCollectionService.get_plot_upgrade_level(
	player: Player,
	facility_id: string
): number
	local profile = get_profile(player)
	if not profile then
		return 1
	end
	return get_plot_upgrade_level(profile, facility_id)
end

function SoulCollectionService.get_plot_upgrades(
	player: Player
): { [string]: number }
	local profile = get_profile(player)
	if not profile then
		return create_default_plot_upgrades()
	end
	return copy_plot_upgrades(profile)
end

--[[
	Returns unit templates genuinely owned by a player.

	Args:
		player (Player): Player whose collection is inspected.

	Returns:
		{ string }: Sorted unique template names.
]]
function SoulCollectionService.get_owned_template_names(
	player: Player
): { string }
	local profile = get_profile(player)
	if not profile then
		return {}
	end
	return owned_template_names(profile)
end

--[[
	Awards Soul Essence from battlefield pickups or other trusted systems.

	Args:
		player (Player): Player receiving Essence.
		amount (number): Positive Essence amount.

	Returns:
		number: New Soul Essence balance.
]]
function SoulCollectionService.award_essence(
	player: Player,
	amount: number
): number
	local profile = get_profile(player)
	if not profile or amount <= 0 then
		return profile and profile.soul_essence or 0
	end

	profile.soul_essence += math.max(1, math.floor(amount))
	mark_changed(player, profile, true)
	return profile.soul_essence
end

--[[
	Returns whether a battlefield skillbook has been learned.

	Args:
		player (Player): Player to inspect.
		skill_id (string): Skill identifier.

	Returns:
		boolean: True when the skillbook is permanently learned.
]]
function SoulCollectionService.has_skillbook(
	player: Player,
	skill_id: string
): boolean
	local profile = get_profile(player)
	return profile ~= nil
		and profile.learned_skillbooks[skill_id] == true
end

--[[
	Returns advanced skillbooks the player has not yet learned.

	Args:
		player (Player): Player to inspect.

	Returns:
		{ string }: Missing skill IDs.
]]
function SoulCollectionService.get_missing_skillbook_ids(
	player: Player
): { string }
	local profile = get_profile(player)
	if not profile then
		return {}
	end

	local result: { string } = {}
	for _, definition in ipairs(
		NecromancerSkills.get_skillbook_skills()
	) do
		if not profile.learned_skillbooks[definition.id] then
			table.insert(result, definition.id)
		end
	end
	return result
end

--[[
	Permanently learns one battlefield skillbook.

	Args:
		player (Player): Player learning the book.
		skill_id (string): Skill identifier.

	Returns:
		boolean, string: Success and user-facing result.
]]
function SoulCollectionService.learn_skillbook(
	player: Player,
	skill_id: string
): (boolean, string)
	local profile = get_profile(player)
	if not profile then
		return false, "Soul profile is still loading."
	end

	local definition = NecromancerSkills.get(skill_id)
	if not definition or not definition.requires_skillbook then
		return false, "That is not a learnable battlefield skillbook."
	end
	if profile.learned_skillbooks[skill_id] then
		return false, ("%s is already learned."):format(
			definition.name
		)
	end

	profile.learned_skillbooks[skill_id] = true
	mark_changed(player, profile, true)
	return true, ("Learned skillbook: %s."):format(
		definition.name
	)
end

--[[
	Records Codex knowledge from a successful Raise.

	Args:
		player (Player): Necromancer gaining knowledge.
		template_name (string): Raised unit template.

	Returns:
		number, number: New Raise count and active defence bonus.
]]
function SoulCollectionService.record_codex_raise(
	player: Player,
	template_name: string
): (number, number)
	local profile = get_profile(player)
	if not profile or template_name == "" then
		return 0, 0
	end

	local old_count = profile.codex_raises[template_name] or 0
	local codex_level = get_plot_upgrade_level(
		profile,
		"Codex"
	)
	local new_count = old_count + 1
	local new_bonus =
		CodexKnowledgeConfig.get_defense_bonus(
			new_count,
			codex_level
		)

	profile.codex_raises[template_name] = new_count
	refresh_live_codex_bonus(
		player,
		template_name,
		new_bonus
	)
	mark_changed(player, profile, true)
	return new_count, new_bonus
end

--[[
	Returns the Codex defence bonus for a unit template.

	Args:
		player (Player): Codex owner.
		template_name (string): Unit template.

	Returns:
		number: Additive defence bonus.
]]
function SoulCollectionService.get_codex_defense_bonus(
	player: Player,
	template_name: string
): number
	local profile = get_profile(player)
	if not profile then
		return 0
	end
	local count = profile.codex_raises[template_name] or 0
	local codex_level = get_plot_upgrade_level(
		profile,
		"Codex"
	)
	return CodexKnowledgeConfig.get_defense_bonus(
		count,
		codex_level
	)
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
				if profile then
					if process_profile(profile, now) then
						mark_changed(player, profile, false)
					end
					send_snapshot(player)
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
