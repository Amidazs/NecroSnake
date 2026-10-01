--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local PlayerCombatService = {}

local REMOTE_NAME = "NecroMVP_Swing"
local TOOL_NAME = "Bone Sword"
local SWING_COOLDOWN = 0.42
local HITBOX_SIZE = Vector3.new(6, 5, 7)
local HITBOX_FORWARD_STUDS = 5
local DAMAGE = 18

local last_swing_by_user_id: { [number]: number } = {}
local did_start = false
local combat_feedback_remote: RemoteEvent? = nil

local function get_remote(): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = ReplicatedStorage
	return remote
end

local function has_tool(player: Player): boolean
	local character = player.Character
	if character and character:FindFirstChild(TOOL_NAME) then
		return true
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	return backpack ~= nil and backpack:FindFirstChild(TOOL_NAME) ~= nil
end

local function give_tool(player: Player)
	if has_tool(player) then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		backpack = player:WaitForChild("Backpack", 5) :: Backpack?
	end
	if not backpack then
		return
	end

	local tool = Instance.new("Tool")
	tool.Name = TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 4, 1)
	handle.Color = Color3.fromRGB(235, 235, 235)
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	tool.Parent = backpack
end

local function find_humanoid_model(inst: Instance): Model?
	local current: Instance? = inst
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function can_damage(player: Player, target: Model): boolean
	if target == player.Character then
		return false
	end

	local humanoid = target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local owner_user_id = target:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) == "number" and owner_user_id == player.UserId then
		return false
	end

	return true
end

local function compute_damage(target: Model): number
	local defense = target:GetAttribute("Defense")
	if typeof(defense) ~= "number" then
		defense = 0
	end

	defense = math.clamp(defense, 0, 0.9)
	return math.max(1, math.floor((DAMAGE * (1 - defense)) + 0.5))
end

local function apply_hit_reaction(attacker_root: BasePart, target: Model)
	local target_root = target:FindFirstChild("HumanoidRootPart")
	if not (target_root and target_root:IsA("BasePart")) then
		return
	end
	if target_root.Anchored then
		return
	end

	local direction = attacker_root.CFrame.LookVector
	target_root.AssemblyLinearVelocity += (direction * 5) + Vector3.new(0, 1.5, 0)
end

local function can_swing(player: Player): boolean
	local now = os.clock()
	local last = last_swing_by_user_id[player.UserId]
	if last and (now - last) < SWING_COOLDOWN then
		return false
	end

	last_swing_by_user_id[player.UserId] = now
	return true
end

local function handle_swing(player: Player)
	if not can_swing(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local tool = character:FindFirstChild(TOOL_NAME)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if not (root and root:IsA("BasePart")) then
		return
	end
	if not (tool and tool:IsA("Tool")) then
		return
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character }

	local hitbox_cframe = root.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_STUDS)
	local parts = Workspace:GetPartBoundsInBox(hitbox_cframe, HITBOX_SIZE, overlap)
	local seen: { [Model]: boolean } = {}
	local hit_count = 0
	local killed_any = false
	local feedback_position: Vector3? = nil
	local feedback_damage = 0
	local hit_targets: { Model } = {}

	for _, part in ipairs(parts) do
		local target = find_humanoid_model(part)
		if target and not seen[target] and can_damage(player, target) then
			seen[target] = true

			local target_humanoid = target:FindFirstChildOfClass("Humanoid")
			if target_humanoid then
				local damage = compute_damage(target)
				local health_before = target_humanoid.Health

				target:SetAttribute("LastDamageSourceKind", "PLAYER")
				target:SetAttribute("LastHitOwnerUserId", player.UserId)
				target:SetAttribute("LastHitTime", os.clock())
				target_humanoid:TakeDamage(damage)
				apply_hit_reaction(root, target)

				hit_count += 1
				table.insert(hit_targets, target)
				feedback_damage = math.max(feedback_damage, damage)
				killed_any = killed_any or (health_before > 0 and target_humanoid.Health <= 0)

				local target_root = target:FindFirstChild("HumanoidRootPart")
				if target_root and target_root:IsA("BasePart") then
					feedback_position = target_root.Position
				end
			end
		end
	end

	if hit_count > 0 and combat_feedback_remote then
		combat_feedback_remote:FireClient(player, {
			hitCount = hit_count,
			damage = feedback_damage,
			killed = killed_any,
			worldPosition = feedback_position,
			targets = hit_targets,
		})
	end
end

local function hook_player(player: Player)
	player.CharacterAdded:Connect(function()
		task.delay(0.25, function()
			if player.Parent then
				give_tool(player)
			end
		end)
	end)

	if player.Character then
		task.defer(give_tool, player)
	end
end
function PlayerCombatService.start()
	if did_start then
		return
	end
	did_start = true

	get_remote().OnServerEvent:Connect(handle_swing)
	combat_feedback_remote = Remotes.combat_feedback()
	Players.PlayerAdded:Connect(hook_player)
	Players.PlayerRemoving:Connect(function(player)
		last_swing_by_user_id[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		hook_player(player)
	end
end

return PlayerCombatService
