--!strict

local CodexKnowledgeConfig = {}

export type Milestone = {
	raise_count: number,
	defense_bonus: number,
}

local MAX_MILESTONES_BY_CODEX_LEVEL = {
	[1] = 1,
	[2] = 3,
	[3] = 4,
}

local MILESTONES: { Milestone } = {
	{
		raise_count = 5,
		defense_bonus = 0.01,
	},
	{
		raise_count = 15,
		defense_bonus = 0.03,
	},
	{
		raise_count = 30,
		defense_bonus = 0.05,
	},
	{
		raise_count = 60,
		defense_bonus = 0.07,
	},
}

--[[
	Returns the active defence bonus for a Raise count.

	Args:
		raise_count (number): Successful Raises for one template.

	Returns:
		number: Additive defence bonus from zero to 0.07.
]]
function CodexKnowledgeConfig.get_defense_bonus(
	raise_count: number,
	codex_level: number?
): number
	local safe_level = math.clamp(
		math.floor(codex_level or 3),
		1,
		3
	)
	local max_milestones =
		MAX_MILESTONES_BY_CODEX_LEVEL[safe_level]
	local bonus = 0

	for index, milestone in ipairs(MILESTONES) do
		if index > max_milestones
			or raise_count < milestone.raise_count
		then
			break
		end
		bonus = milestone.defense_bonus
	end
	return bonus
end

--[[
	Returns the next Codex milestone after a Raise count.

	Args:
		raise_count (number): Successful Raises for one template.

	Returns:
		Milestone?: Next milestone, or nil when complete.
]]
function CodexKnowledgeConfig.get_next_milestone(
	raise_count: number,
	codex_level: number?
): Milestone?
	local safe_level = math.clamp(
		math.floor(codex_level or 3),
		1,
		3
	)
	local max_milestones =
		MAX_MILESTONES_BY_CODEX_LEVEL[safe_level]

	for index, milestone in ipairs(MILESTONES) do
		if index > max_milestones then
			break
		end
		if raise_count < milestone.raise_count then
			return milestone
		end
	end
	return nil
end

--[[
	Returns milestone definitions in progression order.

	Args:
		None.

	Returns:
		{ Milestone }: Ordered milestone list.
]]
function CodexKnowledgeConfig.get_milestones(): { Milestone }
	return table.clone(MILESTONES)
end

return CodexKnowledgeConfig
