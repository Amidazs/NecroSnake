--!strict

local NecromancerSkills = {}

export type SkillDefinition = {
	id: string,
	name: string,
	description: string,
	unlock_level: number,
	unlock_rebirth: number,
	cooldown: number,
}

local DEFINITIONS: { SkillDefinition } = {
	{
		id = "BoneWall",
		name = "Bone Wall",
		description = "Raise a short-lived wall that blocks movement.",
		unlock_level = 10,
		unlock_rebirth = 0,
		cooldown = 18,
	},
	{
		id = "Regroup",
		name = "Regroup",
		description = "Pull your surviving army back around you.",
		unlock_level = 12,
		unlock_rebirth = 0,
		cooldown = 14,
	},
	{
		id = "FearPulse",
		name = "Fear Pulse",
		description = "Briefly disables nearby enemy units.",
		unlock_level = 15,
		unlock_rebirth = 0,
		cooldown = 22,
	},
	{
		id = "Rally",
		name = "Rally",
		description = "Temporarily increases your army's damage.",
		unlock_level = 20,
		unlock_rebirth = 0,
		cooldown = 24,
	},
	{
		id = "CorpseExplosion",
		name = "Corpse Explosion",
		description = "Consume a corpse to damage nearby enemies.",
		unlock_level = 25,
		unlock_rebirth = 0,
		cooldown = 20,
	},
	{
		id = "Sacrifice",
		name = "Sacrifice",
		description = "Destroy one undead to restore Necromancer health.",
		unlock_level = 30,
		unlock_rebirth = 0,
		cooldown = 28,
	},
	{
		id = "Frenzy",
		name = "Frenzy",
		description = "Prestige option: trade army health for damage.",
		unlock_level = 10,
		unlock_rebirth = 1,
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
	Checks whether progression has unlocked a skill.

	Args:
		skill_id (string): Skill identifier.
		level (number): Current Necromancer level.
		rebirth_count (number): Completed Rebirth count.

	Returns:
		boolean: True when the skill is available.
]]
function NecromancerSkills.is_unlocked(
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

return NecromancerSkills
