--!strict

local DEBUG_RAISE = true


local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CombatService = {}

local army_service = nil :: any
local running = false
local scan_task: thread? = nil

local npc_added_conn: RBXScriptConnection? = nil
local npc_groups_added_conn: RBXScriptConnection? = nil

local RAISE_RANGE = 80
local TICK_SECONDS = 0.5

-- If last-hit ownership is older than this, do not raise.
-- This avoids stale tags causing unexpected raises.
local LAST_HIT_TIMEOUT_SECONDS = 6.0

local function now(): number
	return os.clock()
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function is_alive_model(model: Model): boolean
	local hum = model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function is_player_in_range(player: Player, pos: Vector3): boolean
	local char = player.Character
	if not (char and is_alive_model(char)) then
		return false
	end

	local hrp = get_root(char)
	if not hrp then
		return false
	end

	return (hrp.Position - pos).Magnitude <= RAISE_RANGE
end

local function get_last_hit_player(model: Model): Player?
	local user_id = model:GetAttribute("LastHitOwnerUserId")
	local hit_time = model:GetAttribute("LastHitTime")

	if typeof(user_id) ~= "number" then
		return nil
	end

	if typeof(hit_time) ~= "number" then
		return nil
	end

	if (now() - hit_time) > LAST_HIT_TIMEOUT_SECONDS then
		return nil
	end

	local plr = Players:GetPlayerByUserId(user_id)
	if not plr then
		return nil
	end

	return plr
end

local function on_npc_died(model: Model)
	if DEBUG_RAISE then

	end

	if not army_service or typeof(army_service.try_raise_dead) ~= "function" then
		if DEBUG_RAISE then

		end
		return
	end

	local root = get_root(model)
	if not root then
		if DEBUG_RAISE then

		end
		return
	end

	local plr = get_last_hit_player(model)
	if not plr then
		if DEBUG_RAISE then

		end
		return
	end

	local char = plr.Character
	local dist = math.huge
	if char then
		local hrp = get_root(char)
		if hrp then
			dist = (hrp.Position - root.Position).Magnitude
		end
	end

	if not is_player_in_range(plr, root.Position) then
		if DEBUG_RAISE then

		end
		return
	end



	local ok, err = pcall(function()
		army_service.try_raise_dead(plr, model)
	end)

	if not ok then
		warn("[CombatService] try_raise_dead error:", err)
	end
end


local function attach_death_hook(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	hum.Died:Connect(function()
		on_npc_died(model)
	end)
end

local function maybe_hook_model(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	if inst:GetAttribute("__combat_hooked") == true then
		return
	end

	local hum = inst:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	inst:SetAttribute("__combat_hooked", true)
	attach_death_hook(inst)
end

local function scan_and_hook(container: Instance)
	for _, inst in ipairs(container:GetDescendants()) do
		maybe_hook_model(inst)
	end
end

function CombatService.init(army_service_module)
	army_service = army_service_module
end

function CombatService.start()
	if running then
		return
	end
	running = true

	scan_task = task.spawn(function()
		while running do
			local npc_folder = Workspace:FindFirstChild("NPCs")
			if npc_folder and npc_folder:IsA("Folder") then
				scan_and_hook(npc_folder)
				if not npc_added_conn then
					npc_added_conn = npc_folder.DescendantAdded:Connect(maybe_hook_model)
				end
			end

			local npc_groups = Workspace:FindFirstChild("NPCGroups")
			if npc_groups and npc_groups:IsA("Folder") then
				scan_and_hook(npc_groups)
				if not npc_groups_added_conn then
					npc_groups_added_conn = npc_groups.DescendantAdded:Connect(
						maybe_hook_model
					)
				end
			end

			task.wait(TICK_SECONDS)
		end
	end)
end

function CombatService.stop()
	running = false

	if scan_task then
		task.cancel(scan_task)
		scan_task = nil
	end

	if npc_added_conn then
		npc_added_conn:Disconnect()
		npc_added_conn = nil
	end

	if npc_groups_added_conn then
		npc_groups_added_conn:Disconnect()
		npc_groups_added_conn = nil
	end
end

return CombatService
