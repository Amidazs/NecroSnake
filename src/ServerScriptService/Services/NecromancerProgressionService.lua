--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)
local NecromancerSkills = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("NecromancerSkills")
)

local NecromancerProgressionService = {}

local MAX_LEVEL = 30
local BASE_COMMAND_CAPACITY = 5
local REBIRTH_CAPACITY_BONUS = 2
local MAX_REBIRTH_CAPACITY_BONUS = 10
local MAX_RAISE_LEVEL_BONUS = 0.09
local MAX_RAISE_PRACTICE_BONUS = 0.04
local MAX_RAISE_REBIRTH_BONUS = 0.02
local MAX_RAISE_REACH_BONUS = 5

local soul_collection_service = nil :: any
local did_start = false

type ProgressionState = {
	xp: number,
	level: number,
	rebirth_count: number,
	prestige_marks: number,
	raise_successes: number,
	equipped_skills: { string },
}

--[[
	Returns the XP required to advance one level.

	Args:
		level (number): Current Necromancer level.

	Returns:
		number: XP required for the next level.
]]
local function xp_to_next(level: number): number
	return 80 + (math.max(1, level) - 1) * 45
end

--[[
	Returns active skill slots unlocked by level.

	Args:
		level (number): Current Necromancer level.

	Returns:
		number: Number of usable slots from zero to three.
]]
local function skill_slot_count(level: number): number
	if level >= 30 then
		return 3
	elseif level >= 20 then
		return 2
	elseif level >= 10 then
		return 1
	end
	return 0
end

--[[
	Calculates Command Capacity from level and Rebirth.

	Args:
		level (number): Current Necromancer level.
		rebirth_count (number): Completed Rebirth count.

	Returns:
		number: Maximum weighted Command Capacity.
]]
local function command_capacity(
	level: number,
	rebirth_count: number
): number
	local level_bonus = math.floor((math.max(1, level) - 1) * 1.4)
	local rebirth_bonus = math.min(
		MAX_REBIRTH_CAPACITY_BONUS,
		math.max(0, rebirth_count) * REBIRTH_CAPACITY_BONUS
	)
	return BASE_COMMAND_CAPACITY + level_bonus + rebirth_bonus
end

--[[
	Calculates the progression Raise chance bonus.

	Args:
		state (ProgressionState): Current progression state.

	Returns:
		number: Additive Raise chance bonus.
]]
local function raise_chance_bonus(
	state: ProgressionState
): number
	local level_ratio = math.clamp(
		(state.level - 1) / math.max(1, MAX_LEVEL - 1),
		0,
		1
	)
	local level_bonus = level_ratio * MAX_RAISE_LEVEL_BONUS
	local practice_bonus = math.min(
		MAX_RAISE_PRACTICE_BONUS,
		state.raise_successes * 0.0004
	)
	local rebirth_bonus = math.min(
		MAX_RAISE_REBIRTH_BONUS,
		state.rebirth_count * 0.004
	)
	return level_bonus + practice_bonus + rebirth_bonus
end

--[[
	Calculates extra server-validated Raise reach.

	Args:
		level (number): Current Necromancer level.

	Returns:
		number: Additional studs of Raise reach.
]]
local function raise_reach_bonus(level: number): number
	local tiers = math.floor((math.max(1, level) - 1) / 6)
	return math.min(MAX_RAISE_REACH_BONUS, tiers * 1.25)
end

--[[
	Calculates local channel-time scaling.

	Args:
		level (number): Current Necromancer level.

	Returns:
		number: Multiplier applied to Raise channel duration.
]]
local function raise_channel_multiplier(level: number): number
	local tiers = math.floor((math.max(1, level) - 1) / 5)
	return math.max(0.72, 1 - tiers * 0.04)
end

--[[
	Fetches the persistent progression state.

	Args:
		player (Player): Player whose state is requested.

	Returns:
		ProgressionState?: State when the Soul profile is loaded.
]]
local function get_state(player: Player): ProgressionState?
	if not soul_collection_service then
		return nil
	end
	return soul_collection_service.get_progression_state(player)
end

--[[
	Stores a changed progression state.

	Args:
		player (Player): Player whose state changed.
		state (ProgressionState): Updated progression state.

	Returns:
		boolean: True when the profile accepted the update.
]]
local function commit_state(
	player: Player,
	state: ProgressionState
): boolean
	if not soul_collection_service then
		return false
	end
	return soul_collection_service.commit_progression_state(
		player,
		state
	)
end

--[[
	Removes equipped skills that are no longer usable.

	Args:
		state (ProgressionState): Mutable progression state.

	Returns:
		boolean: True when the loadout changed.
]]
local function sanitize_equipped(
	state: ProgressionState
): boolean
	local allowed_slots = skill_slot_count(state.level)
	local sanitized: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, skill_id in ipairs(state.equipped_skills) do
		if #sanitized >= allowed_slots then
			break
		end
		if not seen[skill_id]
			and NecromancerSkills.is_unlocked(
				skill_id,
				state.level,
				state.rebirth_count
			)
		then
			seen[skill_id] = true
			table.insert(sanitized, skill_id)
		end
	end

	local changed = #sanitized ~= #state.equipped_skills
	if not changed then
		for index, skill_id in ipairs(sanitized) do
			if state.equipped_skills[index] ~= skill_id then
				changed = true
				break
			end
		end
	end

	state.equipped_skills = sanitized
	return changed
end

--[[
	Applies derived progression values as replicated attributes.

	Args:
		player (Player): Player receiving progression attributes.
		state (ProgressionState): Current persistent state.

	Returns:
		None.
]]
local function apply_attributes(
	player: Player,
	state: ProgressionState
)
	player:SetAttribute("NecromancerXP", state.xp)
	player:SetAttribute("NecromancerLevel", state.level)
	player:SetAttribute("RebirthCount", state.rebirth_count)
	player:SetAttribute("PrestigeMarks", state.prestige_marks)
	player:SetAttribute("RaiseSuccesses", state.raise_successes)
	player:SetAttribute(
		"CommandCapacity",
		command_capacity(state.level, state.rebirth_count)
	)
	player:SetAttribute(
		"RaiseChanceBonus",
		raise_chance_bonus(state)
	)
	player:SetAttribute(
		"RaiseReachBonus",
		raise_reach_bonus(state.level)
	)
	player:SetAttribute(
		"RaiseChannelMultiplier",
		raise_channel_multiplier(state.level)
	)
	player:SetAttribute(
		"SkillSlotCount",
		skill_slot_count(state.level)
	)
	player:SetAttribute(
		"NextLevelXP",
		if state.level < MAX_LEVEL
			then xp_to_next(state.level)
			else 0
	)

	for slot = 1, 3 do
		player:SetAttribute(
			("EquippedSkill%d"):format(slot),
			state.equipped_skills[slot] or ""
		)
	end
end

--[[
	Builds the client progression payload.

	Args:
		player (Player): Player requesting progression data.
		state (ProgressionState): Current persistent state.

	Returns:
		table: Client-safe progression snapshot.
]]
local function client_snapshot(
	player: Player,
	state: ProgressionState
)
	local catalog = {}
	for _, definition in ipairs(NecromancerSkills.get_all()) do
		table.insert(catalog, {
			id = definition.id,
			name = definition.name,
			description = definition.description,
			unlockLevel = definition.unlock_level,
			unlockRebirth = definition.unlock_rebirth,
			cooldown = definition.cooldown,
			unlocked = NecromancerSkills.is_unlocked(
				definition.id,
				state.level,
				state.rebirth_count
			),
		})
	end

	return {
		kind = "SNAPSHOT",
		level = state.level,
		xp = state.xp,
		nextLevelXp = if state.level < MAX_LEVEL
			then xp_to_next(state.level)
			else 0,
		maxLevel = MAX_LEVEL,
		rebirthCount = state.rebirth_count,
		prestigeMarks = state.prestige_marks,
		raiseSuccesses = state.raise_successes,
		commandCapacity = command_capacity(
			state.level,
			state.rebirth_count
		),
		raiseChanceBonus = raise_chance_bonus(state),
		raiseReachBonus = raise_reach_bonus(state.level),
		raiseChannelMultiplier = raise_channel_multiplier(
			state.level
		),
		skillSlots = skill_slot_count(state.level),
		equippedSkills = table.clone(state.equipped_skills),
		canRebirth = state.level >= MAX_LEVEL,
		inBase = soul_collection_service
			and soul_collection_service.is_player_in_safe_zone(
				player
			)
			or false,
		skills = catalog,
	}
end

--[[
	Sends current progression to one client.

	Args:
		player (Player): Recipient.

	Returns:
		None.
]]
local function send_snapshot(player: Player)
	local state = get_state(player)
	if not state then
		return
	end
	Remotes.progression():FireClient(
		player,
		client_snapshot(player, state)
	)
end

--[[
	Sends a progression action result.

	Args:
		player (Player): Recipient.
		ok (boolean): Whether the action succeeded.
		message (string): User-facing result.

	Returns:
		None.
]]
local function send_result(
	player: Player,
	ok: boolean,
	message: string
)
	Remotes.progression():FireClient(player, {
		kind = "RESULT",
		ok = ok,
		message = message,
	})
end

--[[
	Normalizes XP and performs level-ups.

	Args:
		state (ProgressionState): Mutable progression state.

	Returns:
		number: Number of levels gained.
]]
local function apply_level_ups(
	state: ProgressionState
): number
	local gained = 0

	while state.level < MAX_LEVEL do
		local needed = xp_to_next(state.level)
		if state.xp < needed then
			break
		end
		state.xp -= needed
		state.level += 1
		gained += 1
	end

	if state.level >= MAX_LEVEL then
		state.level = MAX_LEVEL
		state.xp = 0
	end

	sanitize_equipped(state)
	return gained
end

--[[
	Handles a client loadout request.

	Args:
		player (Player): Player changing the loadout.
		payload (any): Expected to contain a skills array.

	Returns:
		None.
]]
local function handle_set_loadout(
	player: Player,
	payload: any
)
	local state = get_state(player)
	if not state then
		send_result(player, false, "Progression is still loading.")
		return
	end

	if not soul_collection_service.is_player_in_safe_zone(player) then
		send_result(
			player,
			false,
			"Necromancer skills can only be changed at the Base."
		)
		return
	end

	local requested = if typeof(payload) == "table"
		then payload.skills
		else nil
	if typeof(requested) ~= "table" then
		send_result(player, false, "Invalid skill loadout.")
		return
	end

	local slots = skill_slot_count(state.level)
	local sanitized: { string } = {}
	local seen: { [string]: boolean } = {}

	for _, skill_id in ipairs(requested) do
		if #sanitized >= slots then
			break
		end
		if typeof(skill_id) ~= "string"
			or seen[skill_id]
			or not NecromancerSkills.is_unlocked(
				skill_id,
				state.level,
				state.rebirth_count
			)
		then
			send_result(player, false, "Loadout contains a locked skill.")
			return
		end
		seen[skill_id] = true
		table.insert(sanitized, skill_id)
	end

	state.equipped_skills = sanitized
	commit_state(player, state)
	apply_attributes(player, state)
	send_snapshot(player)
	send_result(player, true, "Necromancer skill loadout updated.")
end

--[[
	Handles a Rebirth request.

	Args:
		player (Player): Player requesting Rebirth.

	Returns:
		None.
]]
local function handle_rebirth(player: Player)
	local state = get_state(player)
	if not state then
		send_result(player, false, "Progression is still loading.")
		return
	end

	if not soul_collection_service.is_player_in_safe_zone(player) then
		send_result(player, false, "Rebirth is only possible at the Base.")
		return
	end
	if state.level < MAX_LEVEL then
		send_result(
			player,
			false,
			("Reach level %d before Rebirth."):format(MAX_LEVEL)
		)
		return
	end

	state.level = 1
	state.xp = 0
	state.rebirth_count += 1
	state.prestige_marks += 1
	state.raise_successes = 0
	state.equipped_skills = {}

	commit_state(player, state)
	apply_attributes(player, state)
	send_snapshot(player)
	send_result(
		player,
		true,
		"Rebirth complete. You gained 1 Prestige Mark."
	)
end
--[[
	Handles progression RemoteEvent requests.

	Args:
		player (Player): Requesting player.
		action (any): Action identifier.
		payload (any): Optional request data.

	Returns:
		None.
]]
local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action == "REQUEST" then
		send_snapshot(player)
	elseif action == "SET_LOADOUT" then
		handle_set_loadout(player, payload)
	elseif action == "REBIRTH" then
		handle_rebirth(player)
	end
end

--[[
	Loads replicated attributes once the Soul profile is ready.

	Args:
		player (Player): Player whose profile became available.

	Returns:
		None.
]]
local function apply_loaded_profile(player: Player)
	local state = get_state(player)
	if not state then
		return
	end

	local changed = sanitize_equipped(state)
	if changed then
		commit_state(player, state)
	end
	apply_attributes(player, state)
	send_snapshot(player)
end
--[[
	Hooks progression initialization for a player.

	Args:
		player (Player): Player to initialize.

	Returns:
		None.
]]
local function hook_player(player: Player)
	player:GetAttributeChangedSignal(
		"SoulProfileLoaded"
	):Connect(function()
		if player:GetAttribute("SoulProfileLoaded") == true then
			apply_loaded_profile(player)
		end
	end)

	if player:GetAttribute("SoulProfileLoaded") == true then
		task.defer(apply_loaded_profile, player)
	end
end

--[[
	Initializes service dependencies.

	Args:
		soul_collection_ref (any): Persistent profile service.

	Returns:
		None.
]]
function NecromancerProgressionService.init(
	soul_collection_ref: any
)
	soul_collection_service = soul_collection_ref
end

--[[
	Starts player and remote listeners.

	Args:
		None.

	Returns:
		None.
]]
function NecromancerProgressionService.start()
	if did_start then
		return
	end
	did_start = true

	Remotes.progression().OnServerEvent:Connect(handle_remote)
	Players.PlayerAdded:Connect(hook_player)

	for _, player in ipairs(Players:GetPlayers()) do
		hook_player(player)
	end
end
--[[
	Returns current progression for trusted server systems.

	Args:
		player (Player): Player to inspect.

	Returns:
		ProgressionState?: Current persistent state.
]]
function NecromancerProgressionService.get_state(
	player: Player
): ProgressionState?
	return get_state(player)
end

--[[
	Returns the current number of usable skill slots.

	Args:
		player (Player): Player to inspect.

	Returns:
		number: Zero to three skill slots.
]]
function NecromancerProgressionService.get_skill_slot_count(
	player: Player
): number
	local state = get_state(player)
	if not state then
		return 0
	end
	return skill_slot_count(state.level)
end

--[[
	Checks whether one skill is equipped.

	Args:
		player (Player): Player to inspect.
		skill_id (string): Skill identifier.

	Returns:
		boolean: True when equipped.
]]
function NecromancerProgressionService.is_skill_equipped(
	player: Player,
	skill_id: string
): boolean
	local state = get_state(player)
	if not state then
		return false
	end
	return table.find(state.equipped_skills, skill_id) ~= nil
end
--[[
	Grants progression XP and handles level-ups.

	Args:
		player (Player): Player receiving XP.
		amount (number): Non-negative XP amount.
		reason (string): Diagnostic reason.

	Returns:
		number: Number of levels gained.
]]
function NecromancerProgressionService.award_xp(
	player: Player,
	amount: number,
	reason: string
): number
	local state = get_state(player)
	if not state or amount <= 0 or state.level >= MAX_LEVEL then
		return 0
	end

	state.xp += math.max(0, math.floor(amount))
	local gained = apply_level_ups(state)
	commit_state(player, state)
	apply_attributes(player, state)
	send_snapshot(player)

	if gained > 0 then
		print(
			("[Progression] %s gained %d level(s) from %s.")
				:format(player.Name, gained, reason)
		)
	end
	return gained
end

--[[
	Records a successful Raise and grants proficiency XP.

	Args:
		player (Player): Necromancer who Raised the unit.
		command_cost (number): Weighted cost of the Raised unit.

	Returns:
		None.
]]
function NecromancerProgressionService.record_raise_success(
	player: Player,
	command_cost: number
)
	local state = get_state(player)
	if not state then
		return
	end

	state.raise_successes += 1
	commit_state(player, state)
	apply_attributes(player, state)

	NecromancerProgressionService.award_xp(
		player,
		20 + math.max(1, math.floor(command_cost)) * 6,
		"Raise"
	)
end
--[[
	Records a unit kill for progression.

	Args:
		player (Player): Owner credited with the kill.
		command_cost (number): Weighted cost of the defeated unit.
		is_pvp (boolean): Whether the victim belonged to a player.

	Returns:
		None.
]]
function NecromancerProgressionService.record_unit_kill(
	player: Player,
	command_cost: number,
	is_pvp: boolean
)
	local base_xp = if is_pvp then 14 else 8
	NecromancerProgressionService.award_xp(
		player,
		base_xp + math.max(1, math.floor(command_cost)) * 3,
		if is_pvp then "PvP unit kill" else "NPC unit kill"
	)
end

--[[
	Records a defeated enemy Necromancer.

	Args:
		player (Player): Killer receiving progression XP.

	Returns:
		None.
]]
function NecromancerProgressionService.record_necromancer_kill(
	player: Player
)
	NecromancerProgressionService.award_xp(
		player,
		60,
		"Necromancer kill"
	)
end

--[[
	Returns Raise channel scaling for server/client tests.

	Args:
		player (Player): Player to inspect.

	Returns:
		number: Channel duration multiplier.
]]
function NecromancerProgressionService.get_raise_channel_multiplier(
	player: Player
): number
	local state = get_state(player)
	if not state then
		return 1
	end
	return raise_channel_multiplier(state.level)
end
--[[
	Sets deterministic progression in Studio acceptance tests.

	Args:
		player (Player): Test player.
		level (number): Desired level.
		rebirth_count (number): Desired Rebirth count.
		raise_successes (number): Desired Raise-success count.

	Returns:
		boolean: True when the state was changed.
]]
function NecromancerProgressionService.debug_set_progression(
	player: Player,
	level: number,
	rebirth_count: number,
	raise_successes: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local state = get_state(player)
	if not state then
		return false
	end

	state.level = math.clamp(
		math.floor(level),
		1,
		MAX_LEVEL
	)
	state.xp = 0
	state.rebirth_count = math.max(
		0,
		math.floor(rebirth_count)
	)
	state.prestige_marks = state.rebirth_count
	state.raise_successes = math.max(
		0,
		math.floor(raise_successes)
	)
	sanitize_equipped(state)
	commit_state(player, state)
	apply_attributes(player, state)
	send_snapshot(player)
	return true
end

return NecromancerProgressionService
