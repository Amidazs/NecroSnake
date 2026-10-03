--!strict

local NecromancerSkills = {}

export type SkillDefinition = {
	id: string,
	name: string,
	description: string,
	unlock_level: number,
	unlock_rebirth: number,
	reliquary_level: number,
	requires_skillbook: boolean,
	cooldown: number,
}

local DEFINITIONS: { SkillDefinition } = {
	{
		id = "BoneWall",
		name = "Bone Wall",
		description = "Raise a short-lived wall that blocks movement.",
		unlock_level = 10,
		unlock_rebirth = 0,
		reliquary_level = 1,
		requires_skillbook = false,
		cooldown = 18,
	},
	{
		id = "Regroup",
		name = "Regroup",
		description = "Pull your surviving army back around you.",
		unlock_level = 12,
		unlock_rebirth = 0,
		reliquary_level = 1,
		requires_skillbook = false,
		cooldown = 14,
	},
	{
		id = "FearPulse",
		name = "Fear Pulse",
		description = "Briefly disables nearby enemy units.",
		unlock_level = 15,
		unlock_rebirth = 0,
		reliquary_level = 1,
		requires_skillbook = false,
		cooldown = 22,
	},
	{
		id = "Rally",
		name = "Rally",
		description = "Temporarily increases your army's damage.",
		unlock_level = 20,
		unlock_rebirth = 0,
		reliquary_level = 2,
		requires_skillbook = true,
		cooldown = 24,
	},
	{
		id = "CorpseExplosion",
		name = "Corpse Explosion",
		description = "Consume a corpse to damage nearby enemies.",
		unlock_level = 25,
		unlock_rebirth = 0,
		reliquary_level = 2,
		requires_skillbook = true,
		cooldown = 20,
	},
	{
		id = "Sacrifice",
		name = "Sacrifice",
		description = "Destroy one undead to restore Necromancer health.",
		unlock_level = 30,
		unlock_rebirth = 0,
		reliquary_level = 3,
		requires_skillbook = true,
		cooldown = 28,
	},
	{
		id = "Frenzy",
		name = "Frenzy",
		description = "Prestige option: trade army health for damage.",
		unlock_level = 10,
		unlock_rebirth = 1,
		reliquary_level = 3,
		requires_skillbook = true,
		cooldown = 32,
	},
}

local BY_ID: { [string]: SkillDefinition } = {}

for _, definition in ipairs(DEFINITIONS) do
	BY_ID[definition.id] = definition
end

--[[
	Returns one immutable skill definition.

	Args:
		skill_id (string): Skill identifier.

	Returns:
		SkillDefinition?: Matching skill definition.
]]
function NecromancerSkills.get(
	skill_id: string
): SkillDefinition?
	return BY_ID[skill_id]
end

--[[
	Returns skill definitions in display order.

	Args:
		None.

	Returns:
		{ SkillDefinition }: Ordered skill definitions.
]]
function NecromancerSkills.get_all(): { SkillDefinition }
	return DEFINITIONS
end

--[[
	Returns only skills that require battlefield skillbooks.

	Args:
		None.

	Returns:
		{ SkillDefinition }: Skillbook-gated definitions.
]]
function NecromancerSkills.get_skillbook_skills(): { SkillDefinition }
	local result: { SkillDefinition } = {}
	for _, definition in ipairs(DEFINITIONS) do
		if definition.requires_skillbook then
			table.insert(result, definition)
		end
	end
	return result
end

--[[
	Checks level and Rebirth requirements only.

	Args:
		skill_id (string): Skill identifier.
		level (number): Current Necromancer level.
		rebirth_count (number): Completed Rebirth count.

	Returns:
		boolean: True when progression requirements are met.
]]
function NecromancerSkills.meets_progression(
	skill_id: string,
	level: number,
	rebirth_count: number
): boolean
	local definition = BY_ID[skill_id]
	if not definition then
		return false
	end

	return level >= definition.unlock_level
		and rebirth_count >= definition.unlock_rebirth
end

--[[
	Checks every learning requirement for one skill.

	Args:
		skill_id (string): Skill identifier.
		level (number): Current Necromancer level.
		rebirth_count (number): Completed Rebirth count.
		reliquary_level (number): Current Skill Reliquary level.
		has_skillbook (boolean): Whether the skillbook was learned.

	Returns:
		boolean: True when the skill can be equipped.
]]
function NecromancerSkills.is_unlocked(
	skill_id: string,
	level: number,
	rebirth_count: number,
	reliquary_level: number?,
	has_skillbook: boolean?
): boolean
	local definition = BY_ID[skill_id]
	if not definition then
		return false
	end
	if not NecromancerSkills.meets_progression(
		skill_id,
		level,
		rebirth_count
	) then
		return false
	end

	local reliquary = reliquary_level or 1
	if reliquary < definition.reliquary_level then
		return false
	end
	if definition.requires_skillbook and has_skillbook ~= true then
		return false
	end
	return true
end

return NecromancerSkills
