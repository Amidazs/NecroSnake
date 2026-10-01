--!strict

-- ModelLibraryService
-- - Holds templates under ServerStorage/ModelLibrary
-- - Spawns clones into Workspace (or provided parent)
-- - Ensures an Animations folder exists with Idle/Walk animations
-- - Starts a server-side NPC animation controller (Idle/Walk)
-- - Provides collision-group helpers (Units vs Leaders)
-- - Leaves corpse lifecycle/raising to CombatService
-- - Applies per-unit stats (HP/Damage/Cooldown/WalkSpeed)
-- - Applies size tier + trait modifiers with weighted rarity rolls
-- - Names NPCs based on rarity rolls (e.g. "Giant Tough Skeleton")

local PhysicsService = game:GetService("PhysicsService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local NpcAnimationController =
	require(script.Parent.Parent.Systems.NpcAnimationController)

local ModelLibraryService = {}

local MODEL_LIBRARY_FOLDER_NAME = "ModelLibrary"
local NPC_FOLDER_NAME = "NPCs"

local COLLISION_GROUP_UNITS = "Units"
local COLLISION_GROUP_LEADERS = "Leaders"

-- Attributes written to spawned NPC models so other systems (raising, UI, etc.)
-- can reliably identify what the model is, even if Model.Name is a display name.
local ATTR_TEMPLATE_NAME = "TemplateName"
local ATTR_TEMPLATE_KEY = "TemplateKey"
local ATTR_SIZE_TIER = "SizeTier"
local ATTR_TRAIT = "Trait"

-- Anti-climb "hat" collider settings
local ANTI_CLIMB_HAT_NAME = "AntiClimbHat"
local ANTI_CLIMB_HAT_THICKNESS = 0.5
local ANTI_CLIMB_HAT_EXTRA_RADIUS = 1.0
local ANTI_CLIMB_HAT_HEIGHT_OFFSET = 2.8

type StatDef = {
	Health: number,
	Damage: number,
	AttackCooldown: number,
	WalkSpeed: number,
	Weight: number,
	CommandCost: number,
	BaseScale: number?,
	DefaultCohort: string?,
	AttackRange: number?,
	PreferredRange: number?,

	IsBoss: boolean?,
	AlwaysRaise: boolean?,
	RaiseChance: number?,
}


type SpawnModifiers = {
	force_size_tier: string?,
	force_trait: string?,
}

local UNIT_STATS: { [string]: StatDef } = {

	-- ========================
	-- TRASH (very common)
	-- ========================
	WeakSkeleton = {
		Health = 30,
		Damage = 5,
		AttackCooldown = 0.9,
		WalkSpeed = 12,
		Weight = 6, -- VERY common
		CommandCost = 1,
		BaseScale = 1.3,
		DefaultCohort = "SecondLine",
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.90,
	},

	-- ========================
	-- BASELINE (common)
	-- ========================
	Skeleton = {
		Health = 60,
		Damage = 10,
		AttackCooldown = 0.9,
		WalkSpeed = 12,
		Weight = 3, -- common
		CommandCost = 1,
		DefaultCohort = "SecondLine",
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.85, -- 0..1
	},

	-- ========================
	-- RANGED (common)
	-- ========================
	SkeletonArcher = {
		Health = 45,
		Damage = 8,
		AttackCooldown = 1.25,
		WalkSpeed = 11,
		Weight = 1.4,
		CommandCost = 1,
		DefaultCohort = "Ranged",
		AttackRange = 30,
		PreferredRange = 22,
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.75,
	},

	-- ========================
	-- UNCOMMON TANK
	-- ========================
	SkeletonKnight = {
		Health = 100,
		Damage = 8,
		AttackCooldown = 0.9,
		WalkSpeed = 10,
		Weight = 1,
		CommandCost = 2,
		BaseScale = 1.5,
		DefaultCohort = "Frontline",
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.65, -- 0..1
	},

	-- ========================
	-- UNCOMMON BRUISER
	-- ========================
	ZombieBrute = {
		Health = 90,
		Damage = 12,
		AttackCooldown = 1.1,
		WalkSpeed = 10,
		Weight = 1,
		CommandCost = 2,
		BaseScale = 1.5,
		DefaultCohort = "Frontline",
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.55, -- 0..1
	},

	-- ========================
	-- RARE ELITE
	-- ========================
	DarkKnight = {
		Health = 85,
		Damage = 14,
		AttackCooldown = 1.0,
		WalkSpeed = 13,
		Weight = 0.25, -- rare
		CommandCost = 3,
		BaseScale = 1.7,
		DefaultCohort = "Frontline",
		IsBoss = false,
		AlwaysRaise = false,
		RaiseChance = 0.45, -- 0..1
	},

	-- ========================
	-- BOSS (extremely rare)
	-- ========================
	GraveBaron = {
		Health = 500,
		Damage = 34,
		AttackCooldown = 1.2,
		WalkSpeed = 10,
		Weight = 0.03, -- basically never random
		CommandCost = 10,
		BaseScale = 3,
		DefaultCohort = "PersonalGuard",
		IsBoss = true,
		AlwaysRaise = false,
		RaiseChance = 0.25,

	},

	CryptWarden = {
		Health = 500,
		Damage = 34,
		AttackCooldown = 1.2,
		WalkSpeed = 10,
		Weight = 0.03, -- basically never random
		CommandCost = 10,
		BaseScale = 3,
		DefaultCohort = "PersonalGuard",
		IsBoss = true,
		AlwaysRaise = false,
		RaiseChance = 0.25,

	},
}


local SIZE_TIERS: { [string]: number } = {
	Normal = 0.72,
	Small = 0.14,
	Giant = 0.14,
}

local TRAIT_MODS: { [string]: number } = {
	None = 0.78,
	Tough = 0.12,
	Frenzied = 0.10,
}

local SIZE_MULTS: { [string]: { scale: number, hp: number, dmg: number, spd: number } } =
	{
		Normal = { scale = 1.0, hp = 1.0, dmg = 1.0, spd = 1.0 },
		Small = { scale = 0.8, hp = 0.8, dmg = 0.85, spd = 1.12 },
		Giant = { scale = 1.35, hp = 1.55, dmg = 1.25, spd = 0.92 },
	}

local TRAIT_MULTS: { [string]: { hp: number, dmg: number, spd: number, defense: number } } =
	{
		None = { hp = 1.0, dmg = 1.0, spd = 1.0, defense = 0 },
		Tough = { hp = 1.25, dmg = 1.0, spd = 0.95, defense = 0.2 },
		Frenzied = { hp = 0.95, dmg = 1.2, spd = 1.1, defense = 0 },
	}

local model_library_folder: Folder? = nil
local npc_folder: Folder? = nil

-- Maps a normalized template key (lowercase, no spaces/underscores) to the
-- canonical template Model.Name stored under ServerStorage/ModelLibrary.
local template_key_to_canonical_name: { [string]: string } = {}

local function now(): number
	return os.clock()
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

local function ensure_folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function ensure_library_folder(): Folder
	return ensure_folder(ServerStorage, MODEL_LIBRARY_FOLDER_NAME)
end

local function ensure_npc_folder(): Folder
	return ensure_folder(Workspace, NPC_FOLDER_NAME)
end

local function normalize_template_key(name: string): string
	-- Normalize names so "CryptWarden", "Crypt Warden", and "crypt_warden"
	-- all resolve to the same key.
	local lower = string.lower(name)
	local stripped = string.gsub(lower, "[%s_]+", "")
	return stripped
end

local function find_first_body_part(
	model: Model,
	names: { string }
): BasePart?
	for _, name in ipairs(names) do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return model.PrimaryPart
end

local function weld_visual_part(
	model: Model,
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	body_part: BasePart,
	local_cframe: CFrame
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	part.CFrame = body_part.CFrame * local_cframe
	part.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body_part
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function ensure_skeleton_archer_template()
	if not model_library_folder then
		return
	end
	if model_library_folder:FindFirstChild("SkeletonArcher") then
		return
	end

	local source = model_library_folder:FindFirstChild("Skeleton")
		or model_library_folder:FindFirstChild("WeakSkeleton")
	if not (source and source:IsA("Model")) then
		warn(
			"[ModelLibraryService] Cannot generate SkeletonArcher: "
				.. "Skeleton source template missing"
		)
		return
	end

	local archer = source:Clone()
	archer.Name = "SkeletonArcher"
	archer:SetAttribute("GeneratedTemplate", true)

	local hand = find_first_body_part(
		archer,
		{ "RightHand", "Right Arm", "RightLowerArm" }
	)
	if hand then
		local wood = Color3.fromRGB(92, 58, 34)
		weld_visual_part(
			archer,
			"BowGrip",
			Vector3.new(0.18, 2.9, 0.18),
			wood,
			Enum.Material.Wood,
			hand,
			CFrame.new(0, -0.25, -0.45)
				* CFrame.Angles(0, 0, math.rad(8))
		)
		weld_visual_part(
			archer,
			"BowUpperLimb",
			Vector3.new(0.16, 1.9, 0.16),
			wood,
			Enum.Material.Wood,
			hand,
			CFrame.new(0.28, 1.35, -0.45)
				* CFrame.Angles(0, 0, math.rad(-18))
		)
		weld_visual_part(
			archer,
			"BowLowerLimb",
			Vector3.new(0.16, 1.9, 0.16),
			wood,
			Enum.Material.Wood,
			hand,
			CFrame.new(-0.28, -1.65, -0.45)
				* CFrame.Angles(0, 0, math.rad(-18))
		)
	end

	local torso = find_first_body_part(
		archer,
		{ "UpperTorso", "Torso", "HumanoidRootPart" }
	)
	if torso then
		weld_visual_part(
			archer,
			"Quiver",
			Vector3.new(0.55, 2.1, 0.55),
			Color3.fromRGB(70, 45, 30),
			Enum.Material.Fabric,
			torso,
			CFrame.new(0.65, 0.25, 0.75)
				* CFrame.Angles(math.rad(-12), 0, math.rad(16))
		)
	end

	archer.Parent = model_library_folder
end

local function rebuild_template_lookup()
	table.clear(template_key_to_canonical_name)

	if not model_library_folder then
		return
	end

	local names: { string } = {}
	for _, inst in ipairs(model_library_folder:GetChildren()) do
		if inst:IsA("Model") then
			table.insert(names, inst.Name)
		end
	end
	table.sort(names)

	for _, name in ipairs(names) do
		local key = normalize_template_key(name)
		local existing = template_key_to_canonical_name[key]

		if not existing then
			template_key_to_canonical_name[key] = name
		else
			-- If duplicates exist (e.g. "CryptWarden" and "Crypt Warden"),
			-- prefer the shorter name (usually the one without spaces).
			if #name < #existing then
				template_key_to_canonical_name[key] = name
			end
		end
	end
end

local function ensure_default_animations(model: Model)
	local anims = model:FindFirstChild("Animations")
	if not anims then
		anims = Instance.new("Folder")
		anims.Name = "Animations"
		anims.Parent = model
	end

	local idle = anims:FindFirstChild("Idle")
	if not idle then
		idle = Instance.new("Animation")
		idle.Name = "Idle"
		idle.AnimationId = "rbxassetid://507766666"
		idle.Parent = anims
	end

	local walk = anims:FindFirstChild("Walk")
	if not walk then
		walk = Instance.new("Animation")
		walk.Name = "Walk"
		walk.AnimationId = "rbxassetid://507777826"
		walk.Parent = anims
	end
end

local function ensure_parts_unanchored(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = false
		end
	end
end

local function ensure_collision_groups_exist()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_UNITS)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_LEADERS)
	end)
end

local function set_descendants_collision_group(model: Model, group_name: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group_name
		end
	end
end

local function get_hrp(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function remove_existing_anti_climb_hat(model: Model)
	local existing = model:FindFirstChild(ANTI_CLIMB_HAT_NAME)
	if existing and existing:IsA("BasePart") then
		existing:Destroy()
	end
end

local function create_anti_climb_hat(model: Model)
	-- This creates an invisible collidable "cap" above the character.
	-- Units can still collide, but they can't step up onto each other.
	local hrp = get_hrp(model)
	local hum = get_humanoid(model)
	if not (hrp and hum) then
		return
	end

	remove_existing_anti_climb_hat(model)

	local scale_attr = model:GetAttribute("SizeScale")
	local scale = 1.0
	if typeof(scale_attr) == "number" and scale_attr > 0 then
		scale = scale_attr
	end

	local base_radius = math.max(hrp.Size.X, hrp.Size.Z) * 0.5
	local radius = (base_radius + ANTI_CLIMB_HAT_EXTRA_RADIUS) * scale

	local hat = Instance.new("Part")
	hat.Name = ANTI_CLIMB_HAT_NAME
	hat.Anchored = false
	hat.CanCollide = true
	hat.CanQuery = false
	hat.CanTouch = false
	hat.CastShadow = false
	hat.Transparency = 1
	hat.Material = Enum.Material.Plastic
	hat.Massless = true
	hat.Size = Vector3.new(radius * 2, ANTI_CLIMB_HAT_THICKNESS, radius * 2)

	-- Position above HRP; this doesn’t need to be perfect, just consistently above
	-- the body so other units can’t stand on shoulders.
	local y_offset = (hrp.Size.Y * 0.5) + (hum.HipHeight) + ANTI_CLIMB_HAT_HEIGHT_OFFSET
	hat.CFrame = hrp.CFrame * CFrame.new(0, y_offset, 0)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hat
	weld.Part1 = hrp
	weld.Parent = hat

	hat.Parent = model
end

local function set_model_scale_to(model: Model, scale: number)
	if scale <= 0 then
		scale = 1
	end

	model:ScaleTo(scale)
end


local function pick_weighted_key(weights: { [string]: number }): string
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	if total <= 0 then
		for k, _ in pairs(weights) do
			return k
		end
		return "None"
	end

	local roll = math.random() * total
	local running = 0

	for k, w in pairs(weights) do
		running += w
		if roll <= running then
			return k
		end
	end

	for k, _ in pairs(weights) do
		return k
	end

	return "None"
end

local function build_display_name(
	template_name: string,
	size_name: string,
	trait_name: string
): string
	local parts: { string } = {}

	if size_name ~= "Normal" then
		table.insert(parts, size_name)
	end

	if trait_name ~= "None" then
		table.insert(parts, trait_name)
	end

	table.insert(parts, template_name)

	return table.concat(parts, " ")
end

local function choose_size_and_trait(mods: SpawnModifiers?): (string, string)
	local size_name = pick_weighted_key(SIZE_TIERS)
	local trait_name = pick_weighted_key(TRAIT_MODS)

	if mods then
		if mods.force_size_tier and SIZE_TIERS[mods.force_size_tier] then
			size_name = mods.force_size_tier
		end
		if mods.force_trait and TRAIT_MODS[mods.force_trait] then
			trait_name = mods.force_trait
		end
	end

	return size_name, trait_name
end

local function write_spawn_identity_attributes(
	model: Model,
	canonical_template_name: string,
	size_name: string,
	trait_name: string
)
	model:SetAttribute(ATTR_TEMPLATE_NAME, canonical_template_name)
	model:SetAttribute(ATTR_TEMPLATE_KEY, normalize_template_key(canonical_template_name))
	model:SetAttribute(ATTR_SIZE_TIER, size_name)
	model:SetAttribute(ATTR_TRAIT, trait_name)
end

local function apply_stats_size_traits(
	model: Model,
	canonical_template_name: string,
	mods: SpawnModifiers?
): (string, string)
	local def = UNIT_STATS[canonical_template_name]
	if not def then
		def = {
			Health = 60,
			Damage = 10,
			AttackCooldown = 1.0,
			WalkSpeed = 12,
			Weight = 1,
			CommandCost = 1,
		}
	end

	local size_name, trait_name = choose_size_and_trait(mods)

	local size_mult = SIZE_MULTS[size_name] or SIZE_MULTS.Normal
	local trait_mult = TRAIT_MULTS[trait_name] or TRAIT_MULTS.None

	-- BaseScale is per-unit permanent size modifier
	local base_scale = def.BaseScale or 1

	-- Final scale = base unit scale × size tier multiplier
	local scale = size_mult.scale * base_scale

	local hp = def.Health * size_mult.hp * trait_mult.hp
	local dmg = def.Damage * size_mult.dmg * trait_mult.dmg
	local spd = def.WalkSpeed * size_mult.spd * trait_mult.spd


	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxHealth = math.max(1, math.floor(hp + 0.5))
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = clamp(spd, 6, 24)
		humanoid.BreakJointsOnDeath = false
	end

	model:SetAttribute("Damage", math.max(1, math.floor(dmg + 0.5)))
	model:SetAttribute("AttackCooldown", clamp(def.AttackCooldown, 0.2, 6.0))
	model:SetAttribute("Defense", clamp(trait_mult.defense, 0, 0.9))
	model:SetAttribute("SizeScale", scale)
	local command_cost = def.CommandCost
	if size_name == "Giant" then
		command_cost = math.max(command_cost + 1, math.ceil(command_cost * 1.5))
	end
	model:SetAttribute("CommandCost", command_cost)
	model:SetAttribute("DefaultCohort", def.DefaultCohort or "SecondLine")
	if typeof(def.AttackRange) == "number" then
		model:SetAttribute("AttackRange", math.max(1, def.AttackRange))
	else
		model:SetAttribute("AttackRange", nil)
	end
	if typeof(def.PreferredRange) == "number" then
		model:SetAttribute(
			"PreferredRange",
			math.max(1, def.PreferredRange)
		)
	else
		model:SetAttribute("PreferredRange", nil)
	end

	set_model_scale_to(model, scale)

	-- Persist identity for raising logic before we overwrite Model.Name.
	write_spawn_identity_attributes(model, canonical_template_name, size_name, trait_name)

	model.Name = build_display_name(canonical_template_name, size_name, trait_name)

	return size_name, trait_name
end

local function get_template_info(requested_name: string): (Model?, string?)
	if not model_library_folder then
		return nil, nil
	end

	-- First try an exact name match (fast path).
	local direct = model_library_folder:FindFirstChild(requested_name)
	if direct and direct:IsA("Model") then
		return direct, direct.Name
	end

	-- Otherwise fall back to normalized lookup.
	local key = normalize_template_key(requested_name)
	local canonical = template_key_to_canonical_name[key]
	if not canonical then
		return nil, nil
	end

	local m = model_library_folder:FindFirstChild(canonical)
	if m and m:IsA("Model") then
		return m, canonical
	end

	return nil, nil
end

function ModelLibraryService.init()
	model_library_folder = ensure_library_folder()
	npc_folder = ensure_npc_folder()
	ensure_collision_groups_exist()

	ensure_skeleton_archer_template()
	rebuild_template_lookup()
end

local function normalize_stats_key(name: string): string
	local lower = string.lower(name)
	return (string.gsub(lower, "[%s_]+", ""))
end

function ModelLibraryService.get_unit_stats(template_key: string): StatDef?
	local direct = UNIT_STATS[template_key]
	if direct then
		return direct
	end

	local normalized = normalize_stats_key(template_key)
	for key, stats in pairs(UNIT_STATS) do
		if normalize_stats_key(key) == normalized then
			return stats
		end
	end

	return nil
end



function ModelLibraryService.get_npc_folder(): Folder?
	return npc_folder
end

function ModelLibraryService.list_template_names(): { string }
	if not model_library_folder then
		return {}
	end

	local result: { string } = {}
	for _, inst in ipairs(model_library_folder:GetChildren()) do
		if inst:IsA("Model") then
			table.insert(result, inst.Name)
		end
	end
	table.sort(result)
	return result
end

function ModelLibraryService.pick_spawn_template(names: { string }): string?
	if #names <= 0 then
		return nil
	end

	local total = 0
	for _, name in ipairs(names) do
		local def = UNIT_STATS[name]
		total += (def and def.Weight) or 1
	end

	local roll = math.random() * total
	local running = 0

	for _, name in ipairs(names) do
		local def = UNIT_STATS[name]
		running += (def and def.Weight) or 1
		if roll <= running then
			return name
		end
	end

	return names[1]
end

function ModelLibraryService.set_units_collision(model: Model)
	set_descendants_collision_group(model, COLLISION_GROUP_UNITS)
end

function ModelLibraryService.set_leaders_collision(model: Model)
	set_descendants_collision_group(model, COLLISION_GROUP_LEADERS)
end

function ModelLibraryService.spawn_from_template(
	template_name: string,
	cframe: CFrame,
	parent: Instance?,
	mods: SpawnModifiers?
): Model?
	local template, canonical_name = get_template_info(template_name)
	if not (template and canonical_name) then
		warn(("ModelLibraryService: template not found: %s"):format(template_name))
		return nil
	end

	local clone = template:Clone()
	clone:SetAttribute("TemplateKey", template_name)
	clone.Parent = parent or npc_folder or Workspace


	clone:PivotTo(cframe)

	local def = UNIT_STATS[canonical_name]
	local is_boss = false
	if def and def.IsBoss == true then
		is_boss = true
	end
	clone:SetAttribute("IsBoss", is_boss)



	ensure_parts_unanchored(clone)
	ensure_default_animations(clone)

	-- Apply stats + size + traits first so SizeScale exists.
	apply_stats_size_traits(clone, canonical_name, mods)

	-- Add anti-climb collider (invisible hat) while keeping normal collisions.
	create_anti_climb_hat(clone)

	-- Default collision group for spawned units is Units;
	-- callers can override.
	ModelLibraryService.set_units_collision(clone)

	local controller = NpcAnimationController.new(clone)
	controller:start()

	return clone
end

return ModelLibraryService
