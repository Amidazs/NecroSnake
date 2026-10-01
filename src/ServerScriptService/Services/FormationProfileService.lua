--!strict

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local FormationProfileService = {}

local STORE_NAME = "NecroSnakeFormationProfile_v1"
local SAVE_DEBOUNCE_SECONDS = 1.0

local ZONES_FOLDER_NAME = "Zones"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"

local VALID_COHORTS: { [string]: boolean } = {
	Frontline = true,
	SecondLine = true,
	Ranged = true,
	Flanks = true,
	RearGuard = true,
	PersonalGuard = true,
}

local model_library_service = nil :: any
local store: any = nil
local store_lookup_attempted = false
local did_start = false

type Profile = {
	assignments: { [string]: string },
	persistent: boolean,
	dirty: boolean,
	save_token: number,
}

local profiles_by_user_id: { [number]: Profile } = {}
local apply_template_to_live_units:
	((Player, string, string) -> ())? = nil

local function log(message: string)
	print("[FormationProfileService] " .. message)
end

local function get_store(): any
	if store then
		return store
	end
	if store_lookup_attempted then
		return nil
	end

	store_lookup_attempted = true
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return store
	end

	if not RunService:IsStudio() then
		warn("[FormationProfileService] DataStore unavailable: " .. tostring(result))
	end
	return nil
end

local function warnf(message: string)
	warn("[FormationProfileService] " .. message)
end

local function get_safe_zone_region(): BasePart?
	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	local safe_world = zones and zones:FindFirstChild(SAFE_ZONE_MODEL_NAME)
	local region = safe_world and safe_world:FindFirstChild(SAFE_ZONE_REGION_NAME)
	if region and region:IsA("BasePart") then
		return region
	end
	return nil
end

local function is_player_in_safe_zone(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local region = get_safe_zone_region()
	if not (root and root:IsA("BasePart") and region) then
		return false
	end

	local local_position = region.CFrame:PointToObjectSpace(root.Position)
	local half_size = region.Size * 0.5
	return math.abs(local_position.X) <= half_size.X
		and math.abs(local_position.Y) <= half_size.Y
		and math.abs(local_position.Z) <= half_size.Z
end

local function default_cohort_for_template(template_name: string): string
	if model_library_service and model_library_service.get_unit_stats then
		local stats = model_library_service.get_unit_stats(template_name)
		local cohort = stats and stats.DefaultCohort or nil
		if typeof(cohort) == "string" and VALID_COHORTS[cohort] then
			return cohort
		end
	end
	return "SecondLine"
end

local function list_template_names(): { string }
	if model_library_service and model_library_service.list_template_names then
		return model_library_service.list_template_names()
	end
	return {}
end

local function sanitize_assignments(raw: any): { [string]: string }
	local result: { [string]: string } = {}
	if typeof(raw) ~= "table" then
		return result
	end

	for template_name, cohort in pairs(raw) do
		if typeof(template_name) == "string"
			and typeof(cohort) == "string"
			and VALID_COHORTS[cohort]
		then
			result[template_name] = cohort
		end
	end
	return result
end

local function get_or_create_profile(player: Player): Profile
	local existing = profiles_by_user_id[player.UserId]
	if existing then
		return existing
	end

	local profile: Profile = {
		assignments = {},
		persistent = false,
		dirty = false,
		save_token = 0,
	}
	profiles_by_user_id[player.UserId] = profile
	return profile
end

local function build_snapshot(player: Player)
	local profile = get_or_create_profile(player)
	local templates = {}

	for _, template_name in ipairs(list_template_names()) do
		local default_cohort = default_cohort_for_template(template_name)
		local saved = profile.assignments[template_name]
		table.insert(templates, {
			name = template_name,
			cohort = saved or default_cohort,
			defaultCohort = default_cohort,
			overridden = saved ~= nil,
		})
	end

	return {
		kind = "SNAPSHOT",
		persistent = profile.persistent,
		inSafeZone = is_player_in_safe_zone(player),
		templates = templates,
	}
end

local function send_snapshot(player: Player)
	Remotes.formation_profile():FireClient(player, build_snapshot(player))
end

local function send_result(
	player: Player,
	ok: boolean,
	message: string
)
	Remotes.formation_profile():FireClient(player, {
		kind = "RESULT",
		ok = ok,
		message = message,
	})
end

local function load_profile(player: Player)
	local profile = get_or_create_profile(player)
	local key = tostring(player.UserId)
	local active_store = get_store()

	if not active_store then
		profile.assignments = {}
		profile.persistent = false
		player:SetAttribute("FormationProfileLoaded", true)
		player:SetAttribute("FormationProfilePersistent", false)
		return
	end

	local ok, data = pcall(function()
		return active_store:GetAsync(key)
	end)

	if ok then
		if typeof(data) == "table" then
			profile.assignments = sanitize_assignments(data.assignments)
		else
			profile.assignments = {}
		end
		profile.persistent = true
		log(("Loaded formation profile for %s."):format(player.Name))
	else
		profile.assignments = {}
		profile.persistent = false
		if not RunService:IsStudio() then
			warnf(("Load failed for %s: %s"):format(player.Name, tostring(data)))
		end
	end

	player:SetAttribute("FormationProfileLoaded", true)
	player:SetAttribute("FormationProfilePersistent", profile.persistent)

	if apply_template_to_live_units then
		for template_name, cohort in pairs(profile.assignments) do
			apply_template_to_live_units(player, template_name, cohort)
		end
	end
end

local function save_profile_now(player: Player): boolean
	local profile = profiles_by_user_id[player.UserId]
	if not profile then
		return true
	end
	if not profile.dirty then
		return true
	end

	local assignments_copy: { [string]: string } = {}
	for template_name, cohort in pairs(profile.assignments) do
		assignments_copy[template_name] = cohort
	end

	local active_store = get_store()
	if not active_store then
		profile.persistent = false
		player:SetAttribute("FormationProfilePersistent", false)
		return false
	end

	local ok, err = pcall(function()
		active_store:UpdateAsync(tostring(player.UserId), function()
			return {
				version = 1,
				assignments = assignments_copy,
			}
		end)
	end)

	if ok then
		profile.persistent = true
		profile.dirty = false
		player:SetAttribute("FormationProfilePersistent", true)
		return true
	end

	profile.persistent = false
	player:SetAttribute("FormationProfilePersistent", false)
	if not RunService:IsStudio() then
		warnf(("Save failed for %s: %s"):format(player.Name, tostring(err)))
	end
	return false
end

local function schedule_save(player: Player)
	local profile = get_or_create_profile(player)
	profile.save_token += 1
	local token = profile.save_token

	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		if not player.Parent then
			return
		end

		local current = profiles_by_user_id[player.UserId]
		if not current or current.save_token ~= token then
			return
		end
		save_profile_now(player)
	end)
end

local function find_template_name(requested: string): string?
	local normalized = string.gsub(string.lower(requested), "[%s_]+", "")
	for _, template_name in ipairs(list_template_names()) do
		local key = string.gsub(string.lower(template_name), "[%s_]+", "")
		if key == normalized then
			return template_name
		end
	end
	return nil
end

apply_template_to_live_units = function(
	player: Player,
	template_name: string,
	cohort: string
)
	local armies = Workspace:FindFirstChild("PlayerArmies")
	if not armies then
		return
	end

	for _, instance in ipairs(armies:GetDescendants()) do
		if instance:IsA("Model")
			and instance:GetAttribute("ArmyOwnerUserId") == player.UserId
			and instance:GetAttribute("TemplateName") == template_name
		then
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				instance:SetAttribute("Cohort", cohort)
			end
		end
	end
end

local function set_template_assignment(
	player: Player,
	template_name: string,
	cohort: string
)
	if not is_player_in_safe_zone(player) then
		send_result(
			player,
			false,
			"Formation defaults can only be edited in the Sanctum."
		)
		return
	end

	local canonical = find_template_name(template_name)
	if not canonical then
		send_result(player, false, "Unknown unit template.")
		return
	end
	if not VALID_COHORTS[cohort] then
		send_result(player, false, "Invalid cohort.")
		return
	end

	local profile = get_or_create_profile(player)
	profile.assignments[canonical] = cohort
	profile.dirty = true
	apply_template_to_live_units(player, canonical, cohort)
	schedule_save(player)

	send_result(
		player,
		true,
		("%s default set to %s."):format(canonical, cohort)
	)
	send_snapshot(player)
end

local function reset_template_assignment(
	player: Player,
	template_name: string
)
	if not is_player_in_safe_zone(player) then
		send_result(
			player,
			false,
			"Formation defaults can only be edited in the Sanctum."
		)
		return
	end

	local canonical = find_template_name(template_name)
	if not canonical then
		send_result(player, false, "Unknown unit template.")
		return
	end

	local profile = get_or_create_profile(player)
	profile.assignments[canonical] = nil
	profile.dirty = true

	local default_cohort = default_cohort_for_template(canonical)
	apply_template_to_live_units(player, canonical, default_cohort)
	schedule_save(player)

	send_result(
		player,
		true,
		("%s reset to %s."):format(canonical, default_cohort)
	)
	send_snapshot(player)
end

local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action == "REQUEST" then
		send_snapshot(player)
		return
	end

	if typeof(payload) ~= "table" then
		send_result(player, false, "Invalid formation request.")
		return
	end

	local template_name = payload.template
	if typeof(template_name) ~= "string" then
		send_result(player, false, "Choose a unit template.")
		return
	end

	if action == "SET_TEMPLATE" then
		local cohort = payload.cohort
		if typeof(cohort) ~= "string" then
			send_result(player, false, "Choose a cohort.")
			return
		end
		set_template_assignment(player, template_name, cohort)
		return
	end

	if action == "RESET_TEMPLATE" then
		reset_template_assignment(player, template_name)
	end
end

function FormationProfileService.init(model_library: any)
	model_library_service = model_library
end

function FormationProfileService.get_cohort_for_template(
	player: Player,
	template_name: string
): string
	local profile = get_or_create_profile(player)
	local saved = profile.assignments[template_name]
	if saved and VALID_COHORTS[saved] then
		return saved
	end
	return default_cohort_for_template(template_name)
end

function FormationProfileService.start()
	if did_start then
		return
	end
	did_start = true

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load_profile, player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(load_profile, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		save_profile_now(player)
		profiles_by_user_id[player.UserId] = nil
	end)

	Remotes.formation_profile().OnServerEvent:Connect(handle_remote)

	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save_profile_now(player)
		end
	end)

	log("Ready.")
end

return FormationProfileService
