--!strict

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local RobloxTeleportService = game:GetService("TeleportService")

local MatchmakingConfig = require(
	ReplicatedStorage.Shared.MatchmakingConfig
)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MatchmakingService = {}

local SERVER_MAP_NAME = "NecroSnakeArenaServers_v1"
local HOP_MAP_NAME = "NecroSnakeArenaHops_v1"
local SERVER_QUERY_LIMIT = 50

local party_service = nil :: any
local backpack_service = nil :: any
local soul_collection_service = nil :: any
local pvp_service = nil :: any

local did_start = false
local heartbeat_task: thread? = nil
local current_server_key: string? = nil
local current_access_code: string? = nil
local current_band_id: string? = nil
local local_hop_time_by_user_id: { [number]: number } = {}

--[[
	Returns the persistent Arena server registry.

	Args:
		None.

	Returns:
		MemoryStoreSortedMap: Cross-server Arena registry.
]]
local function get_server_map(): any
	return MemoryStoreService:GetSortedMap(SERVER_MAP_NAME)
end

--[[
	Returns the short-lived user hop registry.

	Args:
		None.

	Returns:
		MemoryStoreHashMap: Cross-server hop cooldown registry.
]]
local function get_hop_map(): any
	return MemoryStoreService:GetHashMap(HOP_MAP_NAME)
end

--[[
	Counts equipped Necromancer skill slots.

	Args:
		player (Player): Player to inspect.

	Returns:
		number: Number of equipped skills.
]]
local function get_equipped_skill_count(
	player: Player
): number
	local count = 0
	for slot = 1, 3 do
		local skill_id = player:GetAttribute(
			("EquippedSkill%d"):format(slot)
		)
		if typeof(skill_id) == "string" and skill_id ~= "" then
			count += 1
		end
	end
	return count
end

--[[
	Returns one numeric Player attribute with a fallback.

	Args:
		player (Player): Player to inspect.
		name (string): Attribute name.
		default_value (number): Fallback value.

	Returns:
		number: Attribute value or fallback.
]]
local function get_number_attribute(
	player: Player,
	name: string,
	default_value: number
): number
	local value = player:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return default_value
end

--[[
	Calculates the matchmaking strength of one player.

	Args:
		player (Player): Player to score.

	Returns:
		number: Matchmaking strength.
]]
local function calculate_player_strength(
	player: Player
): number
	local loadout_cost = 0
	if backpack_service
		and backpack_service.get_match_loadout_cost
	then
		loadout_cost =
			backpack_service.get_match_loadout_cost(player)
	end

	return MatchmakingConfig.calculate_strength({
		command_capacity = get_number_attribute(
			player,
			"CommandCapacity",
			5
		),
		rebirth_count = get_number_attribute(
			player,
			"RebirthCount",
			0
		),
		loadout_cost = loadout_cost,
		equipped_skill_count =
			get_equipped_skill_count(player),
	})
end

--[[
	Applies current matchmaking strength attributes to one player.

	Args:
		player (Player): Player receiving attributes.

	Returns:
		number: Calculated strength.
		table: Selected matchmaking band.
]]
local function apply_strength_attributes(
	player: Player
): (number, any)
	local score = calculate_player_strength(player)
	local band = MatchmakingConfig.get_band(score)

	player:SetAttribute("MatchStrength", score)
	player:SetAttribute("MatchBandId", band.id)
	player:SetAttribute("MatchBandName", band.name)
	return score, band
end

--[[
	Returns the strongest score across a party.

	Args:
		members ({ Player }): Party or solo members.

	Returns:
		number: Strongest member score.
		Player: Strongest member.
]]
local function get_group_strength(
	members: { Player }
): (number, Player)
	local strongest = members[1]
	local strongest_score = -1

	for _, member in ipairs(members) do
		local score = calculate_player_strength(member)
		apply_strength_attributes(member)
		if score > strongest_score then
			strongest_score = score
			strongest = member
		end
	end

	return math.max(0, strongest_score), strongest
end

--[[
	Sends a matchmaking status payload to one player.

	Args:
		player (Player): Recipient.
		status (string): Status identifier.
		message (string): User-facing message.

	Returns:
		None.
]]
local function send_status(
	player: Player,
	status: string,
	message: string
)
	Remotes.matchmaking_update():FireClient(player, {
		kind = "STATUS",
		status = status,
		message = message,
		score = player:GetAttribute("MatchStrength") or 0,
		bandId = player:GetAttribute("MatchBandId") or "",
		bandName = player:GetAttribute("MatchBandName") or "",
		targetPlayers =
			MatchmakingConfig.TARGET_ARENA_PLAYERS,
	})
end

--[[
	Sends one status to all members in a group.

	Args:
		members ({ Player }): Players receiving the status.
		status (string): Status identifier.
		message (string): User-facing message.

	Returns:
		None.
]]
local function send_group_status(
	members: { Player },
	status: string,
	message: string
)
	for _, member in ipairs(members) do
		if member.Parent then
			send_status(member, status, message)
		end
	end
end

--[[
	Returns the local party group used for matchmaking.

	Args:
		player (Player): Queueing player.

	Returns:
		{ Player }: Solo player or current party members.
]]
local function get_match_group(
	player: Player
): { Player }
	if party_service and party_service.get_members then
		return party_service.get_members(player)
	end
	return { player }
end

--[[
	Checks that every queued party member is ready in the Sanctum.

	Args:
		members ({ Player }): Queue group.

	Returns:
		boolean: True when every member can queue.
		string: Failure message when false.
]]
local function validate_group(
	members: { Player }
): (boolean, string)
	if #members == 0 then
		return false, "No party members are available."
	end
	if #members > MatchmakingConfig.TARGET_ARENA_PLAYERS then
		return false, "That party cannot fit in an Arena server."
	end

	for _, member in ipairs(members) do
		if not member.Parent then
			return false, "A party member left the server."
		end
		if pvp_service
			and pvp_service.is_in_safe_zone
			and not pvp_service.is_in_safe_zone(member)
		then
			return false,
				"Every party member must be in the Sanctum."
		end
	end
	return true, ""
end

--[[
	Returns whether a user hop cooldown is still active.

	Args:
		player (Player): Player to inspect.
		cooldown (number): Required cooldown in seconds.

	Returns:
		boolean: True when the player may move servers.
		number: Remaining cooldown seconds.
]]
local function can_hop(
	player: Player,
	cooldown: number
): (boolean, number)
	local current_unix = os.time()

	if RunService:IsStudio() or game.PlaceId == 0 then
		local previous = local_hop_time_by_user_id[player.UserId]
		if not previous then
			return true, 0
		end
		local remaining = cooldown - (current_unix - previous)
		return remaining <= 0, math.max(0, remaining)
	end

	local ok, previous = pcall(function()
		return get_hop_map():GetAsync(
			tostring(player.UserId)
		)
	end)
	if not ok or typeof(previous) ~= "number" then
		return true, 0
	end

	local remaining = cooldown - (current_unix - previous)
	return remaining <= 0, math.max(0, remaining)
end

--[[
	Records a cross-server movement for hop protection.

	Args:
		members ({ Player }): Players being moved.

	Returns:
		None.
]]
local function mark_hop(members: { Player })
	local timestamp = os.time()
	for _, member in ipairs(members) do
		local_hop_time_by_user_id[member.UserId] = timestamp

		if not RunService:IsStudio()
			and game.PlaceId ~= 0
		then
			pcall(function()
				get_hop_map():SetAsync(
					tostring(member.UserId),
					timestamp,
					MatchmakingConfig
						.NORMAL_HOP_COOLDOWN_SECONDS + 30
				)
			end)
		end
	end
end

--[[
	Validates hop cooldowns for an entire party.

	Args:
		members ({ Player }): Queue group.
		cooldown (number): Required cooldown.

	Returns:
		boolean: True when every member may hop.
		string: Failure message when blocked.
]]
local function validate_hop_cooldown(
	members: { Player },
	cooldown: number
): (boolean, string)
	for _, member in ipairs(members) do
		local allowed, remaining = can_hop(
			member,
			cooldown
		)
		if not allowed then
			return false,
				("%s can change Arena servers in %.0fs.")
					:format(
						member.DisplayName,
						remaining
					)
		end
	end
	return true, ""
end

--[[
	Saves persistent Soul Collection state before a server move.

	Args:
		members ({ Player }): Players about to teleport.

	Returns:
		boolean: True when every available profile saved.
]]
local function save_group(members: { Player }): boolean
	if not soul_collection_service
		or not soul_collection_service.save_now
	then
		return true
	end

	for _, member in ipairs(members) do
		if not soul_collection_service.save_now(member) then
			return false
		end
	end
	return true
end

--[[
	Builds common teleport data for an Arena group.

	Args:
		player (Player): Queue leader.
		score (number): Strongest-member score.
		band (any): Selected matchmaking band.
		server_key (string): Arena server registry key.
		access_code (string?): Reserved-server access code.
		friend_override (boolean): Whether band matching was bypassed.

	Returns:
		table: Teleport data.
]]
local function build_teleport_data(
	player: Player,
	score: number,
	band: any,
	server_key: string,
	access_code: string?,
	friend_override: boolean
): any
	local party_payload = nil
	if party_service
		and party_service.get_teleport_payload
	then
		party_payload =
			party_service.get_teleport_payload(player)
	end

	return {
		phase = 11,
		autoArena = true,
		matchStrength = score,
		matchBandId = band.id,
		matchBandName = band.name,
		matchServerKey = server_key,
		arenaAccessCode = access_code,
		friendOverride = friend_override,
		party = party_payload,
		lastMatchRequestUnix = os.time(),
	}
end

--[[
	Reads a matching server from the MemoryStore registry.

	Args:
		band_id (string): Required matchmaking band.
		group_size (number): Number of incoming players.

	Returns:
		table?: Matching server record.
]]
local function find_matching_server(
	band_id: string,
	group_size: number
): any?
	local ok, records = pcall(function()
		return get_server_map():GetRangeAsync(
			Enum.SortDirection.Descending,
			SERVER_QUERY_LIMIT
		)
	end)
	if not ok or typeof(records) ~= "table" then
		return nil
	end

	for _, entry in ipairs(records) do
		local value = entry.value
		if typeof(value) == "table"
			and value.bandId == band_id
			and typeof(value.playerCount) == "number"
			and value.playerCount + group_size
				<= MatchmakingConfig.TARGET_ARENA_PLAYERS
			and typeof(value.accessCode) == "string"
			and value.accessCode ~= ""
		then
			value.serverKey = entry.key
			return value
		end
	end
	return nil
end

--[[
	Creates a new reserved Arena server registration.

	Args:
		band_id (string): Matchmaking band.
		group_size (number): Initial expected players.

	Returns:
		table?: Created server record.
		string?: Failure reason.
]]
local function create_arena_server(
	band_id: string,
	group_size: number
): (any?, string?)
	local ok, access_code, private_server_id = pcall(
		function()
			return RobloxTeleportService:ReserveServerAsync(
				game.PlaceId
			)
		end
	)
	if not ok or typeof(access_code) ~= "string" then
		return nil, tostring(access_code)
	end

	local server_key = HttpService:GenerateGUID(false)
	local record = {
		bandId = band_id,
		playerCount = group_size,
		accessCode = access_code,
		privateServerId = private_server_id,
		updatedAt = os.time(),
	}

	local stored, err = pcall(function()
		get_server_map():SetAsync(
			server_key,
			record,
			MatchmakingConfig.SERVER_TTL_SECONDS,
			group_size
		)
	end)
	if not stored then
		return nil, tostring(err)
	end

	record.serverKey = server_key
	return record, nil
end

--[[
	Teleports a normal matchmaking group to a reserved server.

	Args:
		player (Player): Queue leader.
		members ({ Player }): Group members.
		score (number): Strongest-member score.
		band (any): Selected band.

	Returns:
		boolean: True when teleport was initiated.
		string: User-facing result.
]]
local function teleport_matched_group(
	player: Player,
	members: { Player },
	score: number,
	band: any
): (boolean, string)
	local server = find_matching_server(
		band.id,
		#members
	)
	if not server then
		local create_error = nil
		server, create_error = create_arena_server(
			band.id,
			#members
		)
		if not server then
			return false,
				"Could not create an Arena server: "
					.. tostring(create_error)
		end
	end

	if not save_group(members) then
		return false,
			"Your Soul Vault could not be saved. Try again."
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = server.accessCode
	options:SetTeleportData(
		build_teleport_data(
			player,
			score,
			band,
			server.serverKey,
			server.accessCode,
			false
		)
	)

	mark_hop(members)
	local ok, err = pcall(function()
		RobloxTeleportService:TeleportAsync(
			game.PlaceId,
			members,
			options
		)
	end)
	if not ok then
		return false, "Arena travel failed: " .. tostring(err)
	end

	return true,
		("Entering %s Arena matchmaking...")
			:format(band.name)
end

--[[
	Returns whether this server can keep the group locally.

	Args:
		band_id (string): Required group band.

	Returns:
		boolean: True when this is already that Arena band.
]]
local function can_use_current_server(
	band_id: string
): boolean
	return current_server_key ~= nil
		and current_band_id == band_id
end

--[[
	Initializes matchmaking attributes for one player.

	Args:
		player (Player): Joining player.

	Returns:
		None.
]]
local function initialize_player(player: Player)
	apply_strength_attributes(player)
	player:SetAttribute("MatchmakingFriendOverride", false)
	player:SetAttribute("MatchmakingAutoArena", false)

	local join_data = player:GetJoinData()
	local teleport_data = join_data.TeleportData
	if typeof(teleport_data) ~= "table"
		or teleport_data.phase ~= 11
	then
		return
	end

	local friend_override =
		teleport_data.friendOverride == true

	if typeof(teleport_data.matchBandId) == "string" then
		player:SetAttribute(
			"ArenaSessionBand",
			teleport_data.matchBandId
		)
		if not friend_override then
			current_band_id = teleport_data.matchBandId
		end
	end
	if not friend_override
		and typeof(teleport_data.matchServerKey) == "string"
	then
		current_server_key = teleport_data.matchServerKey
	end
	if not friend_override
		and typeof(teleport_data.arenaAccessCode) == "string"
	then
		current_access_code = teleport_data.arenaAccessCode
	end

	player:SetAttribute(
		"MatchmakingFriendOverride",
		friend_override
	)
	player:SetAttribute(
		"MatchmakingAutoArena",
		teleport_data.autoArena == true
	)
end

--[[
	Updates the current reserved server registry heartbeat.

	Args:
		None.

	Returns:
		None.
]]
local function update_server_heartbeat()
	if not current_server_key
		or not current_band_id
		or not current_access_code
	then
		return
	end

	local connected_count = #Players:GetPlayers()

	pcall(function()
		get_server_map():SetAsync(
			current_server_key :: string,
			{
				bandId = current_band_id,
				playerCount = connected_count,
				accessCode = current_access_code,
				jobId = game.JobId,
				updatedAt = os.time(),
			},
			MatchmakingConfig.SERVER_TTL_SECONDS,
			connected_count
		)
	end)
end

--[[
	Handles matchmaking-specific client actions.

	Args:
		player (Player): Requesting player.
		action (any): Action identifier.
		payload (any): Optional request payload.

	Returns:
		None.
]]
local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action == "REQUEST" then
		apply_strength_attributes(player)
		send_status(
			player,
			"READY",
			"Matchmaking profile ready."
		)
		return
	end

	if action ~= "JOIN_FRIEND" then
		send_status(
			player,
			"ERROR",
			"Unknown matchmaking action."
		)
		return
	end

	local target = nil
	if typeof(payload) == "table" then
		target = payload.username
	end
	if typeof(target) ~= "string" or target == "" then
		send_status(
			player,
			"ERROR",
			"Enter a friend's username."
		)
		return
	end

	local ok, message = MatchmakingService.join_friend(
		player,
		target
	)
	send_status(
		player,
		if ok then "JOINING_FRIEND" else "ERROR",
		message
	)
end

--[[
	Initializes matchmaking dependencies.

	Args:
		party_service_ref (any): Party service.
		backpack_service_ref (any): Backpack service.
		soul_collection_service_ref (any): Persistent Soul service.
		pvp_service_ref (any): PvP safe-zone service.

	Returns:
		None.
]]
function MatchmakingService.init(
	party_service_ref: any,
	backpack_service_ref: any,
	soul_collection_service_ref: any,
	pvp_service_ref: any
)
	party_service = party_service_ref
	backpack_service = backpack_service_ref
	soul_collection_service = soul_collection_service_ref
	pvp_service = pvp_service_ref
end

--[[
	Starts matchmaking remotes and server registry heartbeats.

	Args:
		None.

	Returns:
		None.
]]
function MatchmakingService.start()
	if did_start then
		return
	end
	did_start = true

	Remotes.matchmaking_action().OnServerEvent:Connect(
		handle_remote
	)
	Players.PlayerAdded:Connect(initialize_player)

	for _, player in ipairs(Players:GetPlayers()) do
		initialize_player(player)
	end

	if not RunService:IsStudio() and game.PlaceId ~= 0 then
		heartbeat_task = task.spawn(function()
			while did_start do
				update_server_heartbeat()
				task.wait(
					MatchmakingConfig
						.SERVER_HEARTBEAT_SECONDS
				)
			end
		end)
	end
end

--[[
	Requests normal Arena matchmaking.

	Args:
		player (Player): Solo player or party leader.

	Returns:
		string: LOCAL, TELEPORTING or DENIED.
		string: User-facing status.
		{ Player }: Match group.
]]
function MatchmakingService.request_arena(
	player: Player
): (string, string, { Player })
	if party_service
		and party_service.can_queue
		and not party_service.can_queue(player)
	then
		return "DENIED",
			"Only the party leader can enter matchmaking.",
			{}
	end

	local members = get_match_group(player)
	local valid, reason = validate_group(members)
	if not valid then
		return "DENIED", reason, members
	end

	local score, strongest = get_group_strength(members)
	local band = MatchmakingConfig.get_band(score)

	for _, member in ipairs(members) do
		member:SetAttribute("PartyMatchStrength", score)
		member:SetAttribute("PartyStrongestUserId", strongest.UserId)
		member:SetAttribute("MatchBandId", band.id)
		member:SetAttribute("MatchBandName", band.name)
	end

	send_group_status(
		members,
		"QUEUED",
		("%s band | party strength %d")
			:format(band.name, score)
	)

	if RunService:IsStudio() or game.PlaceId == 0 then
		return "LOCAL",
			("Studio fallback: %s matchmaking.")
				:format(band.name),
			members
	end

	if can_use_current_server(band.id) then
		return "LOCAL",
			("Remaining in this %s Arena.")
				:format(band.name),
			members
	end

	local cooldown_ok, cooldown_message =
		validate_hop_cooldown(
			members,
			MatchmakingConfig
				.NORMAL_HOP_COOLDOWN_SECONDS
		)
	if not cooldown_ok then
		return "DENIED", cooldown_message, members
	end

	local ok, message = teleport_matched_group(
		player,
		members,
		score,
		band
	)
	if ok then
		send_group_status(
			members,
			"TELEPORTING",
			message
		)
		return "TELEPORTING", message, members
	end

	send_group_status(members, "ERROR", message)
	return "DENIED", message, members
end

--[[
	Joins an online Roblox friend, bypassing strength bands.

	Args:
		player (Player): Player requesting the friend join.
		username (string): Exact Roblox username.

	Returns:
		boolean: True when join was accepted or initiated.
		string: User-facing result message.
]]
function MatchmakingService.join_friend(
	player: Player,
	username: string
): (boolean, string)
	if party_service
		and party_service.can_queue
		and not party_service.can_queue(player)
	then
		return false,
			"Only the party leader can move the party."
	end

	local members = get_match_group(player)
	local valid, reason = validate_group(members)
	if not valid then
		return false, reason
	end

	local cooldown_ok, cooldown_message =
		validate_hop_cooldown(
			members,
			MatchmakingConfig
				.FRIEND_HOP_COOLDOWN_SECONDS
		)
	if not cooldown_ok then
		return false, cooldown_message
	end

	local user_ok, target_user_id = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)
	if not user_ok or typeof(target_user_id) ~= "number" then
		return false, "That Roblox user could not be found."
	end
	if target_user_id == player.UserId then
		return false, "You are already here."
	end

	local friend_ok, is_friend = pcall(function()
		return player:IsFriendsWith(target_user_id)
	end)
	if not friend_ok or not is_friend then
		return false, "Join Friend only accepts Roblox friends."
	end

	local local_friend = Players:GetPlayerByUserId(
		target_user_id
	)
	if local_friend then
		for _, member in ipairs(members) do
			member:SetAttribute(
				"MatchmakingFriendOverride",
				true
			)
		end
		return true, "Your friend is already in this server."
	end

	if RunService:IsStudio() or game.PlaceId == 0 then
		return false,
			"Cross-server friend joins are unavailable in Studio."
	end

	local call_ok, joinable, error_message, place_id, job_id =
		pcall(function()
			return RobloxTeleportService:
				GetPlayerPlaceInstanceAsync(target_user_id)
		end)
	if not call_ok then
		return false, "Could not locate that friend."
	end
	if joinable ~= true then
		return false,
			tostring(error_message or "That friend is not joinable.")
	end
	if place_id ~= game.PlaceId
		or typeof(job_id) ~= "string"
		or job_id == ""
	then
		return false,
			"That friend is not in this Necro Snake place."
	end

	if not save_group(members) then
		return false,
			"Your Soul Vault could not be saved. Try again."
	end

	local score = get_group_strength(members)
	local band = MatchmakingConfig.get_band(score)
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = job_id
	options:SetTeleportData(
		build_teleport_data(
			player,
			score,
			band,
			"friend:" .. job_id,
			nil,
			true
		)
	)

	for _, member in ipairs(members) do
		member:SetAttribute(
			"MatchmakingFriendOverride",
			true
		)
	end

	mark_hop(members)
	local moved, move_error = pcall(function()
		RobloxTeleportService:TeleportAsync(
			game.PlaceId,
			members,
			options
		)
	end)
	if not moved then
		return false,
			"Friend join failed: " .. tostring(move_error)
	end

	return true,
		("Joining %s's Arena server.")
			:format(username)
end

--[[
	Returns whether a player arrived through Arena matchmaking.

	Args:
		player (Player): Player to inspect.

	Returns:
		boolean: True when the player should auto-enter the Arena.
]]
function MatchmakingService.should_auto_enter_arena(
	player: Player
): boolean
	return player:GetAttribute("MatchmakingAutoArena") == true
end

--[[
	Clears the one-use auto-enter flag.

	Args:
		player (Player): Player whose flag should be cleared.

	Returns:
		None.
]]
function MatchmakingService.consume_auto_enter_arena(
	player: Player
)
	player:SetAttribute("MatchmakingAutoArena", false)
end

--[[
	Returns one player's current matchmaking strength.

	Args:
		player (Player): Player to inspect.

	Returns:
		number: Matchmaking strength.
]]
function MatchmakingService.get_strength(
	player: Player
): number
	local score = calculate_player_strength(player)
	apply_strength_attributes(player)
	return score
end

--[[
	Returns deterministic band data for Studio acceptance tests.

	Args:
		score (number): Arbitrary strength score.

	Returns:
		table: Matching band definition.
]]
function MatchmakingService.debug_get_band(score: number): any
	return MatchmakingConfig.get_band(score)
end

--[[
	Calculates strongest-member matchmaking for Studio tests.

	Args:
		members ({ Player }): Test group.

	Returns:
		number: Strongest group score.
		Player: Strongest member.
]]
function MatchmakingService.debug_group_strength(
	members: { Player }
): (number, Player)
	return get_group_strength(members)
end

--[[
	Resolves synthetic member scores using strongest-member matching.

	Args:
		scores ({ number }): Synthetic party member scores.

	Returns:
		number: Strongest score.
		string: Band ID selected from that score.
]]
function MatchmakingService.debug_resolve_party_scores(
	scores: { number }
): (number, string)
	local strongest = 0
	for _, score in ipairs(scores) do
		strongest = math.max(strongest, score)
	end
	local band = MatchmakingConfig.get_band(strongest)
	return strongest, band.id
end

--[[
	Builds cross-band friend-override data for Studio acceptance.

	Args:
		player (Player): Test player.
		score (number): Synthetic player or party score.

	Returns:
		table: Teleport-style data with the override flag set.
]]
function MatchmakingService.debug_friend_override_data(
	player: Player,
	score: number
): any
	local band = MatchmakingConfig.get_band(score)
	return build_teleport_data(
		player,
		score,
		band,
		"studio-friend-test",
		nil,
		true
	)
end

--[[
	Marks a local Studio hop for cooldown acceptance tests.

	Args:
		player (Player): Test player.

	Returns:
		boolean: True when Studio testing is active.
]]
function MatchmakingService.debug_mark_hop(
	player: Player
): boolean
	if not RunService:IsStudio() then
		return false
	end
	mark_hop({ player })
	return true
end

--[[
	Reads the normal hop cooldown for Studio acceptance tests.

	Args:
		player (Player): Test player.

	Returns:
		boolean: True when another hop is currently allowed.
		number: Remaining normal-hop cooldown.
]]
function MatchmakingService.debug_can_hop(
	player: Player
): (boolean, number)
	if not RunService:IsStudio() then
		return false, 0
	end
	return can_hop(
		player,
		MatchmakingConfig.NORMAL_HOP_COOLDOWN_SECONDS
	)
end

--[[
	Clears local Studio hop history after an acceptance test.

	Args:
		player (Player): Test player.

	Returns:
		boolean: True when Studio testing is active.
]]
function MatchmakingService.debug_clear_hop(
	player: Player
): boolean
	if not RunService:IsStudio() then
		return false
	end
	local_hop_time_by_user_id[player.UserId] = nil
	return true
end

return MatchmakingService
