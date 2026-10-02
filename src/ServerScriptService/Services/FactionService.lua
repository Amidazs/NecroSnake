--!strict

local FactionService = {}

local VISUAL_FOLDER_NAME = "FactionVisuals"
local ATTR_FACTION_ID = "FactionId"
local ATTR_FACTION_NAME = "FactionName"
local ATTR_COMBAT_ROLE = "CombatRole"
local ATTR_COMBAT_ROLE_NAME = "CombatRoleName"
local ATTR_FACTION_RARITY = "FactionRarity"
local ATTR_FACTION_REGION = "FactionRegion"

local ROLE_BASE_HEALTH = "RoleBaseHealth"
local ROLE_BASE_DAMAGE = "RoleBaseDamage"
local ROLE_BASE_COOLDOWN = "RoleBaseAttackCooldown"
local ROLE_BASE_DEFENSE = "RoleBaseDefense"
local ROLE_BASE_COST = "RoleBaseCommandCost"
local ROLE_BASE_RANGE = "RoleBaseAttackRange"
local ROLE_BASE_PREFERRED = "RoleBasePreferredRange"
local ROLE_BASE_SPEED = "RoleBaseWalkSpeed"

export type RosterEntry = {
	template_name: string,
	role_id: string,
	weight: number,
	rarity: string,
}

export type RoleDefinition = {
	display_name: string,
	cohort: string,
	min_command_cost: number,
	health_multiplier: number,
	damage_multiplier: number,
	cooldown_multiplier: number,
	speed_multiplier: number,
	defense_bonus: number,
	attack_range: number?,
	preferred_range: number?,
	support_heal: number?,
	support_radius: number?,
	support_cooldown: number?,
}

export type FactionDefinition = {
	id: string,
	display_name: string,
	short_name: string,
	region_name: string,
	color: Color3,
	roster: { RosterEntry },
}

local ROLE_DEFINITIONS: { [string]: RoleDefinition } = {
	Shield = {
		display_name = "Shield",
		cohort = "Frontline",
		min_command_cost = 2,
		health_multiplier = 1.15,
		damage_multiplier = 0.90,
		cooldown_multiplier = 1.0,
		speed_multiplier = 0.92,
		defense_bonus = 0.18,
		attack_range = 6,
		preferred_range = 4.5,
	},
	Spear = {
		display_name = "Spear",
		cohort = "Frontline",
		min_command_cost = 1,
		health_multiplier = 1.0,
		damage_multiplier = 1.08,
		cooldown_multiplier = 1.0,
		speed_multiplier = 1.0,
		defense_bonus = 0,
		attack_range = 8.5,
		preferred_range = 6.5,
	},
	Archer = {
		display_name = "Archer",
		cohort = "Ranged",
		min_command_cost = 1,
		health_multiplier = 0.95,
		damage_multiplier = 0.95,
		cooldown_multiplier = 1.0,
		speed_multiplier = 1.0,
		defense_bonus = 0,
		attack_range = 30,
		preferred_range = 22,
	},
	Caster = {
		display_name = "Caster",
		cohort = "Ranged",
		min_command_cost = 2,
		health_multiplier = 0.9,
		damage_multiplier = 1.18,
		cooldown_multiplier = 1.18,
		speed_multiplier = 0.96,
		defense_bonus = 0,
		attack_range = 26,
		preferred_range = 18,
	},
	Brute = {
		display_name = "Brute",
		cohort = "Frontline",
		min_command_cost = 2,
		health_multiplier = 1.35,
		damage_multiplier = 1.22,
		cooldown_multiplier = 1.1,
		speed_multiplier = 0.88,
		defense_bonus = 0.05,
		attack_range = 6.5,
		preferred_range = 4.5,
	},
	Support = {
		display_name = "Support",
		cohort = "RearGuard",
		min_command_cost = 2,
		health_multiplier = 0.95,
		damage_multiplier = 0.65,
		cooldown_multiplier = 1.2,
		speed_multiplier = 0.98,
		defense_bonus = 0,
		attack_range = 18,
		preferred_range = 14,
		support_heal = 8,
		support_radius = 18,
		support_cooldown = 3,
	},
	Skirmisher = {
		display_name = "Skirmisher",
		cohort = "Flanks",
		min_command_cost = 1,
		health_multiplier = 0.9,
		damage_multiplier = 1.08,
		cooldown_multiplier = 0.9,
		speed_multiplier = 1.15,
		defense_bonus = 0,
		attack_range = 6,
		preferred_range = 4,
	},
	Reaver = {
		display_name = "Reaver",
		cohort = "Flanks",
		min_command_cost = 3,
		health_multiplier = 1.1,
		damage_multiplier = 1.18,
		cooldown_multiplier = 0.9,
		speed_multiplier = 1.12,
		defense_bonus = 0.05,
		attack_range = 8,
		preferred_range = 6,
	},
	Cavalry = {
		display_name = "Cavalry",
		cohort = "Flanks",
		min_command_cost = 3,
		health_multiplier = 1.15,
		damage_multiplier = 1.12,
		cooldown_multiplier = 0.92,
		speed_multiplier = 1.22,
		defense_bonus = 0.08,
		attack_range = 9,
		preferred_range = 7,
	},
}

local FACTION_ORDER = {
	"OssuaryLegion",
	"Mirebound",
	"AshenCovenant",
	"GraveCourt",
}

local FACTIONS: { [string]: FactionDefinition } = {
	OssuaryLegion = {
		id = "OssuaryLegion",
		display_name = "Ossuary Legion",
		short_name = "LEGION",
		region_name = "Northwest Ossuary",
		color = Color3.fromRGB(205, 205, 185),
		roster = {
			{
				template_name = "SkeletonKnight",
				role_id = "Shield",
				weight = 4.5,
				rarity = "Common",
			},
			{
				template_name = "Skeleton",
				role_id = "Spear",
				weight = 5,
				rarity = "Common",
			},
			{
				template_name = "SkeletonArcher",
				role_id = "Archer",
				weight = 4,
				rarity = "Common",
			},
			{
				template_name = "WeakSkeleton",
				role_id = "Support",
				weight = 1.6,
				rarity = "Uncommon",
			},
			{
				template_name = "DarkKnight",
				role_id = "Cavalry",
				weight = 0.55,
				rarity = "Elite",
			},
		},
	},
	Mirebound = {
		id = "Mirebound",
		display_name = "Mirebound Brood",
		short_name = "MIRE",
		region_name = "Southwest Mire",
		color = Color3.fromRGB(95, 150, 92),
		roster = {
			{
				template_name = "ZombieBrute",
				role_id = "Brute",
				weight = 4.5,
				rarity = "Common",
			},
			{
				template_name = "WeakSkeleton",
				role_id = "Skirmisher",
				weight = 4,
				rarity = "Common",
			},
			{
				template_name = "WeakSkeleton",
				role_id = "Support",
				weight = 3,
				rarity = "Common",
			},
			{
				template_name = "SkeletonArcher",
				role_id = "Caster",
				weight = 2.2,
				rarity = "Uncommon",
			},
			{
				template_name = "ZombieBrute",
				role_id = "Brute",
				weight = 0.65,
				rarity = "Elite",
			},
		},
	},
	AshenCovenant = {
		id = "AshenCovenant",
		display_name = "Ashen Covenant",
		short_name = "ASHEN",
		region_name = "Northeast Ashlands",
		color = Color3.fromRGB(165, 105, 82),
		roster = {
			{
				template_name = "Skeleton",
				role_id = "Spear",
				weight = 3.5,
				rarity = "Common",
			},
			{
				template_name = "SkeletonArcher",
				role_id = "Archer",
				weight = 3.5,
				rarity = "Common",
			},
			{
				template_name = "SkeletonArcher",
				role_id = "Caster",
				weight = 4,
				rarity = "Common",
			},
			{
				template_name = "WeakSkeleton",
				role_id = "Support",
				weight = 2,
				rarity = "Uncommon",
			},
			{
				template_name = "DarkKnight",
				role_id = "Reaver",
				weight = 0.65,
				rarity = "Elite",
			},
		},
	},
	GraveCourt = {
		id = "GraveCourt",
		display_name = "Grave Court",
		short_name = "COURT",
		region_name = "Southeast Necropolis",
		color = Color3.fromRGB(128, 90, 165),
		roster = {
			{
				template_name = "SkeletonKnight",
				role_id = "Shield",
				weight = 3.5,
				rarity = "Common",
			},
			{
				template_name = "ZombieBrute",
				role_id = "Brute",
				weight = 3,
				rarity = "Common",
			},
			{
				template_name = "SkeletonArcher",
				role_id = "Caster",
				weight = 3,
				rarity = "Common",
			},
			{
				template_name = "WeakSkeleton",
				role_id = "Support",
				weight = 2,
				rarity = "Uncommon",
			},
			{
				template_name = "DarkKnight",
				role_id = "Reaver",
				weight = 0.8,
				rarity = "Elite",
			},
			{
				template_name = "GraveBaron",
				role_id = "Brute",
				weight = 0.08,
				rarity = "Rare",
			},
			{
				template_name = "CryptWarden",
				role_id = "Caster",
				weight = 0.08,
				rarity = "Rare",
			},
		},
	},
}

--[[
	Clamps a number to a closed range.

	Args:
		value (number): Input value.
		minimum (number): Minimum allowed value.
		maximum (number): Maximum allowed value.

	Returns:
		number: Clamped value.
]]
local function clamp(
	value: number,
	minimum: number,
	maximum: number
): number
	return math.max(minimum, math.min(maximum, value))
end

--[[
	Reads a numeric model attribute.

	Args:
		model (Model): Model to inspect.
		name (string): Attribute name.

	Returns:
		number?: Numeric value when present.
]]
local function read_number_attr(
	model: Model,
	name: string
): number?
	local value = model:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return nil
end

--[[
	Reads a non-empty string model attribute.

	Args:
		model (Model): Model to inspect.
		name (string): Attribute name.

	Returns:
		string?: String value when present.
]]
local function read_string_attr(
	model: Model,
	name: string
): string?
	local value = model:GetAttribute(name)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

--[[
	Returns the model Humanoid.

	Args:
		model (Model): Model to inspect.

	Returns:
		Humanoid?: Humanoid when present.
]]
local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

--[[
	Finds a stable body part for faction visuals.

	Args:
		model (Model): Model receiving visuals.

	Returns:
		BasePart?: Preferred torso/root part.
]]
local function get_attach_part(model: Model): BasePart?
	for _, name in ipairs({
		"UpperTorso",
		"Torso",
		"HumanoidRootPart",
	}) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return nil
end

--[[
	Removes visuals created by this service.

	Args:
		model (Model): Model whose faction visuals are removed.

	Returns:
		None.
]]
local function clear_visuals(model: Model)
	local old = model:FindFirstChild(VISUAL_FOLDER_NAME)
	if old then
		old:Destroy()
	end
end

--[[
	Creates one welded, non-colliding visual part.

	Args:
		folder (Folder): Visual folder parent.
		attach_part (BasePart): Part to weld against.
		name (string): New part name.
		size (Vector3): Visual part size.
		offset (CFrame): Offset from the attachment part.
		color (Color3): Faction display color.
		material (Enum.Material): Visual material.

	Returns:
		Part: Created welded part.
]]
local function create_welded_part(
	folder: Folder,
	attach_part: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = attach_part.CFrame * offset
	part.Parent = folder

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attach_part
	weld.Part1 = part
	weld.Parent = part
	return part
end

--[[
	Adds a role-specific silhouette prop.

	Args:
		folder (Folder): Visual folder parent.
		attach_part (BasePart): Body part used for welding.
		role_id (string): Combat role identifier.
		color (Color3): Faction color.

	Returns:
		None.
]]
local function create_role_prop(
	folder: Folder,
	attach_part: BasePart,
	role_id: string,
	color: Color3
)
	if role_id == "Shield" then
		create_welded_part(
			folder,
			attach_part,
			"RoleShield",
			Vector3.new(0.25, 2.4, 1.8),
			CFrame.new(-1.3, 0.1, 0),
			color,
			Enum.Material.Metal
		)
	elseif role_id == "Spear"
		or role_id == "Reaver"
		or role_id == "Cavalry"
	then
		create_welded_part(
			folder,
			attach_part,
			if role_id == "Cavalry"
				then "RoleLance"
				else "RoleSpear",
			if role_id == "Cavalry"
				then Vector3.new(0.18, 5.4, 0.18)
				else Vector3.new(0.18, 4.4, 0.18),
			CFrame.new(1.1, 0, 0),
			color,
			Enum.Material.Metal
		)
	elseif role_id == "Caster" then
		local orb = create_welded_part(
			folder,
			attach_part,
			"RoleOrb",
			Vector3.new(0.75, 0.75, 0.75),
			CFrame.new(1.05, 0.85, -0.3),
			color,
			Enum.Material.Neon
		)
		orb.Shape = Enum.PartType.Ball
	elseif role_id == "Support" then
		create_welded_part(
			folder,
			attach_part,
			"RoleStaff",
			Vector3.new(0.18, 3.8, 0.18),
			CFrame.new(1.1, 0, 0),
			color,
			Enum.Material.Wood
		)
		create_welded_part(
			folder,
			attach_part,
			"RoleBeacon",
			Vector3.new(0.9, 0.18, 0.18),
			CFrame.new(1.1, 1.6, 0),
			color,
			Enum.Material.Neon
		)
	elseif role_id == "Brute" then
		create_welded_part(
			folder,
			attach_part,
			"RolePauldronLeft",
			Vector3.new(0.7, 0.45, 0.8),
			CFrame.new(-0.95, 0.85, 0),
			color,
			Enum.Material.Metal
		)
		create_welded_part(
			folder,
			attach_part,
			"RolePauldronRight",
			Vector3.new(0.7, 0.45, 0.8),
			CFrame.new(0.95, 0.85, 0),
			color,
			Enum.Material.Metal
		)
	elseif role_id == "Archer" then
		create_welded_part(
			folder,
			attach_part,
			"RoleQuiver",
			Vector3.new(0.45, 1.8, 0.45),
			CFrame.new(0.7, 0.25, 0.65),
			color,
			Enum.Material.Wood
		)
	elseif role_id == "Skirmisher" then
		create_welded_part(
			folder,
			attach_part,
			"RoleBlade",
			Vector3.new(0.14, 1.6, 0.32),
			CFrame.new(1.0, 0.2, 0),
			color,
			Enum.Material.Metal
		)
	end
end

--[[
	Creates the faction and role nameplate.

	Args:
		folder (Folder): Visual folder parent.
		attach_part (BasePart): Billboard adornee.
		faction (FactionDefinition): Faction metadata.
		role (RoleDefinition): Combat role metadata.
		rarity (string): Rarity label.

	Returns:
		None.
]]
local function create_billboard(
	folder: Folder,
	attach_part: BasePart,
	faction: FactionDefinition,
	role: RoleDefinition,
	rarity: string
)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FactionIdentity"
	gui.Adornee = attach_part
	gui.Size = UDim2.fromOffset(132, 34)
	gui.StudsOffset = Vector3.new(0, 3.8, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 115
	gui.Parent = folder

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	label.BackgroundTransparency = 0.28
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = faction.color
	label.TextStrokeTransparency = 0.55
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ("%s · %s%s"):format(
		faction.short_name,
		role.display_name,
		if rarity == "Common" then "" else " · " .. rarity
	)
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label
end

--[[
	Creates faction color and role silhouette visuals.

	Args:
		model (Model): Unit receiving visuals.
		faction (FactionDefinition): Faction metadata.
		role (RoleDefinition): Combat role metadata.
		role_id (string): Combat role identifier.
		rarity (string): Faction rarity label.

	Returns:
		None.
]]
local function apply_visual_identity(
	model: Model,
	faction: FactionDefinition,
	role: RoleDefinition,
	role_id: string,
	rarity: string
)
	clear_visuals(model)

	local attach_part = get_attach_part(model)
	if not attach_part then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = VISUAL_FOLDER_NAME
	folder.Parent = model

	local highlight = Instance.new("Highlight")
	highlight.Name = "FactionOutline"
	highlight.Adornee = model
	highlight.FillColor = faction.color
	highlight.FillTransparency = 0.93
	highlight.OutlineColor = faction.color
	highlight.OutlineTransparency = 0.18
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = folder

	create_welded_part(
		folder,
		attach_part,
		"FactionBand",
		Vector3.new(1.1, 0.24, 0.32),
		CFrame.new(0, 0.9, 0.55),
		faction.color,
		Enum.Material.Neon
	)
	create_role_prop(folder, attach_part, role_id, faction.color)
	create_billboard(folder, attach_part, faction, role, rarity)
end

--[[
	Captures unmodified template stats before role modifiers.

	Args:
		model (Model): Unit whose base stats are captured.

	Returns:
		None.
]]
local function capture_role_bases(model: Model)
	local humanoid = get_humanoid(model)
	if humanoid and read_number_attr(model, ROLE_BASE_HEALTH) == nil then
		model:SetAttribute(ROLE_BASE_HEALTH, humanoid.MaxHealth)
		model:SetAttribute(ROLE_BASE_SPEED, humanoid.WalkSpeed)
	end

	local pairs_to_capture = {
		{ ROLE_BASE_DAMAGE, "Damage", 10 },
		{ ROLE_BASE_COOLDOWN, "AttackCooldown", 1 },
		{ ROLE_BASE_DEFENSE, "Defense", 0 },
		{ ROLE_BASE_COST, "CommandCost", 1 },
		{ ROLE_BASE_RANGE, "AttackRange", 0 },
		{ ROLE_BASE_PREFERRED, "PreferredRange", 0 },
	}
	for _, pair in ipairs(pairs_to_capture) do
		if read_number_attr(model, pair[1]) == nil then
			local value = read_number_attr(model, pair[2])
			model:SetAttribute(pair[1], value or pair[3])
		end
	end
end

--[[
	Applies one combat role from captured base stats.

	Args:
		model (Model): Unit receiving role mechanics.
		role (RoleDefinition): Role stat definition.

	Returns:
		None.
]]
local function apply_role_stats(
	model: Model,
	role: RoleDefinition
)
	capture_role_bases(model)

	local humanoid = get_humanoid(model)
	if humanoid then
		local base_health = read_number_attr(
			model,
			ROLE_BASE_HEALTH
		) or humanoid.MaxHealth
		local health_ratio = if humanoid.MaxHealth > 0
			then humanoid.Health / humanoid.MaxHealth
			else 1
		local max_health = math.max(
			1,
			math.floor(
				base_health * role.health_multiplier + 0.5
			)
		)
		humanoid.MaxHealth = max_health
		humanoid.Health = clamp(
			max_health * health_ratio,
			0,
			max_health
		)

		local base_speed = read_number_attr(
			model,
			ROLE_BASE_SPEED
		) or humanoid.WalkSpeed
		humanoid.WalkSpeed = base_speed * role.speed_multiplier
	end

	local base_damage = read_number_attr(
		model,
		ROLE_BASE_DAMAGE
	) or 10
	model:SetAttribute(
		"Damage",
		math.max(
			1,
			math.floor(base_damage * role.damage_multiplier + 0.5)
		)
	)

	local base_cooldown = read_number_attr(
		model,
		ROLE_BASE_COOLDOWN
	) or 1
	model:SetAttribute(
		"AttackCooldown",
		clamp(
			base_cooldown * role.cooldown_multiplier,
			0.2,
			6
		)
	)

	local base_defense = read_number_attr(
		model,
		ROLE_BASE_DEFENSE
	) or 0
	model:SetAttribute(
		"Defense",
		clamp(base_defense + role.defense_bonus, 0, 0.9)
	)

	local base_cost = read_number_attr(model, ROLE_BASE_COST) or 1
	model:SetAttribute(
		"CommandCost",
		math.max(
			math.floor(base_cost),
			role.min_command_cost
		)
	)

	model:SetAttribute("DefaultCohort", role.cohort)
	model:SetAttribute("Cohort", role.cohort)
	model:SetAttribute(
		"RoleSpeedMultiplier",
		role.speed_multiplier
	)

	if role.attack_range then
		model:SetAttribute("AttackRange", role.attack_range)
	else
		local base_range = read_number_attr(model, ROLE_BASE_RANGE) or 0
		model:SetAttribute(
			"AttackRange",
			if base_range > 0 then base_range else nil
		)
	end

	if role.preferred_range then
		model:SetAttribute("PreferredRange", role.preferred_range)
	else
		local base_preferred = read_number_attr(
			model,
			ROLE_BASE_PREFERRED
		) or 0
		model:SetAttribute(
			"PreferredRange",
			if base_preferred > 0 then base_preferred else nil
		)
	end

	model:SetAttribute("SupportHealAmount", role.support_heal)
	model:SetAttribute("SupportHealRadius", role.support_radius)
	model:SetAttribute(
		"SupportHealCooldown",
		role.support_cooldown
	)
end

--[[
	Picks a roster entry by weight.

	Args:
		roster ({ RosterEntry }): Faction roster.

	Returns:
		RosterEntry: Weighted roster entry.
]]
local function pick_weighted(
	roster: { RosterEntry }
): RosterEntry
	local total = 0
	for _, entry in ipairs(roster) do
		total += math.max(0, entry.weight)
	end

	local roll = math.random() * total
	local cursor = 0
	for _, entry in ipairs(roster) do
		cursor += math.max(0, entry.weight)
		if roll <= cursor then
			return entry
		end
	end
	return roster[#roster]
end

--[[
	Returns faction IDs in deterministic display order.

	Args:
		None.

	Returns:
		{ string }: Ordered faction identifiers.
]]
function FactionService.get_faction_ids(): { string }
	return table.clone(FACTION_ORDER)
end

--[[
	Returns one faction definition.

	Args:
		faction_id (string): Faction identifier.

	Returns:
		FactionDefinition?: Matching definition.
]]
function FactionService.get_definition(
	faction_id: string
): FactionDefinition?
	return FACTIONS[faction_id]
end

--[[
	Returns one combat role definition.

	Args:
		role_id (string): Role identifier.

	Returns:
		RoleDefinition?: Matching definition.
]]
function FactionService.get_role_definition(
	role_id: string
): RoleDefinition?
	return ROLE_DEFINITIONS[role_id]
end

--[[
	Checks whether two factions are enemies.

	Args:
		left_id (string?): First faction identifier.
		right_id (string?): Second faction identifier.

	Returns:
		boolean: True for two different known factions.
]]
function FactionService.is_hostile(
	left_id: string?,
	right_id: string?
): boolean
	return left_id ~= nil
		and right_id ~= nil
		and left_id ~= right_id
		and FACTIONS[left_id] ~= nil
		and FACTIONS[right_id] ~= nil
end

--[[
	Chooses a home faction from a map position.

	Args:
		position (Vector3): Spawn position.
		min_x (number): Map minimum X.
		max_x (number): Map maximum X.
		min_z (number): Map minimum Z.
		max_z (number): Map maximum Z.

	Returns:
		string: Faction identifier for the region.
]]
function FactionService.choose_faction_for_position(
	position: Vector3,
	min_x: number,
	max_x: number,
	min_z: number,
	max_z: number
): string
	local center_x = (min_x + max_x) * 0.5
	local center_z = (min_z + max_z) * 0.5
	local half_x = math.max(1, (max_x - min_x) * 0.5)
	local half_z = math.max(1, (max_z - min_z) * 0.5)
	local nx = (position.X - center_x) / half_x
	local nz = (position.Z - center_z) / half_z

	local west = nx < 0
	local north = nz < 0
	local primary: string
	if west and north then
		primary = "OssuaryLegion"
	elseif west then
		primary = "Mirebound"
	elseif north then
		primary = "AshenCovenant"
	else
		primary = "GraveCourt"
	end

	local in_contested_band = math.abs(nx) < 0.12
		or math.abs(nz) < 0.12
	if in_contested_band and math.random() < 0.4 then
		return FACTION_ORDER[math.random(1, #FACTION_ORDER)]
	end
	return primary
end

--[[
	Picks a faction-specific unit template and role.

	Args:
		faction_id (string): Faction identifier.

	Returns:
		RosterEntry?: Weighted roster entry.
]]
function FactionService.pick_roster_entry(
	faction_id: string
): RosterEntry?
	local faction = FACTIONS[faction_id]
	if not faction or #faction.roster == 0 then
		return nil
	end
	return pick_weighted(faction.roster)
end

--[[
	Applies faction identity, role mechanics and visuals.

	Args:
		model (Model): Unit receiving identity.
		faction_id (string): Faction identifier.
		role_id (string): Combat role identifier.
		rarity (string?): Optional rarity label.

	Returns:
		boolean: True when identity was applied.
]]
function FactionService.apply_identity(
	model: Model,
	faction_id: string,
	role_id: string,
	rarity: string?
): boolean
	local faction = FACTIONS[faction_id]
	local role = ROLE_DEFINITIONS[role_id]
	if not faction or not role then
		return false
	end

	local rarity_name = rarity or "Common"
	model:SetAttribute(ATTR_FACTION_ID, faction.id)
	model:SetAttribute(ATTR_FACTION_NAME, faction.display_name)
	model:SetAttribute(ATTR_COMBAT_ROLE, role_id)
	model:SetAttribute(
		ATTR_COMBAT_ROLE_NAME,
		role.display_name
	)
	model:SetAttribute(ATTR_FACTION_RARITY, rarity_name)
	model:SetAttribute(
		ATTR_FACTION_REGION,
		faction.region_name
	)

	apply_role_stats(model, role)
	apply_visual_identity(
		model,
		faction,
		role,
		role_id,
		rarity_name
	)
	return true
end

--[[
	Reapplies identity already stored on a model.

	Args:
		model (Model): Unit with faction attributes.

	Returns:
		boolean: True when stored identity was valid.
]]
function FactionService.restore_identity(model: Model): boolean
	local faction_id = read_string_attr(model, ATTR_FACTION_ID)
	local role_id = read_string_attr(model, ATTR_COMBAT_ROLE)
	if not faction_id or not role_id then
		return false
	end

	return FactionService.apply_identity(
		model,
		faction_id,
		role_id,
		read_string_attr(model, ATTR_FACTION_RARITY)
	)
end

--[[
	Copies faction identity from one unit to another.

	Args:
		source (Model): Existing faction unit.
		target (Model): Newly spawned unit.

	Returns:
		boolean: True when source identity was copied.
]]
function FactionService.copy_identity(
	source: Model,
	target: Model
): boolean
	local faction_id = read_string_attr(source, ATTR_FACTION_ID)
	local role_id = read_string_attr(source, ATTR_COMBAT_ROLE)
	if not faction_id or not role_id then
		return false
	end

	return FactionService.apply_identity(
		target,
		faction_id,
		role_id,
		read_string_attr(source, ATTR_FACTION_RARITY)
	)
end

--[[
	Returns a model faction identifier.

	Args:
		model (Model): Model to inspect.

	Returns:
		string?: Faction identifier when present.
]]
function FactionService.get_faction_id(model: Model): string?
	return read_string_attr(model, ATTR_FACTION_ID)
end

--[[
	Returns a model combat-role identifier.

	Args:
		model (Model): Model to inspect.

	Returns:
		string?: Combat-role identifier when present.
]]
function FactionService.get_role_id(model: Model): string?
	return read_string_attr(model, ATTR_COMBAT_ROLE)
end

return FactionService
