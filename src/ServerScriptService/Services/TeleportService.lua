--!strict
-- TeleportService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TeleportService = {}

local SAFE_TELEPORT_DELAY_SECONDS = 10

local ZONES_FOLDER_NAME = "Zones"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local ARENA_MODEL_NAME = "ArenaWorld"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"
local ARENA_SPAWN_REGION_NAME = "ArenaSpawnRegion"

local did_start = false
local request_token_by_user_id: { [number]: number } = {}

local army_service = nil :: any
local backpack_service = nil :: any
local pvp_service = nil :: any

local function log(message: string)
	print("[TeleportService] " .. message)
end

local function get_zone_part(model_name: string, part_name: string): BasePart?
	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zones then
		return nil
	end

	local model = zones:FindFirstChild(model_name)
	if not model then
		return nil
	end

	local part = model:FindFirstChild(part_name)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function get_region_center_cframe(model_name: string, region_name: string): CFrame?
	local part = get_zone_part(model_name, region_name)
	if not part then
		return nil
	end

	-- Zone parts describe a volume; their top face is not a safe spawn height.
	-- Raycast from the zone centre X/Z down to the actual world surface.
	local origin = Vector3.new(
		part.Position.X,
		part.Position.Y + (part.Size.Y * 0.5),
		part.Position.Z
	)
	local direction = Vector3.new(0, -(part.Size.Y + 1000), 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { part }
	params.IgnoreWater = false

	local hit = Workspace:Raycast(origin, direction, params)
	if hit then
		return CFrame.new(hit.Position + Vector3.new(0, 6, 0))
	end

	return CFrame.new(part.Position)
end

local function teleport_player_to(player: Player, destination: string): (boolean, string)
	local character = player.Character
	if not character then
		return false, "Character missing."
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return false, "HumanoidRootPart missing."
	end

	local cf: CFrame? = nil

	if destination == "SafeZone" then
		cf = get_region_center_cframe(SAFE_ZONE_MODEL_NAME, SAFE_ZONE_REGION_NAME)
	elseif destination == "Arena" then
		cf = get_region_center_cframe(ARENA_MODEL_NAME, ARENA_SPAWN_REGION_NAME)
	else
		return false, "Invalid destination."
	end

	if not cf then
		return false, "Destination region not found."
	end

	hrp.CFrame = cf
	return true, ""
end

local function fire_result(player: Player, ok: boolean, message: string)
	Remotes.teleport_result():FireClient(player, ok, message)
end

local function next_token(user_id: number): number
	local current = request_token_by_user_id[user_id] or 0
	current += 1
	request_token_by_user_id[user_id] = current
	return current
end

local function is_token_current(user_id: number, token: number): boolean
	return (request_token_by_user_id[user_id] or 0) == token
end

local function stash_army_into_backpack(player: Player)
	-- Append the current army back into the backpack.
	-- Important: do NOT replace, otherwise any units left in the backpack
	-- (not deployed to the arena) would be lost.
	local snapshot = army_service.snapshot_and_clear_army(player)
	backpack_service.store_snapshot_append(player, snapshot)
end

local function deploy_backpack_into_world(player: Player)
	-- If the player has selected a loadout, deploy only that, keep rest.
	local selected = backpack_service.take_loadout_units(player)
	if selected and #selected > 0 then
		army_service.spawn_from_snapshot(player, selected)
		return
	end

	-- Otherwise deploy everything (old behavior).
	local snapshot = backpack_service.take_backpack(player)
	if not snapshot then
		return
	end

	army_service.spawn_from_snapshot(player, snapshot)
end

local function handle_safezone_request(player: Player)
	if pvp_service and pvp_service.can_enter_safe_zone then
		local allowed, remaining =
			pvp_service.can_enter_safe_zone(player)
		if not allowed then
			fire_result(
				player,
				false,
				("Combat-tagged for %.1fs."):format(remaining)
			)
			return
		end
	end

	local character = player.Character
	local root = character
		and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		fire_result(player, false, "Character missing.")
		return
	end

	local token = next_token(player.UserId)
	local start_position = root.Position

	fire_result(player, true, "Opening the veil... hold still (10s).")

	task.delay(SAFE_TELEPORT_DELAY_SECONDS, function()
		if not player.Parent then
			return
		end

		if not is_token_current(player.UserId, token) then
			return
		end

		local current_character = player.Character
		local current_root = current_character
			and current_character:FindFirstChild("HumanoidRootPart")
		local humanoid = current_character
			and current_character:FindFirstChildOfClass("Humanoid")
		if not (current_root and current_root:IsA("BasePart"))
			or not humanoid
			or humanoid.Health <= 0
		then
			fire_result(player, false, "Retreat cancelled.")
			return
		end

		if (current_root.Position - start_position).Magnitude > 4 then
			fire_result(
				player,
				false,
				"Retreat cancelled: you moved."
			)
			return
		end

		if pvp_service and pvp_service.can_enter_safe_zone then
			local allowed, remaining =
				pvp_service.can_enter_safe_zone(player)
			if not allowed then
				fire_result(
					player,
					false,
					("Retreat blocked by combat for %.1fs."):format(
						remaining
					)
				)
				return
			end
		end

		stash_army_into_backpack(player)

		local ok, err = teleport_player_to(player, "SafeZone")
		if not ok then
			fire_result(player, false, "Teleport failed: " .. err)
			return
		end

		if pvp_service and pvp_service.mark_entered_safe_zone then
			pvp_service.mark_entered_safe_zone(player)
		end
		fire_result(player, true, "You retreat to the sanctum.")
	end)
end

local function handle_arena_request(player: Player)
	next_token(player.UserId)

	local ok, err = teleport_player_to(player, "Arena")
	if not ok then
		fire_result(player, false, "Teleport failed: " .. err)
		return
	end

	deploy_backpack_into_world(player)
	if pvp_service and pvp_service.mark_entered_arena then
		pvp_service.mark_entered_arena(player)
	end
	fire_result(player, true, "You step through the veil into the arena.")
end

local function on_teleport_request(player: Player, destination: string)
	if destination == "SafeZone" then
		handle_safezone_request(player)
		return
	end

	if destination == "Arena" then
		handle_arena_request(player)
		return
	end

	fire_result(player, false, "Invalid destination.")
end

local function on_player_removing(player: Player)
	next_token(player.UserId)
	backpack_service.clear_backpack(player)
end

function TeleportService.init(
	army_service_ref: any,
	backpack_service_ref: any,
	pvp_service_ref: any?
)
	army_service = army_service_ref
	backpack_service = backpack_service_ref
	pvp_service = pvp_service_ref
end

function TeleportService.start()
	if did_start then
		return
	end

	did_start = true

	Remotes.teleport_request().OnServerEvent:Connect(on_teleport_request)
	Players.PlayerRemoving:Connect(on_player_removing)

	log("Ready.")
end

return TeleportService
