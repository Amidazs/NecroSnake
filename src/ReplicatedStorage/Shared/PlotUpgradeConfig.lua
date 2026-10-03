--!strict

local PlotUpgradeConfig = {}

local MAX_LEVEL = 3

local FACILITY_ORDER = {
	"Plot",
	"SoulFoundry",
	"Formation",
	"SkillReliquary",
	"Codex",
	"MasterGallery",
	"TrophyHall",
	"UpgradeForge",
}

local DEFINITIONS = {
	Plot = {
		name = "Sanctum Plot",
		costs = {
			[2] = 150,
			[3] = 400,
		},
	},
	SoulFoundry = {
		name = "Soul Foundry",
		costs = {
			[2] = 100,
			[3] = 250,
		},
	},
	Formation = {
		name = "Formation War Room",
		costs = {
			[2] = 90,
			[3] = 210,
		},
	},
	SkillReliquary = {
		name = "Skill Reliquary",
		costs = {
			[2] = 110,
			[3] = 260,
		},
	},
	Codex = {
		name = "Necromancer Codex",
		costs = {
			[2] = 80,
			[3] = 190,
		},
	},
	MasterGallery = {
		name = "Master Gallery",
		costs = {
			[2] = 120,
			[3] = 300,
		},
	},
	TrophyHall = {
		name = "Boss Trophy Hall",
		costs = {
			[2] = 90,
			[3] = 220,
		},
	},
	UpgradeForge = {
		name = "Foundry Upgrade Forge",
		costs = {
			[2] = 140,
			[3] = 360,
		},
	},
}

local COMMAND_RANGE_BY_LEVEL = {
	[1] = 120,
	[2] = 140,
	[3] = 160,
}

local SKILL_COOLDOWN_BY_LEVEL = {
	[1] = 1,
	[2] = 0.95,
	[3] = 0.90,
}

local DISSOLVE_MULTIPLIER_BY_LEVEL = {
	[1] = 1,
	[2] = 1.10,
	[3] = 1.20,
}

local MASTER_CAPACITY_BY_LEVEL = {
	[1] = 6,
	[2] = 10,
	[3] = 14,
}

local TROPHY_SLOTS_BY_LEVEL = {
	[1] = 4,
	[2] = 6,
	[3] = 8,
}

local FORGE_DISCOUNT_BY_LEVEL = {
	[1] = 0,
	[2] = 0.05,
	[3] = 0.10,
}

--[[
	Clamps a facility level to the supported progression range.

	Args:
		level (number): Raw facility level.

	Returns:
		number: Level from one to MAX_LEVEL.
]]
local function clamp_level(level: number): number
	return math.clamp(math.floor(level), 1, MAX_LEVEL)
end

--[[
	Returns the ordered facility identifiers shown by the Upgrade Forge.

	Args:
		None.

	Returns:
		{ string }: Stable facility order.
]]
function PlotUpgradeConfig.get_facility_order(): { string }
	return table.clone(FACILITY_ORDER)
end

--[[
	Returns whether an identifier belongs to a plot facility.

	Args:
		facility_id (string): Facility identifier.

	Returns:
		boolean: True when the facility is defined.
]]
function PlotUpgradeConfig.is_valid_facility(
	facility_id: string
): boolean
	return DEFINITIONS[facility_id] ~= nil
end

--[[
	Returns the user-facing facility name.

	Args:
		facility_id (string): Facility identifier.

	Returns:
		string: Display name, or the identifier when unknown.
]]
function PlotUpgradeConfig.get_name(
	facility_id: string
): string
	local definition = DEFINITIONS[facility_id]
	if definition then
		return definition.name
	end
	return facility_id
end

--[[
	Returns the maximum supported facility level.

	Args:
		None.

	Returns:
		number: Maximum facility level.
]]
function PlotUpgradeConfig.get_max_level(): number
	return MAX_LEVEL
end

--[[
	Returns the Forge discount at one facility level.

	Args:
		level (number): Upgrade Forge level.

	Returns:
		number: Fractional discount from zero to one.
]]
function PlotUpgradeConfig.get_forge_discount(
	level: number
): number
	return FORGE_DISCOUNT_BY_LEVEL[clamp_level(level)]
end

--[[
	Applies the current Forge discount to an upgrade cost.

	Args:
		base_cost (number): Undiscounted Soul Essence cost.
		forge_level (number): Upgrade Forge level.

	Returns:
		number: Rounded discounted Soul Essence cost.
]]
function PlotUpgradeConfig.apply_forge_discount(
	base_cost: number,
	forge_level: number
): number
	local discount = PlotUpgradeConfig.get_forge_discount(
		forge_level
	)
	return math.max(
		0,
		math.floor(base_cost * (1 - discount) + 0.5)
	)
end

--[[
	Returns the next-level facility cost.

	The Forge does not discount its own upgrade. Plot and all other
	facilities use the current Forge discount.

	Args:
		facility_id (string): Facility identifier.
		current_level (number): Current facility level.
		forge_level (number): Current Upgrade Forge level.

	Returns:
		number?: Soul Essence cost, or nil at maximum level.
]]
function PlotUpgradeConfig.get_upgrade_cost(
	facility_id: string,
	current_level: number,
	forge_level: number
): number?
	local definition = DEFINITIONS[facility_id]
	if not definition then
		return nil
	end

	local next_level = clamp_level(current_level) + 1
	if next_level > MAX_LEVEL then
		return nil
	end

	local base_cost = definition.costs[next_level]
	if not base_cost then
		return nil
	end

	if facility_id == "UpgradeForge" then
		return base_cost
	end
	return PlotUpgradeConfig.apply_forge_discount(
		base_cost,
		forge_level
	)
end

--[[
	Returns the army command range granted by Formation level.

	Args:
		level (number): Formation War Room level.

	Returns:
		number: Maximum command distance in studs.
]]
function PlotUpgradeConfig.get_command_range(
	level: number
): number
	return COMMAND_RANGE_BY_LEVEL[clamp_level(level)]
end

--[[
	Returns the skill cooldown multiplier granted by Reliquary level.

	Args:
		level (number): Skill Reliquary level.

	Returns:
		number: Multiplier applied to skill cooldown durations.
]]
function PlotUpgradeConfig.get_skill_cooldown_multiplier(
	level: number
): number
	return SKILL_COOLDOWN_BY_LEVEL[clamp_level(level)]
end

--[[
	Returns the Soul Essence dissolve multiplier from Codex level.

	Args:
		level (number): Necromancer Codex level.

	Returns:
		number: Multiplier applied to dissolve yield.
]]
function PlotUpgradeConfig.get_dissolve_multiplier(
	level: number
): number
	return DISSOLVE_MULTIPLIER_BY_LEVEL[clamp_level(level)]
end

--[[
	Returns the stored Master capacity for Gallery level.

	Args:
		level (number): Master Gallery level.

	Returns:
		number: Maximum safely stored Masters.
]]
function PlotUpgradeConfig.get_master_capacity(
	level: number
): number
	return MASTER_CAPACITY_BY_LEVEL[clamp_level(level)]
end

--[[
	Returns the physical boss-display capacity for Trophy Hall level.

	Args:
		level (number): Boss Trophy Hall level.

	Returns:
		number: Unlocked trophy plinth count.
]]
function PlotUpgradeConfig.get_trophy_slots(
	level: number
): number
	return TROPHY_SLOTS_BY_LEVEL[clamp_level(level)]
end

--[[
	Returns a concise user-facing benefit summary.

	Args:
		facility_id (string): Facility identifier.
		level (number): Facility level being described.

	Returns:
		string: Description of the active benefit.
]]
function PlotUpgradeConfig.get_effect_text(
	facility_id: string,
	level: number
): string
	local safe_level = clamp_level(level)

	if facility_id == "Plot" then
		return ("Facility level cap: %d"):format(safe_level)
	elseif facility_id == "SoulFoundry" then
		return ("%d cloning machine(s)"):format(safe_level)
	elseif facility_id == "Formation" then
		return ("%d stud command range"):format(
			PlotUpgradeConfig.get_command_range(safe_level)
		)
	elseif facility_id == "SkillReliquary" then
		local multiplier =
			PlotUpgradeConfig.get_skill_cooldown_multiplier(
				safe_level
			)
		local reduction = math.floor(
			(1 - multiplier) * 100 + 0.5
		)
		return ("%d%% skill cooldown reduction"):format(
			reduction
		)
	elseif facility_id == "Codex" then
		local multiplier =
			PlotUpgradeConfig.get_dissolve_multiplier(
				safe_level
			)
		local bonus = math.floor(
			(multiplier - 1) * 100 + 0.5
		)
		return ("%d%% extra dissolve Essence"):format(bonus)
	elseif facility_id == "MasterGallery" then
		return ("%d stored Masters"):format(
			PlotUpgradeConfig.get_master_capacity(safe_level)
		)
	elseif facility_id == "TrophyHall" then
		return ("%d boss trophy displays"):format(
			PlotUpgradeConfig.get_trophy_slots(safe_level)
		)
	elseif facility_id == "UpgradeForge" then
		local discount = math.floor(
			PlotUpgradeConfig.get_forge_discount(safe_level)
				* 100
				+ 0.5
		)
		return ("%d%% upgrade discount"):format(discount)
	end

	return "Unknown facility."
end

return PlotUpgradeConfig
