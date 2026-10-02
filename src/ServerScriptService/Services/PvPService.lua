--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PvPService = {}

local SPAWN_PROTECTION_SECONDS = 8
local COMBAT_TAG_SECONDS = 12
local ZONE_REFRESH_SECONDS = 0.5

local SAFE_ZONE_CENTER_X = 3600
local SAFE_ZONE_CENTER_Z = 3600
local SAFE_ZONE_SIZE_X = 1200
local SAFE_ZONE_SIZE_Z = 1200

local ARENA_MIN_X = 0
local ARENA_MAX_X = 2000
local ARENA_MIN_Z = 0
local ARENA_MAX_Z = 2000

local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"
local SAFE_ZONE_WORLD_NAME = "SafeZoneWorld"
local ZONES_FOLDER_NAME = "Zones"

local army_service = nil :: any
local did_start = false
local zone_task: thread? = nil

local function server_now(): number
	return Workspace:GetServerTimeNow()
end

local function get_character_root(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function get_owner_player(model: Model): Player?
	local character_player = Players:GetPlayerFromCharacter(model)
	if character_player then
		return character_player
	end

	local owner_user_id = model:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) ~= "number" then
		return nil
	end
	return Players:GetPlayerByUserId(owner_user_id)
end

local function is_point_in_part_bounds(
	part: BasePart,
	position: Vector3
): boolean
	local local_position = part.CFrame:PointToObjectSpace(position)
	local half_size = part.Size * 0.5

	return math.abs(local_position.X) <= half_size.X
		and math.abs(local_position.Y) <= half_size.Y
		and math.abs(local_position.Z) <= half_size.Z
end

local function get_safe_zone_region(): BasePart?
	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zones then
		return nil
	end

	local safe_world = zones:FindFirstChild(SAFE_ZONE_WORLD_NAME)
	if not safe_world then
		return nil
	end

	local region = safe_world:FindFirstChild(SAFE_ZONE_REGION_NAME)
	if region and region:IsA("BasePart") then
		return region
	end
	return nil
end

local function is_in_safe_bounds(position: Vector3): boolean
	local half_x = SAFE_ZONE_SIZE_X * 0.5
	local half_z = SAFE_ZONE_SIZE_Z * 0.5

	return position.X >= SAFE_ZONE_CENTER_X - half_x
		and position.X <= SAFE_ZONE_CENTER_X + half_x
		and position.Z >= SAFE_ZONE_CENTER_Z - half_z
		and position.Z <= SAFE_ZONE_CENTER_Z + half_z
end

local function is_in_arena_bounds(position: Vector3): boolean
	return position.X >= ARENA_MIN_X
		and position.X <= ARENA_MAX_X
		and position.Z >= ARENA_MIN_Z
		and position.Z <= ARENA_MAX_Z
end

local function set_boolean_until(
	player: Player,
	until_attribute: string,
	boolean_attribute: string,
	duration: number
)
	local expires_at = server_now() + duration
	player:SetAttribute(until_attribute, expires_at)
	player:SetAttribute(boolean_attribute, true)

	task.delay(duration + 0.05, function()
		if not player.Parent then
			return
		end

		local current = player:GetAttribute(until_attribute)
		if typeof(current) ~= "number" or current > server_now() then
			return
		end

		player:SetAttribute(boolean_attribute, false)
	end)
end

local function increment_number_attribute(player: Player, name: string)
	local current = player:GetAttribute(name)
	if typeof(current) ~= "number" then
		current = 0
	end
	player:SetAttribute(name, current + 1)
end

local function update_player_zone(player: Player)
	local root = get_character_root(player)
	if not root then
		player:SetAttribute("PvPZone", "Unknown")
		return
	end

	local region = get_safe_zone_region()
	if region and is_point_in_part_bounds(region, root.Position) then
		player:SetAttribute("PvPZone", "SafeZone")
		return
	end

	if is_in_safe_bounds(root.Position) then
		player:SetAttribute("PvPZone", "SafeZone")
	elseif is_in_arena_bounds(root.Position) then
		player:SetAttribute("PvPZone", "Arena")
	else
		player:SetAttribute("PvPZone", "Wilderness")
	end
end

local function hook_character(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end

	PvPService.begin_spawn_protection(player)

	if not humanoid then
		return
	end

	humanoid.Died:Connect(function()
		local killer_user_id = character:GetAttribute(
			"LastHitOwnerUserId"
		)
		if typeof(killer_user_id) ~= "number" then
			killer_user_id = 0
		end

		local damage_source = character:GetAttribute(
			"LastDamageSourceKind"
		)
		local loss_source = "NECROMANCER_DEATH"
		local loss_reason = "NECROMANCER_DEATH"

		if damage_source == "NPC" then
			loss_source = "NPC"
			loss_reason = "NECROMANCER_NPC_DEATH"
		elseif killer_user_id ~= 0
			and killer_user_id ~= player.UserId
		then
			loss_source = "PLAYER_ARMY"
			loss_reason = "PVP_NECROMANCER_DEATH"
		end

		if army_service and army_service.kill_army_for_loss then
			army_service.kill_army_for_loss(
				player,
				killer_user_id,
				loss_source,
				loss_reason
			)
		end

		if killer_user_id == 0
			or killer_user_id == player.UserId
		then
			return
		end

		local killer = Players:GetPlayerByUserId(killer_user_id)
		player:SetAttribute("LastKilledByUserId", killer_user_id)
		increment_number_attribute(player, "PvPDeaths")

		if killer then
			increment_number_attribute(killer, "PvPKills")
		end
	end)
end

local function initialize_player(player: Player)
	for _, name in ipairs({
		"PvPKills",
		"PvPDeaths",
		"PvPUnitKills",
		"PvPUnitsLost",
	}) do
		if typeof(player:GetAttribute(name)) ~= "number" then
			player:SetAttribute(name, 0)
		end
	end

	if typeof(player:GetAttribute("CombatTaggedUntil")) ~= "number" then
		player:SetAttribute("CombatTaggedUntil", 0)
	end
	if typeof(player:GetAttribute("PvPProtectedUntil")) ~= "number" then
		player:SetAttribute("PvPProtectedUntil", 0)
	end

	player:SetAttribute("CombatTagged", false)
	player:SetAttribute("PvPProtected", false)
	update_player_zone(player)

	player.CharacterAdded:Connect(function(character)
		hook_character(player, character)
	end)

	if player.Character then
		task.defer(hook_character, player, player.Character)
	end
end

local function handle_player_removing(player: Player)
	if not army_service then
		return
	end

	if PvPService.is_combat_tagged(player) then
		local killer_user_id = player:GetAttribute(
			"LastPvPOpponentUserId"
		)
		if typeof(killer_user_id) ~= "number" then
			killer_user_id = 0
		end

		army_service.kill_army_for_loss(
			player,
			killer_user_id,
			"PVP_LOGOUT",
			"COMBAT_LOGOUT"
		)
		return
	end

	army_service.clear_army(player)
end

function PvPService.init(army_service_ref: any)
	army_service = army_service_ref
end

function PvPService.is_in_safe_zone(player: Player): boolean
	update_player_zone(player)
	return player:GetAttribute("PvPZone") == "SafeZone"
end

function PvPService.is_spawn_protected(player: Player): boolean
	local expires_at = player:GetAttribute("PvPProtectedUntil")
	return typeof(expires_at) == "number"
		and expires_at > server_now()
end

function PvPService.begin_spawn_protection(player: Player)
	set_boolean_until(
		player,
		"PvPProtectedUntil",
		"PvPProtected",
		SPAWN_PROTECTION_SECONDS
	)
end

function PvPService.clear_spawn_protection(player: Player)
	player:SetAttribute("PvPProtectedUntil", 0)
	player:SetAttribute("PvPProtected", false)
end

function PvPService.is_combat_tagged(player: Player): boolean
	local expires_at = player:GetAttribute("CombatTaggedUntil")
	return typeof(expires_at) == "number"
		and expires_at > server_now()
end

function PvPService.get_combat_seconds_remaining(
	player: Player
): number
	local expires_at = player:GetAttribute("CombatTaggedUntil")
	if typeof(expires_at) ~= "number" then
		return 0
	end
	return math.max(0, expires_at - server_now())
end

function PvPService.tag_combat(
	player: Player,
	opponent_user_id: number
)
	set_boolean_until(
		player,
		"CombatTaggedUntil",
		"CombatTagged",
		COMBAT_TAG_SECONDS
	)
	player:SetAttribute("LastPvPOpponentUserId", opponent_user_id)
end

function PvPService.can_damage(
	attacker_user_id: number,
	target: Model
): boolean
	local attacker = Players:GetPlayerByUserId(attacker_user_id)
	if not attacker then
		return false
	end

	if PvPService.is_in_safe_zone(attacker)
		or PvPService.is_spawn_protected(attacker)
	then
		return false
	end

	local victim = get_owner_player(target)
	if not victim then
		return true
	end
	if victim == attacker then
		return false
	end
	if PvPService.is_in_safe_zone(victim)
		or PvPService.is_spawn_protected(victim)
	then
		return false
	end

	return true
end

function PvPService.register_damage(
	attacker_user_id: number,
	target: Model
)
	local attacker = Players:GetPlayerByUserId(attacker_user_id)
	local victim = get_owner_player(target)
	if not attacker or not victim or attacker == victim then
		return
	end

	PvPService.tag_combat(attacker, victim.UserId)
	PvPService.tag_combat(victim, attacker.UserId)

	target:SetAttribute("LastPvPAttackerUserId", attacker.UserId)
	target:SetAttribute("LastPvPHitAt", server_now())
end

function PvPService.record_unit_death(model: Model)
	local victim_user_id = model:GetAttribute("ArmyOwnerUserId")
	local killer_user_id = model:GetAttribute("LastHitOwnerUserId")
	if typeof(victim_user_id) ~= "number"
		or typeof(killer_user_id) ~= "number"
		or victim_user_id == 0
		or killer_user_id == 0
		or victim_user_id == killer_user_id
	then
		return
	end

	local victim = Players:GetPlayerByUserId(victim_user_id)
	local killer = Players:GetPlayerByUserId(killer_user_id)

	if victim then
		increment_number_attribute(victim, "PvPUnitsLost")
	end
	if killer then
		increment_number_attribute(killer, "PvPUnitKills")
	end
end

function PvPService.can_enter_safe_zone(
	player: Player
): (boolean, number)
	local remaining = PvPService.get_combat_seconds_remaining(player)
	return remaining <= 0, remaining
end

function PvPService.mark_entered_arena(player: Player)
	player:SetAttribute("PvPZone", "Arena")
	PvPService.begin_spawn_protection(player)
end

function PvPService.mark_entered_safe_zone(player: Player)
	player:SetAttribute("PvPZone", "SafeZone")
	player:SetAttribute("CombatTaggedUntil", 0)
	player:SetAttribute("CombatTagged", false)
	PvPService.clear_spawn_protection(player)
end

function PvPService.start()
	if did_start then
		return
	end
	did_start = true

	Players.PlayerAdded:Connect(initialize_player)
	Players.PlayerRemoving:Connect(handle_player_removing)

	for _, player in ipairs(Players:GetPlayers()) do
		initialize_player(player)
	end

	zone_task = task.spawn(function()
		while did_start do
			for _, player in ipairs(Players:GetPlayers()) do
				update_player_zone(player)
				player:SetAttribute(
					"CombatTagged",
					PvPService.is_combat_tagged(player)
				)
				player:SetAttribute(
					"PvPProtected",
					PvPService.is_spawn_protected(player)
				)
			end
			task.wait(ZONE_REFRESH_SECONDS)
		end
	end)
end

function PvPService.stop()
	did_start = false
	if zone_task then
		task.cancel(zone_task)
		zone_task = nil
	end
end

return PvPService
