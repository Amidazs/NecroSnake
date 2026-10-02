--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PLAYER_BOUNDS_MARGIN = 12
local PLAYER_RAYCAST_START_HEIGHT = 600
local PLAYER_RAYCAST_DISTANCE = 2000
local PLAYER_SURFACE_OFFSET = 6

local FALLBACK_MIN_X = -512
local FALLBACK_MAX_X = 512
local FALLBACK_MIN_Z = -512
local FALLBACK_MAX_Z = 512

local ArmyService = {}

local model_library_service = nil :: any
local formation_profile_service = nil :: any
local unit_record_service = nil :: any
local did_init = false

local PLAYER_ARMIES_FOLDER_NAME = "PlayerArmies"
local DEFAULT_STARTER_TEMPLATE = "Skeleton"
local DEFAULT_STARTER_COUNT = 3

-- Attributes written by ModelLibraryService on spawned models.
local ATTR_TEMPLATE_NAME = "TemplateName"
local ATTR_SIZE_TIER = "SizeTier"
local ATTR_TRAIT = "Trait"

-- Raise rules
local BASE_RAISE_CHANCE = 0.95
local MIN_RAISE_CHANCE = 0.05
local MAX_RAISE_CHANCE = 1

-- These weights should match ModelLibraryService SIZE_TIERS and TRAIT_MODS
-- so rarity behaves consistently with your spawn rolls.
local SIZE_WEIGHTS: { [string]: number } = {
	Normal = 0.72,
	Small = 0.14,
	Giant = 0.14,
}

local TRAIT_WEIGHTS: { [string]: number } = {
	None = 0.78,
	Tough = 0.12,
	Frenzied = 0.10,
}

-- Spawn spread (helps prevent stacking)
local STARTER_RING_RADIUS = 10
local STARTER_RING_JITTER = 2
local SUMMON_RING_RADIUS = 10
local SUMMON_RING_JITTER = 3
local GOLDEN_ANGLE = math.rad(137.5077640500378)

type SpawnOverrides = {
	force_size_tier: string?,
	force_trait: string?,
}

type ArmyUnit = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
}

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

local player_armies_folder: Folder? = nil

local armies_by_user_id: { [number]: { ArmyUnit } } = {}
local spawn_index_by_user_id: { [number]: number } = {}

local function clamp01(value: number): number
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function clamp(num: number, min_v: number, max_v: number): number
	if num < min_v then
		return min_v
	end
	if num > max_v then
		return max_v
	end
	return num
end

local function get_terrain_bounds_xz(): (number, number, number, number)
	local bounds_part = Workspace:FindFirstChild("SpawnBounds", true)
	if bounds_part and bounds_part:IsA("BasePart") then
		local size = bounds_part.Size
		local pos = bounds_part.Position
		local half_x = size.X * 0.5
		local half_z = size.Z * 0.5

		return pos.X - half_x, pos.X + half_x, pos.Z - half_z, pos.Z + half_z
	end

	return FALLBACK_MIN_X, FALLBACK_MAX_X, FALLBACK_MIN_Z, FALLBACK_MAX_Z
end

local function is_near_foliage(pos: Vector3, radius: number): boolean
	local biomes = Workspace:FindFirstChild("Biomes")
	if not biomes then
		return false
	end

	local foliage = biomes:FindFirstChild("Foliage")
	if not foliage then
		return false
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.FilterDescendantsInstances = { foliage }

	local parts = Workspace:GetPartBoundsInRadius(pos, radius, params)
	return #parts > 0
end

local function pick_random_ground_position(): Vector3
	local min_x, max_x, min_z, max_z = get_terrain_bounds_xz()

	for _ = 1, 60 do
		local x = min_x + math.random() * (max_x - min_x)
		local z = min_z + math.random() * (max_z - min_z)

		local origin = Vector3.new(x, PLAYER_RAYCAST_START_HEIGHT, z)
		local direction = Vector3.new(0, -PLAYER_RAYCAST_DISTANCE, 0)

		local biomes = Workspace:FindFirstChild("Biomes")

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { biomes }
		params.IgnoreWater = true

		local result = Workspace:Raycast(origin, direction, params)
		if result then
			local hit_terrain = result.Instance:IsA("Terrain")
			local hit_floor = result.Instance:IsA("BasePart") and result.Instance.CanCollide

			if (hit_terrain or hit_floor)
				and (not hit_terrain or result.Material ~= Enum.Material.Water) then
				local candidate = Vector3.new(
					x,
					result.Position.Y + PLAYER_SURFACE_OFFSET,
					z
				)

				if not is_near_foliage(candidate, 10) then
					return candidate
				end
			end
		end
	end

	-- Fallback if we fail too many attempts
	return Vector3.new(0, 10, 0)
end

local function ensure_folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensure_player_armies_folder(): Folder
	if player_armies_folder and player_armies_folder.Parent ~= nil then
		return player_armies_folder
	end

	player_armies_folder = ensure_folder(Workspace, PLAYER_ARMIES_FOLDER_NAME)
	return player_armies_folder
end

local function get_or_create_player_army_folder(player: Player): Folder
	local root = ensure_player_armies_folder()
	local name = ("%d_%s"):format(player.UserId, player.Name)
	return ensure_folder(root, name)
end

local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function get_root(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local p = model.PrimaryPart
	if p and p:IsA("BasePart") then
		return p
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end

	return nil
end

local function remove_unit_from_army(player: Player, unit_model: Model)
	local list = armies_by_user_id[player.UserId] or {}
	local new_list: { ArmyUnit } = {}

	for _, u in ipairs(list) do
		if u.model ~= unit_model then
			table.insert(new_list, u)
		end
	end
	armies_by_user_id[player.UserId] = new_list
	if ArmyService.refresh_command_capacity then
		ArmyService.refresh_command_capacity(player)
	end
end

local function hook_unit_death_cleanup(
	player: Player,
	unit_model: Model,
	humanoid: Humanoid
)
	humanoid.Died:Connect(function()
		remove_unit_from_army(player, unit_model)

	end)
end

local function compute_spread_offset(
	index: number,
	ring_radius: number,
	jitter: number
): Vector3
	-- Golden-angle spiral placement spreads units without clustering.
	local angle = GOLDEN_ANGLE * index
	local radius = ring_radius + (math.sqrt(index) * 1.5)

	local x = math.cos(angle) * radius
	local z = math.sin(angle) * radius

	local jx = (math.random() * 2 - 1) * jitter
	local jz = (math.random() * 2 - 1) * jitter

	return Vector3.new(x + jx, 0, z + jz)
end

local function spawn_one_unit(
	player: Player,
	template_name: string,
	folder: Folder,
	origin_cframe: CFrame,
	spread_index: number,
	ring_radius: number,
	jitter: number,
	overrides: SpawnOverrides?
): Model?
	assert(model_library_service, "ArmyService missing ModelLibraryService")

	local offset = compute_spread_offset(spread_index, ring_radius, jitter)
	local cframe = origin_cframe * CFrame.new(offset)

	local model: Model? = nil
	if model_library_service.spawn_from_template then
		model = model_library_service.spawn_from_template(
			template_name,
			cframe,
			folder,
			overrides
		)
	end

	if not model then
		return nil
	end

	model.Parent = folder

	-- Mark as player army so AI can treat speed + targeting differently.
	model:SetAttribute("IsPlayerArmy", true)
	model:SetAttribute("ArmyOwnerUserId", player.UserId)

	local cohort = nil
	local template_identity = model:GetAttribute(ATTR_TEMPLATE_NAME)
	if formation_profile_service
		and formation_profile_service.get_cohort_for_template
		and typeof(template_identity) == "string"
	then
		cohort = formation_profile_service.get_cohort_for_template(
			player,
			template_identity
		)
	end
	if typeof(cohort) ~= "string" or cohort == "" then
		cohort = model:GetAttribute("DefaultCohort")
	end
	if typeof(cohort) ~= "string" or cohort == "" then
		cohort = "SecondLine"
	end
	model:SetAttribute("Cohort", cohort)

	spawn_index_by_user_id[player.UserId] = (spawn_index_by_user_id[player.UserId] or 0)
		+ 1
	model:SetAttribute("ArmyUnitId", spawn_index_by_user_id[player.UserId])

	if model_library_service.set_units_collision then
		model_library_service.set_units_collision(model)
	end

	local humanoid = get_humanoid(model)
	local root = get_root(model)

	if not (humanoid and root) then
		model:Destroy()
		return nil
	end

	-- The owning client simulates its army physics. Damage, targeting,
	-- leashing, command validation and corrective teleports remain server-side.
	-- This distributes the expensive humanoid assemblies across clients instead
	-- of forcing one server to simulate every player's full army.
	local ownership_ok = pcall(function()
		root:SetNetworkOwner(player)
	end)
	if not ownership_ok then
		pcall(function()
			root:SetNetworkOwnershipAuto()
		end)
	end

	humanoid.AutoJumpEnabled = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	local unit: ArmyUnit = {
		model = model,
		humanoid = humanoid,
		root = root,
	}

	armies_by_user_id[player.UserId] = armies_by_user_id[player.UserId] or {}
	table.insert(armies_by_user_id[player.UserId], unit)
	ArmyService.refresh_command_capacity(player)

	hook_unit_death_cleanup(player, model, humanoid)

	return model
end

local function summon_starter_units(player: Player)
	local overrides: SpawnOverrides = {
		force_size_tier = "Normal",
		force_trait = "None",
	}

	local spawned = ArmyService.summon_units(
		player,
		DEFAULT_STARTER_TEMPLATE,
		DEFAULT_STARTER_COUNT,
		overrides
	)

	for _, model in ipairs(spawned) do
		model:SetAttribute("AcquisitionKind", "StarterLoan")
	end
end

local function compute_rarity_scaled_raise_chance(
	size_tier: string?,
	trait: string?
): number
	local size_name = size_tier or "Normal"
	local trait_name = trait or "None"

	local size_weight = SIZE_WEIGHTS[size_name] or SIZE_WEIGHTS.Normal or 1
	local trait_weight = TRAIT_WEIGHTS[trait_name] or TRAIT_WEIGHTS.None or 1

	local normal_weight = SIZE_WEIGHTS.Normal or 1
	local none_weight = TRAIT_WEIGHTS.None or 1

	local rarity_factor = (size_weight * trait_weight) / (normal_weight * none_weight)

	local chance = BASE_RAISE_CHANCE * rarity_factor
	return clamp(chance, MIN_RAISE_CHANCE, MAX_RAISE_CHANCE)
end

local function read_string_attr(model: Model, attr_name: string): string?
	local value = model:GetAttribute(attr_name)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local DEFAULT_COMMAND_CAPACITY = 5
local MAX_RAISE_CHANCE_FROM_PROGRESSION = 0.95

local function get_unit_command_cost(template_name: string, size_tier: string?): number
	local stats = nil
	if model_library_service and model_library_service.get_unit_stats then
		stats = model_library_service.get_unit_stats(template_name)
	end

	local cost = 1
	if stats and type(stats.CommandCost) == "number" then
		cost = math.max(1, math.floor(stats.CommandCost))
	end

	if size_tier == "Giant" then
		cost = math.max(cost + 1, math.ceil(cost * 1.5))
	end

	return cost
end

local function get_model_command_cost(model: Model): number
	local attr = model:GetAttribute("CommandCost")
	if typeof(attr) == "number" then
		return math.max(1, math.floor(attr))
	end

	local template_name = read_string_attr(model, ATTR_TEMPLATE_NAME) or model.Name
	local size_tier = read_string_attr(model, ATTR_SIZE_TIER)
	return get_unit_command_cost(template_name, size_tier)
end

local function initialize_player_progression(player: Player)
	if typeof(player:GetAttribute("NecromancerLevel")) ~= "number" then
		player:SetAttribute("NecromancerLevel", 1)
	end
	if typeof(player:GetAttribute("CommandCapacity")) ~= "number" then
		player:SetAttribute("CommandCapacity", DEFAULT_COMMAND_CAPACITY)
	end
	if typeof(player:GetAttribute("RaiseChanceBonus")) ~= "number" then
		player:SetAttribute("RaiseChanceBonus", 0)
	end
	if typeof(player:GetAttribute("UsedCommandCapacity")) ~= "number" then
		player:SetAttribute("UsedCommandCapacity", 0)
	end
end

function ArmyService.get_command_capacity(player: Player): number
	local value = player:GetAttribute("CommandCapacity")
	if typeof(value) == "number" then
		return math.max(0, math.floor(value))
	end
	return DEFAULT_COMMAND_CAPACITY
end

function ArmyService.get_used_command_capacity(player: Player): number
	local total = 0
	for _, unit in ipairs(armies_by_user_id[player.UserId] or {}) do
		if unit.model and unit.model.Parent ~= nil then
			total += get_model_command_cost(unit.model)
		end
	end
	return total
end

function ArmyService.get_model_command_cost(model: Model): number
	return get_model_command_cost(model)
end

function ArmyService.refresh_command_capacity(player: Player)
	player:SetAttribute(
		"UsedCommandCapacity",
		ArmyService.get_used_command_capacity(player)
	)
end

function ArmyService.can_add_model(player: Player, model: Model): (boolean, number, number, number)
	local cost = get_model_command_cost(model)
	local used = ArmyService.get_used_command_capacity(player)
	local maximum = ArmyService.get_command_capacity(player)
	return used + cost <= maximum, cost, used, maximum
end

function ArmyService.banish_unit(player: Player, model: Model): (boolean, string)
	if model:GetAttribute("ArmyOwnerUserId") ~= player.UserId then
		return false, "That unit is not part of your army."
	end
	if model.Parent == nil then
		return false, "That unit no longer exists."
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or model:GetAttribute("IsNecroCorpse") == true then
		return false, "Dead units cannot be Banished."
	end

	remove_unit_from_army(player, model)
	model:SetAttribute("WasBanished", true)
	model:Destroy()
	return true, "Unit banished. Command Capacity freed."
end

function ArmyService.init(
	model_library,
	formation_profile_service_ref: any?,
	unit_record_service_ref: any?
)
	model_library_service = model_library
	formation_profile_service = formation_profile_service_ref
	unit_record_service = unit_record_service_ref
	did_init = true

	Players.PlayerAdded:Connect(function(player)
		initialize_player_progression(player)
		player.CharacterAdded:Connect(function(character)
			if model_library_service.set_leaders_collision then
				model_library_service.set_leaders_collision(character)
			end

			task.defer(function()
				task.wait(0.1)

				if player.Character then
					local pos = pick_random_ground_position()
					player.Character:PivotTo(CFrame.new(pos))
				end

				summon_starter_units(player)
			end)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		initialize_player_progression(player)
		if player.Character
			and model_library_service.set_leaders_collision
		then
			model_library_service.set_leaders_collision(player.Character)
		end
	end
end

function ArmyService.get_army_units(player: Player): { Model }
	local list = armies_by_user_id[player.UserId] or {}
	local models = {}

	for _, u in ipairs(list) do
		if u.model and u.model.Parent ~= nil then
			table.insert(models, u.model)
		end
	end

	return models
end

function ArmyService.kill_army_for_loss(
	player: Player,
	killer_user_id: number,
	source_kind: string,
	reason: string
): number
	local list = armies_by_user_id[player.UserId] or {}
	local models: { Model } = {}

	for _, unit in ipairs(list) do
		if unit.model and unit.model.Parent ~= nil then
			table.insert(models, unit.model)
		end
	end

	-- Remove the live ownership list first. Died callbacks may fire
	-- synchronously while the models are being converted into corpses.
	armies_by_user_id[player.UserId] = {}
	ArmyService.refresh_command_capacity(player)

	for _, model in ipairs(models) do
		model:SetAttribute("LastDamageSourceKind", source_kind)
		model:SetAttribute("LastHitOwnerUserId", killer_user_id)
		model:SetAttribute("PvPLossReason", reason)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	return #models
end

function ArmyService.clear_army(player: Player)
	local folder = get_or_create_player_army_folder(player)

	local list = armies_by_user_id[player.UserId] or {}
	for _, u in ipairs(list) do
		if u.model and u.model.Parent ~= nil then
			u.model:Destroy()
		end
	end

	armies_by_user_id[player.UserId] = {}
	ArmyService.refresh_command_capacity(player)

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

function ArmyService.summon_unit_at(
	player: Player,
	template_name: string,
	cframe: CFrame,
	overrides: SpawnOverrides?
): Model?
	assert(did_init, "ArmyService not initialized")
	assert(model_library_service, "ArmyService missing ModelLibraryService")

	local size_tier = overrides and overrides.force_size_tier or nil
	local estimated_cost = get_unit_command_cost(template_name, size_tier)
	local used = ArmyService.get_used_command_capacity(player)
	if used + estimated_cost > ArmyService.get_command_capacity(player) then
		return nil
	end

	local folder = get_or_create_player_army_folder(player)
	return spawn_one_unit(
		player,
		template_name,
		folder,
		cframe,
		0,
		0,
		0,
		overrides
	)
end

function ArmyService.summon_units(
	player: Player,
	template_name: string,
	count: number,
	overrides: SpawnOverrides?
): { Model }
	print("ArmyService.summon_units:", player.Name, template_name, count)

	assert(did_init, "ArmyService not initialized")
	assert(model_library_service, "ArmyService missing ModelLibraryService")

	local character = player.Character
	if not character then
		return {}
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return {}
	end

	local folder = get_or_create_player_army_folder(player)
	local spawned: { Model } = {}

	armies_by_user_id[player.UserId] = armies_by_user_id[player.UserId] or {}

	local start_index = (spawn_index_by_user_id[player.UserId] or 0) + 1
	for i = 0, count - 1 do
		local size_tier = overrides and overrides.force_size_tier or nil
		local estimated_cost = get_unit_command_cost(template_name, size_tier)
		local used = ArmyService.get_used_command_capacity(player)
		if used + estimated_cost > ArmyService.get_command_capacity(player) then
			break
		end

		local model = spawn_one_unit(
			player,
			template_name,
			folder,
			hrp.CFrame,
			start_index + i,
			(template_name == DEFAULT_STARTER_TEMPLATE and overrides ~= nil)
					and STARTER_RING_RADIUS
				or SUMMON_RING_RADIUS,
			(template_name == DEFAULT_STARTER_TEMPLATE and overrides ~= nil)
					and STARTER_RING_JITTER
				or SUMMON_RING_JITTER,
			overrides
		)

		if model then
			table.insert(spawned, model)
		end
	end

	return spawned
end

-- NEW: Convert the player's current spawned army into a "backpack snapshot"
-- and remove the units from the world (so nothing can fight/follow into SafeZone).
function ArmyService.snapshot_and_clear_army(
	player: Player
): { UnitSnapshot }
	local list = armies_by_user_id[player.UserId] or {}
	local snapshot: { UnitSnapshot } = {}

	for _, unit in ipairs(list) do
		local model = unit.model
		if model and model.Parent ~= nil then
			if unit_record_service
				and unit_record_service.from_model
			then
				table.insert(
					snapshot,
					unit_record_service.from_model(model)
				)
			else
				table.insert(snapshot, {
					template_name = read_string_attr(
						model,
						ATTR_TEMPLATE_NAME
					) or model.Name,
					size_tier = read_string_attr(
						model,
						ATTR_SIZE_TIER
					),
					trait = read_string_attr(
						model,
						ATTR_TRAIT
					),
				})
			end
		end
	end

	ArmyService.clear_army(player)
	return snapshot
end

-- NEW: Spawn units back into the world from a backpack snapshot.
-- This spawns near the player's HumanoidRootPart (same as summon_units).
function ArmyService.spawn_from_snapshot(
	player: Player,
	snapshot: { UnitSnapshot }
): { Model }
	local spawned: { Model } = {}

	for _, s in ipairs(snapshot) do
		local overrides: SpawnOverrides? = nil
		if s.size_tier ~= nil or s.trait ~= nil then
			overrides = {
				force_size_tier = s.size_tier,
				force_trait = s.trait,
			}
		end

		local models = ArmyService.summon_units(
			player,
			s.template_name,
			1,
			overrides
		)
		for _, model in ipairs(models) do
			if unit_record_service
				and unit_record_service.apply_to_model
			then
				unit_record_service.apply_to_model(model, s)
			end
			table.insert(spawned, model)
		end
	end

	return spawned
end

function ArmyService.get_raise_chance(player: Player, dead_model: Model): number
	local template_name = read_string_attr(dead_model, ATTR_TEMPLATE_NAME)
		or DEFAULT_STARTER_TEMPLATE
	local size_name = read_string_attr(dead_model, ATTR_SIZE_TIER) or "Normal"
	local trait_name = read_string_attr(dead_model, ATTR_TRAIT) or "None"

	local base_chance = compute_rarity_scaled_raise_chance(size_name, trait_name)
	if model_library_service and model_library_service.get_unit_stats then
		local stats = model_library_service.get_unit_stats(template_name)
		if stats and type(stats.RaiseChance) == "number" then
			base_chance = clamp01(stats.RaiseChance)
		end
	end

	local bonus = player:GetAttribute("RaiseChanceBonus")
	if typeof(bonus) ~= "number" then
		bonus = 0
	end

	return clamp(
		base_chance + bonus,
		MIN_RAISE_CHANCE,
		MAX_RAISE_CHANCE_FROM_PROGRESSION
	)
end

function ArmyService.try_raise_dead(
	player: Player,
	dead_model: Model
): (boolean, string, number, number)
	if not model_library_service or dead_model.Parent == nil then
		return false, "INVALID", 0, 0
	end

	local humanoid = dead_model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health > 0 then
		return false, "INVALID", 0, 0
	end

	local can_add, cost, used, maximum = ArmyService.can_add_model(player, dead_model)
	local chance = ArmyService.get_raise_chance(player, dead_model)
	if not can_add then
		return false, "FULL", chance, cost
	end

	local roll = Random.new():NextNumber()
	if roll > chance then
		print("[RAISE FAILED]", dead_model.Name, roll, chance)
		return false, "FAILED", chance, cost
	end

	local template_name = read_string_attr(dead_model, ATTR_TEMPLATE_NAME)
		or DEFAULT_STARTER_TEMPLATE
	local size_attr = read_string_attr(dead_model, ATTR_SIZE_TIER)
	local trait_attr = read_string_attr(dead_model, ATTR_TRAIT)

	local overrides: SpawnOverrides? = nil
	if size_attr or trait_attr then
		overrides = {
			force_size_tier = size_attr,
			force_trait = trait_attr,
		}
	end

	local corpse_cframe = dead_model:GetPivot()
	local spawned = ArmyService.summon_unit_at(
		player,
		template_name,
		corpse_cframe,
		overrides
	)
	if not spawned then
		warn(
			"[ArmyService] Raise passed roll but spawn failed:",
			template_name,
			used,
			maximum
		)
		return false, "SPAWN_FAILED", chance, cost
	end

	if unit_record_service
		and unit_record_service.from_model
		and unit_record_service.make_captured
		and unit_record_service.apply_to_model
	then
		local old_record = unit_record_service.from_model(
			dead_model
		)
		local captured = unit_record_service.make_captured(
			old_record
		)
		if captured then
			unit_record_service.apply_to_model(
				spawned,
				captured
			)
		end
	end

	if dead_model.Parent ~= nil then
		dead_model:Destroy()
	end

	print("[RAISE SUCCESS]", template_name, "chance=", chance)
	return true, "SUCCESS", chance, cost
end

return ArmyService
