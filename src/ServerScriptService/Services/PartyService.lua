--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchmakingConfig = require(
	ReplicatedStorage.Shared.MatchmakingConfig
)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PartyService = {}

local INVITE_SECONDS = 30

type PartyState = {
	id: string,
	leader_user_id: number,
	members: { [number]: boolean },
}

type InviteState = {
	from_user_id: number,
	expires_at: number,
}

local parties_by_id: { [string]: PartyState } = {}
local party_id_by_user_id: { [number]: string } = {}
local invites_by_user_id: {
	[number]: { [number]: InviteState },
} = {}

local pvp_service = nil :: any
local did_start = false

--[[
	Returns the current server time used for invite expiry.

	Args:
		None.

	Returns:
		number: Current monotonic clock time.
]]
local function now(): number
	return os.clock()
end

--[[
	Returns a party by player user ID.

	Args:
		user_id (number): Player user ID.

	Returns:
		PartyState?: Party when one exists.
]]
local function get_party_by_user_id(
	user_id: number
): PartyState?
	local party_id = party_id_by_user_id[user_id]
	if not party_id then
		return nil
	end
	return parties_by_id[party_id]
end

--[[
	Returns sorted party member user IDs.

	Args:
		party (PartyState): Party to inspect.

	Returns:
		{ number }: Sorted member user IDs.
]]
local function get_member_user_ids(
	party: PartyState
): { number }
	local result: { number } = {}
	for user_id in pairs(party.members) do
		table.insert(result, user_id)
	end
	table.sort(result)
	return result
end

--[[
	Returns the number of members in a party.

	Args:
		party (PartyState): Party to inspect.

	Returns:
		number: Member count.
]]
local function get_party_size(party: PartyState): number
	local count = 0
	for _ in pairs(party.members) do
		count += 1
	end
	return count
end

--[[
	Returns whether a player can change party state.

	Args:
		player (Player): Player requesting a party change.

	Returns:
		boolean: True while party changes are allowed.
]]
local function can_change_party(player: Player): boolean
	if not pvp_service or not pvp_service.is_in_safe_zone then
		return true
	end
	return pvp_service.is_in_safe_zone(player)
end

--[[
	Applies replicated party attributes to one player.

	Args:
		player (Player): Player receiving party state.
		party (PartyState?): Party or nil when solo.

	Returns:
		None.
]]
local function apply_party_attributes(
	player: Player,
	party: PartyState?
)
	if not party then
		player:SetAttribute("PartyId", "")
		player:SetAttribute("PartyLeaderUserId", 0)
		player:SetAttribute("PartySize", 1)
		return
	end

	player:SetAttribute("PartyId", party.id)
	player:SetAttribute(
		"PartyLeaderUserId",
		party.leader_user_id
	)
	player:SetAttribute("PartySize", get_party_size(party))
end

--[[
	Removes expired invites for one recipient.

	Args:
		user_id (number): Invite recipient user ID.

	Returns:
		None.
]]
local function prune_invites(user_id: number)
	local invites = invites_by_user_id[user_id]
	if not invites then
		return
	end

	local current = now()
	for inviter_user_id, invite in pairs(invites) do
		if invite.expires_at <= current then
			invites[inviter_user_id] = nil
		end
	end

	if next(invites) == nil then
		invites_by_user_id[user_id] = nil
	end
end

--[[
	Builds a client-safe party snapshot.

	Args:
		player (Player): Snapshot recipient.
		message (string?): Optional status message.

	Returns:
		table: Party and invite data.
]]
local function build_snapshot(
	player: Player,
	message: string?
): any
	prune_invites(player.UserId)

	local party = get_party_by_user_id(player.UserId)
	local members = {}
	if party then
		for _, user_id in ipairs(get_member_user_ids(party)) do
			local member = Players:GetPlayerByUserId(user_id)
			table.insert(members, {
				userId = user_id,
				name = member and member.Name
					or ("User %d"):format(user_id),
				displayName = member and member.DisplayName
					or ("User %d"):format(user_id),
			})
		end
	end

	local invites = {}
	for inviter_user_id, invite in pairs(
		invites_by_user_id[player.UserId] or {}
	) do
		local inviter = Players:GetPlayerByUserId(
			inviter_user_id
		)
		table.insert(invites, {
			fromUserId = inviter_user_id,
			fromName = inviter and inviter.DisplayName
				or ("User %d"):format(inviter_user_id),
			expiresIn = math.max(
				0,
				invite.expires_at - now()
			),
		})
	end

	return {
		kind = "SNAPSHOT",
		partyId = party and party.id or "",
		leaderUserId = party
			and party.leader_user_id
			or 0,
		members = members,
		invites = invites,
		maxSize = MatchmakingConfig.PARTY_MAX_SIZE,
		message = message or "",
	}
end

--[[
	Sends party state to one player.

	Args:
		player (Player): Snapshot recipient.
		message (string?): Optional status message.

	Returns:
		None.
]]
local function send_snapshot(
	player: Player,
	message: string?
)
	Remotes.party_update():FireClient(
		player,
		build_snapshot(player, message)
	)
end

--[[
	Refreshes attributes and UI for all online party members.

	Args:
		party (PartyState): Party to refresh.
		message (string?): Optional status message.

	Returns:
		None.
]]
local function refresh_party(
	party: PartyState,
	message: string?
)
	for user_id in pairs(party.members) do
		local player = Players:GetPlayerByUserId(user_id)
		if player then
			apply_party_attributes(player, party)
			send_snapshot(player, message)
		end
	end
end

--[[
	Creates a new party led by one player.

	Args:
		player (Player): Party leader.

	Returns:
		PartyState: Created party.
]]
local function create_party(player: Player): PartyState
	local party: PartyState = {
		id = HttpService:GenerateGUID(false),
		leader_user_id = player.UserId,
		members = {
			[player.UserId] = true,
		},
	}
	parties_by_id[party.id] = party
	party_id_by_user_id[player.UserId] = party.id
	refresh_party(party, "Party created.")
	return party
end

--[[
	Returns an existing party or creates a new one.

	Args:
		player (Player): Player requiring a party.

	Returns:
		PartyState: Existing or newly-created party.
]]
local function get_or_create_party(
	player: Player
): PartyState
	local party = get_party_by_user_id(player.UserId)
	if party then
		return party
	end
	return create_party(player)
end

--[[
	Removes one user from their party.

	Args:
		user_id (number): User ID to remove.
		message (string?): Optional message for remaining members.

	Returns:
		None.
]]
local function remove_member(
	user_id: number,
	message: string?
)
	local party = get_party_by_user_id(user_id)
	if not party then
		return
	end

	party.members[user_id] = nil
	party_id_by_user_id[user_id] = nil

	local removed_player = Players:GetPlayerByUserId(user_id)
	if removed_player then
		apply_party_attributes(removed_player, nil)
		send_snapshot(
			removed_player,
			message or "You left the party."
		)
	end

	local member_ids = get_member_user_ids(party)
	if #member_ids == 0 then
		parties_by_id[party.id] = nil
		return
	end

	if party.leader_user_id == user_id then
		party.leader_user_id = member_ids[1]
	end

	if #member_ids == 1 then
		local remaining_id = member_ids[1]
		local remaining = Players:GetPlayerByUserId(
			remaining_id
		)
		party_id_by_user_id[remaining_id] = nil
		parties_by_id[party.id] = nil
		if remaining then
			apply_party_attributes(remaining, nil)
			send_snapshot(
				remaining,
				"Party disbanded."
			)
		end
		return
	end

	refresh_party(
		party,
		message or "Party membership changed."
	)
end

--[[
	Sends a party invitation.

	Args:
		player (Player): Inviting player.
		target_user_id (number): Target user ID.

	Returns:
		boolean: True when the invite was sent.
		string: User-facing result message.
]]
local function invite_player(
	player: Player,
	target_user_id: number
): (boolean, string)
	if not can_change_party(player) then
		return false, "Party changes are only allowed in the Sanctum."
	end

	local target = Players:GetPlayerByUserId(target_user_id)
	if not target or target == player then
		return false, "That player is not available."
	end
	if not can_change_party(target) then
		return false, "That player is currently in the Arena."
	end

	local party = get_or_create_party(player)
	if party.leader_user_id ~= player.UserId then
		return false, "Only the party leader can invite players."
	end
	if party.members[target.UserId] then
		return false, "That player is already in your party."
	end
	if get_party_by_user_id(target.UserId) then
		return false, "That player is already in another party."
	end
	if get_party_size(party)
		>= MatchmakingConfig.PARTY_MAX_SIZE
	then
		return false, "Your party is full."
	end

	local invites = invites_by_user_id[target.UserId]
	if not invites then
		invites = {}
		invites_by_user_id[target.UserId] = invites
	end
	invites[player.UserId] = {
		from_user_id = player.UserId,
		expires_at = now() + INVITE_SECONDS,
	}

	send_snapshot(
		target,
		("%s invited you to a party."):format(
			player.DisplayName
		)
	)
	send_snapshot(player, "Party invite sent.")
	return true, "Party invite sent."
end

--[[
	Accepts an outstanding party invitation.

	Args:
		player (Player): Invite recipient.
		inviter_user_id (number): Inviter user ID.

	Returns:
		boolean: True when the player joined.
		string: User-facing result message.
]]
local function accept_invite(
	player: Player,
	inviter_user_id: number
): (boolean, string)
	if not can_change_party(player) then
		return false, "Party changes are only allowed in the Sanctum."
	end
	if get_party_by_user_id(player.UserId) then
		return false, "Leave your current party first."
	end

	prune_invites(player.UserId)
	local invites = invites_by_user_id[player.UserId]
	local invite = invites and invites[inviter_user_id]
	if not invite then
		return false, "That invite is no longer available."
	end

	local inviter = Players:GetPlayerByUserId(inviter_user_id)
	local party = inviter
		and get_party_by_user_id(inviter.UserId)
	if not inviter or not party then
		return false, "That party is no longer available."
	end
	if party.leader_user_id ~= inviter.UserId then
		return false, "That invite is no longer valid."
	end
	if get_party_size(party)
		>= MatchmakingConfig.PARTY_MAX_SIZE
	then
		return false, "That party is full."
	end

	invites_by_user_id[player.UserId] = nil
	party.members[player.UserId] = true
	party_id_by_user_id[player.UserId] = party.id
	refresh_party(
		party,
		("%s joined the party."):format(player.DisplayName)
	)
	return true, "Joined party."
end

--[[
	Declines one party invitation.

	Args:
		player (Player): Invite recipient.
		inviter_user_id (number): Inviter user ID.

	Returns:
		boolean: True when an invite existed.
		string: User-facing result message.
]]
local function decline_invite(
	player: Player,
	inviter_user_id: number
): (boolean, string)
	prune_invites(player.UserId)
	local invites = invites_by_user_id[player.UserId]
	if not invites or not invites[inviter_user_id] then
		return false, "That invite is no longer available."
	end

	invites[inviter_user_id] = nil
	send_snapshot(player, "Party invite declined.")
	return true, "Party invite declined."
end

--[[
	Handles one client party action.

	Args:
		player (Player): Requesting player.
		action (any): Action identifier.
		payload (any): Optional action payload.

	Returns:
		None.
]]
local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action == "REQUEST" then
		send_snapshot(player, nil)
		return
	end

	payload = if typeof(payload) == "table"
		then payload
		else {}
	local target_user_id = payload.userId
	if typeof(target_user_id) ~= "number" then
		target_user_id = 0
	end

	local ok = false
	local message = "Unknown party action."

	if action == "INVITE" then
		ok, message = invite_player(
			player,
			math.floor(target_user_id)
		)
	elseif action == "ACCEPT" then
		ok, message = accept_invite(
			player,
			math.floor(target_user_id)
		)
	elseif action == "DECLINE" then
		ok, message = decline_invite(
			player,
			math.floor(target_user_id)
		)
	elseif action == "LEAVE" then
		if can_change_party(player) then
			remove_member(player.UserId, nil)
			ok = true
			message = "Left party."
		else
			message = "You cannot leave a party in the Arena."
		end
	end

	if player.Parent then
		send_snapshot(player, message)
	end
end

--[[
	Initializes one player's party attributes and teleport restoration.

	Args:
		player (Player): Joining player.

	Returns:
		None.
]]
local function initialize_player(player: Player)
	apply_party_attributes(player, nil)

	local join_data = player:GetJoinData()
	local teleport_data = join_data.TeleportData
	if typeof(teleport_data) ~= "table" then
		send_snapshot(player, nil)
		return
	end

	local party_data = teleport_data.party
	if typeof(party_data) ~= "table" then
		send_snapshot(player, nil)
		return
	end

	PartyService.restore_from_teleport(
		player,
		party_data
	)
end

--[[
	Initializes the Party service dependency.

	Args:
		pvp_service_ref (any): PvP service used for safe-zone checks.

	Returns:
		None.
]]
function PartyService.init(pvp_service_ref: any)
	pvp_service = pvp_service_ref
end

--[[
	Starts party remotes and player lifecycle hooks.

	Args:
		None.

	Returns:
		None.
]]
function PartyService.start()
	if did_start then
		return
	end
	did_start = true

	Remotes.party_action().OnServerEvent:Connect(handle_remote)
	Players.PlayerAdded:Connect(initialize_player)
	Players.PlayerRemoving:Connect(function(player)
		invites_by_user_id[player.UserId] = nil
		remove_member(
			player.UserId,
			"A party member left the server."
		)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		initialize_player(player)
	end
end

--[[
	Returns online party members for a player.

	Args:
		player (Player): Player whose party is requested.

	Returns:
		{ Player }: Local server party members, including the player.
]]
function PartyService.get_members(
	player: Player
): { Player }
	local party = get_party_by_user_id(player.UserId)
	if not party then
		return { player }
	end

	local result: { Player } = {}
	for _, user_id in ipairs(get_member_user_ids(party)) do
		local member = Players:GetPlayerByUserId(user_id)
		if member then
			table.insert(result, member)
		end
	end
	return result
end

--[[
	Returns whether two user IDs share the same non-solo party.

	Args:
		left_user_id (number): First user ID.
		right_user_id (number): Second user ID.

	Returns:
		boolean: True when both user IDs share a party.
]]
function PartyService.are_user_ids_in_same_party(
	left_user_id: number,
	right_user_id: number
): boolean
	local left_party = party_id_by_user_id[left_user_id]
	local right_party = party_id_by_user_id[right_user_id]
	return left_party ~= nil
		and left_party == right_party
end

function PartyService.are_in_same_party(
	left: Player,
	right: Player
): boolean
	return PartyService.are_user_ids_in_same_party(
		left.UserId,
		right.UserId
	)
end

--[[
	Returns whether a player is allowed to queue their party.

	Args:
		player (Player): Player attempting Arena matchmaking.

	Returns:
		boolean: True for solo players or party leaders.
]]
function PartyService.can_queue(player: Player): boolean
	local party = get_party_by_user_id(player.UserId)
	return not party
		or party.leader_user_id == player.UserId
end

--[[
	Builds party data that can survive a server teleport.

	Args:
		player (Player): Party member requesting teleport data.

	Returns:
		table?: Party payload, or nil for a solo player.
]]
function PartyService.get_teleport_payload(
	player: Player
): any?
	local party = get_party_by_user_id(player.UserId)
	if not party then
		return nil
	end

	return {
		id = party.id,
		leaderUserId = party.leader_user_id,
		memberUserIds = get_member_user_ids(party),
	}
end

--[[
	Restores one teleported player into a party.

	Args:
		player (Player): Arriving player.
		raw (any): Party teleport payload.

	Returns:
		boolean: True when party state was restored.
]]
function PartyService.restore_from_teleport(
	player: Player,
	raw: any
): boolean
	if typeof(raw) ~= "table"
		or typeof(raw.id) ~= "string"
		or typeof(raw.leaderUserId) ~= "number"
		or typeof(raw.memberUserIds) ~= "table"
	then
		return false
	end

	local allowed = false
	local members: { [number]: boolean } = {}
	for _, user_id in ipairs(raw.memberUserIds) do
		if typeof(user_id) == "number" then
			local normalized = math.floor(user_id)
			members[normalized] = true
			if normalized == player.UserId then
				allowed = true
			end
		end
	end
	if not allowed then
		return false
	end

	local party = parties_by_id[raw.id]
	if not party then
		party = {
			id = raw.id,
			leader_user_id = math.floor(raw.leaderUserId),
			members = members,
		}
		parties_by_id[party.id] = party
	end

	party.members[player.UserId] = true
	party_id_by_user_id[player.UserId] = party.id
	refresh_party(party, "Party restored after travel.")
	return true
end

--[[
	Creates a deterministic party for Studio acceptance tests.

	Args:
		players ({ Player }): Players to place in one party.

	Returns:
		string?: Party ID when created.
]]
function PartyService.debug_create_party(
	players: { Player }
): string?
	if not RunService:IsStudio() or #players == 0 then
		return nil
	end

	local leader = players[1]
	local party = create_party(leader)
	for index = 2, #players do
		local player = players[index]
		remove_member(player.UserId, nil)
		party.members[player.UserId] = true
		party_id_by_user_id[player.UserId] = party.id
	end
	refresh_party(party, "Studio test party.")
	return party.id
end

--[[
	Clears one player's party after a Studio acceptance test.

	Args:
		player (Player): Test player.

	Returns:
		boolean: True when Studio testing is active.
]]
function PartyService.debug_clear_party(
	player: Player
): boolean
	if not RunService:IsStudio() then
		return false
	end
	remove_member(player.UserId, "Studio test party cleared.")
	return true
end

--[[
	Creates a synthetic party for deterministic Studio acceptance.

	Args:
		user_ids ({ number }): Synthetic party user IDs.
		leader_user_id (number): User ID to mark as party leader.

	Returns:
		string?: Party ID when the synthetic party was created.
]]
function PartyService.debug_create_user_id_party(
	user_ids: { number },
	leader_user_id: number
): string?
	if not RunService:IsStudio() or #user_ids == 0 then
		return nil
	end

	local party: PartyState = {
		id = "studio-" .. HttpService:GenerateGUID(false),
		leader_user_id = leader_user_id,
		members = {},
	}
	for _, user_id in ipairs(user_ids) do
		local normalized = math.floor(user_id)
		remove_member(normalized, nil)
		party.members[normalized] = true
		party_id_by_user_id[normalized] = party.id
	end
	parties_by_id[party.id] = party
	refresh_party(party, "Studio synthetic party.")
	return party.id
end

--[[
	Clears a synthetic Studio party by member user ID.

	Args:
		user_id (number): Any user ID currently in the party.

	Returns:
		boolean: True when Studio testing is active.
]]
function PartyService.debug_clear_user_id_party(
	user_id: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local party = get_party_by_user_id(user_id)
	if not party then
		return true
	end

	for member_user_id in pairs(party.members) do
		party_id_by_user_id[member_user_id] = nil
		local player = Players:GetPlayerByUserId(
			member_user_id
		)
		if player then
			apply_party_attributes(player, nil)
			send_snapshot(
				player,
				"Studio synthetic party cleared."
			)
		end
	end
	parties_by_id[party.id] = nil
	return true
end

return PartyService
