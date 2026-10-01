--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local CombatService = {}

local CORPSE_LIFETIME_SECONDS = 20
local CLAIM_SECONDS = 6
local MAX_FAILED_RAISES = 3
local RAISE_DISTANCE = 14
local RAISE_HOLD_SECONDS = 1.15
local BANISH_DISTANCE = 35
local SCAN_SECONDS = 0.5

local ATTR_CORPSE = "IsNecroCorpse"
local ATTR_CORPSE_CREATED = "CorpseCreatedAt"
local ATTR_CORPSE_EXPIRES = "CorpseExpiresAt"
local ATTR_CLAIM_USER_ID = "CorpseClaimUserId"
local ATTR_CLAIM_EXPIRES = "CorpseClaimExpiresAt"
local ATTR_RAISE_FAILURES = "RaiseFailures"
local ATTR_MAX_RAISE_FAILURES = "MaxRaiseFailures"

local army_service = nil :: any
local running = false
local scan_task: thread? = nil
local result_remote: RemoteEvent? = nil
local banish_remote: RemoteEvent? = nil
local processing: { [Model]: boolean } = {}
local container_connections: { [Instance]: RBXScriptConnection } = {}

local function server_now(): number
	return Workspace:GetServerTimeNow()
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return nil
end

local function get_player_root(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return get_root(character)
end

local function send_result(player: Player, payload: { [string]: any })
	if result_remote then
		result_remote:FireClient(player, payload)
	end
end

local function update_corpse_visual(model: Model, failures: number)
	local highlight = model:FindFirstChild("NecroCorpseHighlight")
	if not highlight or not highlight:IsA("Highlight") then
		highlight = Instance.new("Highlight")
		highlight.Name = "NecroCorpseHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency = 0.78
		highlight.OutlineTransparency = 0.15
		highlight.Parent = model
	end

	if failures <= 0 then
		highlight.FillColor = Color3.fromRGB(55, 190, 105)
		highlight.OutlineColor = Color3.fromRGB(145, 255, 180)
	elseif failures == 1 then
		highlight.FillColor = Color3.fromRGB(205, 165, 45)
		highlight.OutlineColor = Color3.fromRGB(255, 220, 105)
	else
		highlight.FillColor = Color3.fromRGB(190, 55, 55)
		highlight.OutlineColor = Color3.fromRGB(255, 120, 120)
	end
end

local function destroy_corpse(model: Model, reason: string)
	if model.Parent == nil then
		return
	end
	model:SetAttribute("CorpseEndReason", reason)
	local prompt = model:FindFirstChild("NecroRaisePrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	model:Destroy()
end

local function get_failures(model: Model): number
	local value = model:GetAttribute(ATTR_RAISE_FAILURES)
	if typeof(value) == "number" then
		return math.max(0, math.floor(value))
	end
	return 0
end

local function get_claim_owner(model: Model): number
	local value = model:GetAttribute(ATTR_CLAIM_USER_ID)
	if typeof(value) == "number" then
		return math.floor(value)
	end
	return 0
end

local function is_claimed_by_other(model: Model, player: Player): (boolean, number)
	local claim_owner = get_claim_owner(model)
	local claim_expires = model:GetAttribute(ATTR_CLAIM_EXPIRES)
	if claim_owner <= 0 or claim_owner == player.UserId then
		return false, 0
	end
	if typeof(claim_expires) ~= "number" then
		return false, 0
	end

	local remaining = claim_expires - server_now()
	return remaining > 0, math.max(0, remaining)
end

local function validate_raise_distance(player: Player, model: Model): boolean
	local player_root = get_player_root(player)
	local corpse_root = get_root(model)
	if not player_root or not corpse_root then
		return false
	end
	return (player_root.Position - corpse_root.Position).Magnitude <= RAISE_DISTANCE + 2
end

local function handle_raise(player: Player, model: Model)
	if processing[model] then
		return
	end
	if model.Parent == nil or model:GetAttribute(ATTR_CORPSE) ~= true then
		return
	end
	if not validate_raise_distance(player, model) then
		send_result(player, {
			kind = "raise",
			status = "TOO_FAR",
			message = "Move closer to the corpse.",
		})
		return
	end

	local expires_at = model:GetAttribute(ATTR_CORPSE_EXPIRES)
	if typeof(expires_at) == "number" and server_now() >= expires_at then
		destroy_corpse(model, "EXPIRED")
		return
	end

	local claimed, claim_remaining = is_claimed_by_other(model, player)
	if claimed then
		send_result(player, {
			kind = "raise",
			status = "CLAIMED",
			message = ("Soul claimed for %.1fs longer."):format(claim_remaining),
		})
		return
	end

	processing[model] = true
	local success, status, chance, command_cost =
		army_service.try_raise_dead(player, model)

	if status == "FULL" then
		local used = army_service.get_used_command_capacity(player)
		local maximum = army_service.get_command_capacity(player)
		send_result(player, {
			kind = "raise",
			status = status,
			chance = chance,
			commandCost = command_cost,
			usedCapacity = used,
			maxCapacity = maximum,
			message = (
				"Army full: %d/%d Command. This unit needs %d."
			):format(used, maximum, command_cost),
		})
		processing[model] = nil
		return
	end

	if success then
		send_result(player, {
			kind = "raise",
			status = "SUCCESS",
			chance = chance,
			commandCost = command_cost,
			message = ("Raise succeeded! (%d%% chance)"):format(
				math.floor(chance * 100 + 0.5)
			),
		})
		processing[model] = nil
		return
	end

	if status == "FAILED" and model.Parent ~= nil then
		local failures = get_failures(model) + 1
		model:SetAttribute(ATTR_RAISE_FAILURES, failures)
		update_corpse_visual(model, failures)

		local remaining_attempts = MAX_FAILED_RAISES - failures
		if remaining_attempts <= 0 then
			send_result(player, {
				kind = "raise",
				status = "DESTROYED",
				chance = chance,
				message = "The third Raise failed. The soul collapsed.",
			})
			processing[model] = nil
			task.delay(0.35, function()
				destroy_corpse(model, "THREE_FAILED_RAISES")
			end)
			return
		end

		send_result(player, {
			kind = "raise",
			status = "FAILED",
			chance = chance,
			failures = failures,
			attemptsRemaining = remaining_attempts,
			message = (
				"Raise failed. %d attempt%s remaining. (%d%% chance)"
			):format(
				remaining_attempts,
				remaining_attempts == 1 and "" or "s",
				math.floor(chance * 100 + 0.5)
			),
		})
	else
		send_result(player, {
			kind = "raise",
			status = status,
			message = "That corpse can no longer be raised.",
		})
	end

	processing[model] = nil
end

local function create_raise_prompt(model: Model, root: BasePart)
	local old = root:FindFirstChild("NecroRaisePrompt")
	if old then
		old:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "NecroRaisePrompt"
	prompt.ActionText = "Raise"
	prompt.ObjectText = model.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = RAISE_HOLD_SECONDS
	prompt.MaxActivationDistance = RAISE_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = root

	prompt.Triggered:Connect(function(player)
		handle_raise(player, model)
	end)
end

local function initialize_corpse(model: Model)
	if model:GetAttribute(ATTR_CORPSE) == true then
		return
	end
	if model:GetAttribute("WasBanished") == true then
		destroy_corpse(model, "BANISHED")
		return
	end

	local root = get_root(model)
	if not root then
		destroy_corpse(model, "NO_ROOT")
		return
	end

	local created = server_now()
	local claim_user_id = model:GetAttribute("LastHitOwnerUserId")
	if typeof(claim_user_id) ~= "number" then
		claim_user_id = 0
	end

	model:SetAttribute(ATTR_CORPSE, true)
	model:SetAttribute(ATTR_CORPSE_CREATED, created)
	model:SetAttribute(ATTR_CORPSE_EXPIRES, created + CORPSE_LIFETIME_SECONDS)
	model:SetAttribute(ATTR_CLAIM_USER_ID, claim_user_id)
	model:SetAttribute(ATTR_CLAIM_EXPIRES, created + CLAIM_SECONDS)
	model:SetAttribute(ATTR_RAISE_FAILURES, 0)
	model:SetAttribute(ATTR_MAX_RAISE_FAILURES, MAX_FAILED_RAISES)

	update_corpse_visual(model, 0)
	create_raise_prompt(model, root)

	task.delay(CLAIM_SECONDS, function()
		if model.Parent ~= nil and model:GetAttribute(ATTR_CORPSE) == true then
			model:SetAttribute("CorpseClaimOpen", true)
		end
	end)

	task.delay(CORPSE_LIFETIME_SECONDS, function()
		if model.Parent ~= nil and model:GetAttribute(ATTR_CORPSE) == true then
			destroy_corpse(model, "EXPIRED")
		end
	end)
end

local function attach_death_hook(model: Model)
	if model:GetAttribute("__combat_hooked") == true then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	model:SetAttribute("__combat_hooked", true)
	humanoid.Died:Connect(function()
		initialize_corpse(model)
	end)

	if humanoid.Health <= 0 then
		initialize_corpse(model)
	end
end

local function scan_and_hook(container: Instance)
	for _, inst in ipairs(container:GetDescendants()) do
		if inst:IsA("Model") then
			attach_death_hook(inst)
		end
	end
end

local function watch_container(container: Instance)
	if container_connections[container] then
		return
	end
	scan_and_hook(container)
	container_connections[container] = container.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			attach_death_hook(inst)
		end
	end)
end

local function handle_banish(player: Player, model: Instance)
	if not model:IsA("Model") then
		return
	end

	local root = get_root(model)
	local player_root = get_player_root(player)
	if not root or not player_root then
		return
	end
	if (root.Position - player_root.Position).Magnitude > BANISH_DISTANCE then
		send_result(player, {
			kind = "banish",
			status = "TOO_FAR",
			message = "Move closer to that unit to Banish it.",
		})
		return
	end

	local ok, message = army_service.banish_unit(player, model)
	send_result(player, {
		kind = "banish",
		status = ok and "SUCCESS" or "FAILED",
		message = message,
	})
end

function CombatService.init(army_service_module)
	army_service = army_service_module
end

function CombatService.start()
	if running then
		return
	end
	running = true

	result_remote = Remotes.necromancy_result()
	banish_remote = Remotes.banish_request()
	banish_remote.OnServerEvent:Connect(handle_banish)

	scan_task = task.spawn(function()
		while running do
			for _, folder_name in ipairs({
				"NPCs",
				"NPCGroups",
				"PlayerArmies",
			}) do
				local folder = Workspace:FindFirstChild(folder_name)
				if folder then
					watch_container(folder)
				end
			end
			task.wait(SCAN_SECONDS)
		end
	end)
end

function CombatService.stop()
	running = false
	if scan_task then
		task.cancel(scan_task)
		scan_task = nil
	end
	for container, connection in pairs(container_connections) do
		connection:Disconnect()
		container_connections[container] = nil
	end
end

return CombatService
