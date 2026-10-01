--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

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
local did_init = false

local PLAYER_ARMIES_FOLDER_NAME = "PlayerArmies"
local DEFAULT_STARTER_TEMPLATE = "Skeleton"
local DEFAULT_STARTER_COUNT = 3

local CORPSE_CLEANUP_SECONDS = 5

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

-- Templates that always raise (keyed by normalized template key).
-- Normalization: lowercase + remove spaces/underscores.
local ALWAYS_RAISE_TEMPLATE_KEYS: { [string]: boolean } = {
	cryptwarden = true,
	gravebaron = true,
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
	template_name: string,
	size_tier: string?,
	trait: string?,
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
end

local function hook_unit_death_cleanup(
	player: Player,
	unit_model: Model,
	humanoid: Humanoid
)
	humanoid.Died:Connect(function()
		remove_unit_from_army(player, unit_model)

		if unit_model.Parent ~= nil then
			Debris:AddItem(unit_model, CORPSE_CLEANUP_SECONDS)
		end
	end)
end

local function ensure_player_death_hooks(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		ArmyService.clear_army(player)
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

local NO_COLLISION_FOLDER_NAME = "NoCollisionWithLeader"

local function get_collidable_parts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.CanCollide then
			table.insert(parts, inst)
		end
	end
	return parts
end

local function clear_no_collision_constraints(unit_model: Model)
	local folder = unit_model:FindFirstChild(NO_COLLISION_FOLDER_NAME)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("NoCollisionConstraint") then
			child:Destroy()
		end
	end
end

local function ensure_no_collision_folder(unit_model: Model): Folder
	local existing = unit_model:FindFirstChild(NO_COLLISION_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = NO_COLLISION_FOLDER_NAME
	folder.Parent = unit_model
	return folder
end

local function disable_collision_with_leader(unit_model: Model, leader_model: Model)
	-- Units should collide with one another, but not with their own leader
	-- (including the player character).
	local folder = ensure_no_collision_folder(unit_model)
	clear_no_collision_constraints(unit_model)

	local unit_parts = get_collidable_parts(unit_model)
	local leader_parts = get_collidable_parts(leader_model)

	for _, unit_part in ipairs(unit_parts) do
		for _, leader_part in ipairs(leader_parts) do
			local c = Instance.new("NoCollisionConstraint")
			c.Part0 = unit_part
			c.Part1 = leader_part
			c.Parent = folder
		end
	end
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

	spawn_index_by_user_id[player.UserId] = (spawn_index_by_user_id[player.UserId] or 0)
		+ 1
	model:SetAttribute("ArmyUnitId", spawn_index_by_user_id[player.UserId])

	if model_library_service.set_units_collision then
		model_library_service.set_units_collision(model)
	end

	local leader_model = player.Character
	if leader_model and leader_model:IsA("Model") then
		disable_collision_with_leader(model, leader_model)
	end

	local humanoid = get_humanoid(model)
	local root = get_root(model)

	if not (humanoid and root) then
		model:Destroy()
		return nil
	end

	local unit: ArmyUnit = {
		model = model,
		humanoid = humanoid,
		root = root,
	}

	armies_by_user_id[player.UserId] = armies_by_user_id[player.UserId] or {}
	table.insert(armies_by_user_id[player.UserId], unit)

	hook_unit_death_cleanup(player, model, humanoid)

	return model
end

local function summon_starter_units(player: Player)
	-- Always spawn exactly 3 NORMAL Skeletons for the player.
	local overrides: SpawnOverrides = {
		force_size_tier = "Normal",
		force_trait = "None",
	}

	ArmyService.summon_units(
		player,
		DEFAULT_STARTER_TEMPLATE,
		DEFAULT_STARTER_COUNT,
		overrides
	)
end

local function normalize_template_key(name: string): string
	local lower = string.lower(name)
	local stripped = string.gsub(lower, "[%s_]+", "")
	return stripped
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

function ArmyService.init(model_library)
	model_library_service = model_library
	did_init = true

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			ensure_player_death_hooks(player, character)

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

function ArmyService.clear_army(player: Player)
	local folder = get_or_create_player_army_folder(player)

	local list = armies_by_user_id[player.UserId] or {}
	for _, u in ipairs(list) do
		if u.model and u.model.Parent ~= nil then
			u.model:Destroy()
		end
	end

	armies_by_user_id[player.UserId] = {}

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
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
function ArmyService.snapshot_and_clear_army(player: Player): { UnitSnapshot }
	local list = armies_by_user_id[player.UserId] or {}
	local snapshot: { UnitSnapshot } = {}

	for _, u in ipairs(list) do
		local model = u.model
		if model and model.Parent ~= nil then
			local template_name = read_string_attr(model, ATTR_TEMPLATE_NAME)
			if not template_name then
				template_name = model.Name
			end

			local size_tier = read_string_attr(model, ATTR_SIZE_TIER)
			local trait = read_string_attr(model, ATTR_TRAIT)

			table.insert(snapshot, {
				template_name = template_name,
				size_tier = size_tier,
				trait = trait,
			})
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

		local models = ArmyService.summon_units(player, s.template_name, 1, overrides)
		for _, m in ipairs(models) do
			table.insert(spawned, m)
		end
	end

	return spawned
end

function ArmyService.try_raise_dead(player: Player, dead_model: Model): boolean
	print(
		"[RAISE CALL]",
		"DeadModel=",
		dead_model.Name,
		"TemplateKeyAttr=",
		dead_model:GetAttribute("TemplateKey"),
		"TemplateNameAttr=",
		dead_model:GetAttribute("TemplateName")
	)

	if not model_library_service then
		return false
	end

	local template_attr = dead_model:GetAttribute(ATTR_TEMPLATE_NAME)
	local size_attr = dead_model:GetAttribute(ATTR_SIZE_TIER)
	local trait_attr = dead_model:GetAttribute(ATTR_TRAIT)

	local template_name = DEFAULT_STARTER_TEMPLATE
	if typeof(template_attr) == "string" and template_attr ~= "" then
		template_name = template_attr
	end

	-- Named/boss templates always raise.
	local template_key = normalize_template_key(template_name)
	local stats_key = template_name

	local unit_stats = nil
	if model_library_service.get_unit_stats then
		unit_stats = model_library_service.get_unit_stats(stats_key)
	end

	print(
		"[RAISE CHECK]",
		"stats_key=",
		stats_key,
		"unit_stats_exists=",
		unit_stats ~= nil,
		"AlwaysRaise=",
		unit_stats and unit_stats.AlwaysRaise,
		"RaiseChance=",
		unit_stats and unit_stats.RaiseChance
	)

	if unit_stats and unit_stats.AlwaysRaise == true then
		-- Always raise: skip chance roll.
	else
		-- 2) Named/boss templates always raise (your existing rule).
		if not ALWAYS_RAISE_TEMPLATE_KEYS[template_key] then
			local raise_chance: number

			-- 3) If unit defines RaiseChance, use it. Otherwise fallback to rarity logic.
			if unit_stats and type(unit_stats.RaiseChance) == "number" then
				raise_chance = clamp01(unit_stats.RaiseChance)
			else
				local size_name = (typeof(size_attr) == "string") and size_attr
					or "Normal"
				local trait_name = (typeof(trait_attr) == "string") and trait_attr
					or "None"

				raise_chance = compute_rarity_scaled_raise_chance(size_name, trait_name)
			end

			local roll = Random.new():NextNumber(0, 1)
			print("[RAISE ROLL]", "roll=", roll, "raise_chance=", raise_chance)

			if roll > raise_chance then
				return false
			end
		end
	end

	local overrides: SpawnOverrides? = nil
	if typeof(size_attr) == "string" and typeof(trait_attr) == "string" then
		overrides = {
			force_size_tier = size_attr,
			force_trait = trait_attr,
		}
	end

	if dead_model.Parent ~= nil then
		dead_model:Destroy()
	end

	-- Raise 1 unit that matches the corpse's template + size + trait.
	ArmyService.summon_units(player, template_name, 1, overrides)
	print("[RAISE SUCCESS]", template_name)
	return true
end

return ArmyService
