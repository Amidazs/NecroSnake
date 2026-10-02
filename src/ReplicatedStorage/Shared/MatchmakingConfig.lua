--!strict

local MatchmakingConfig = {}

MatchmakingConfig.TARGET_ARENA_PLAYERS = 8
MatchmakingConfig.PARTY_MAX_SIZE = 4
MatchmakingConfig.NORMAL_HOP_COOLDOWN_SECONDS = 45
MatchmakingConfig.FRIEND_HOP_COOLDOWN_SECONDS = 15
MatchmakingConfig.SERVER_HEARTBEAT_SECONDS = 15
MatchmakingConfig.SERVER_TTL_SECONDS = 60

export type StrengthInputs = {
	command_capacity: number,
	rebirth_count: number,
	loadout_cost: number,
	equipped_skill_count: number,
}

export type BandDefinition = {
	id: string,
	name: string,
	max_score: number,
}

local BANDS: { BandDefinition } = {
	{
		id = "Initiate",
		name = "Initiate",
		max_score = 17,
	},
	{
		id = "Adept",
		name = "Adept",
		max_score = 34,
	},
	{
		id = "Veteran",
		name = "Veteran",
		max_score = 54,
	},
	{
		id = "Ascendant",
		name = "Ascendant",
		max_score = math.huge,
	},
}

--[[
	Calculates a comparable matchmaking strength score.

	Args:
		inputs (StrengthInputs): Progression and selected-army values.

	Returns:
		number: Rounded non-negative strength score.
]]
function MatchmakingConfig.calculate_strength(
	inputs: StrengthInputs
): number
	local capacity = math.max(0, inputs.command_capacity)
	local rebirths = math.max(0, inputs.rebirth_count)
	local loadout = math.max(0, inputs.loadout_cost)
	local skills = math.max(0, inputs.equipped_skill_count)

	local loadout_component = math.min(loadout, capacity) * 0.5
	local raw_score = capacity
		+ rebirths * 4
		+ loadout_component
		+ skills * 2

	return math.max(0, math.floor(raw_score + 0.5))
end

--[[
	Returns the matchmaking band for a strength score.

	Args:
		score (number): Calculated player or party strength.

	Returns:
		BandDefinition: Matching band definition.
]]
function MatchmakingConfig.get_band(
	score: number
): BandDefinition
	local safe_score = math.max(0, score)
	for _, band in ipairs(BANDS) do
		if safe_score <= band.max_score then
			return band
		end
	end
	return BANDS[#BANDS]
end

--[[
	Returns a safe copy of all matchmaking bands.

	Args:
		None.

	Returns:
		{ BandDefinition }: Ordered band definitions.
]]
function MatchmakingConfig.get_bands(): { BandDefinition }
	local result: { BandDefinition } = {}
	for _, band in ipairs(BANDS) do
		table.insert(result, {
			id = band.id,
			name = band.name,
			max_score = band.max_score,
		})
	end
	return result
end

return MatchmakingConfig
