--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer

local PLAYER_ARMIES_FOLDER_NAME = "PlayerArmies"
local HIGHLIGHT_NAME = "ArmyOutlineHighlight"
local UPDATE_SECONDS = 0.2

local CLOSE_DISTANCE = 95
local MID_DISTANCE = 230

local OUTLINE_COLOR = Color3.fromRGB(105, 220, 160)
local FILL_COLOR = Color3.fromRGB(55, 135, 95)

local tracked: { [Model]: Highlight } = {}
local update_accumulator = 0

local function is_owned_by_local_player(model: Model): boolean
	local owner_user_id = model:GetAttribute("ArmyOwnerUserId")
	return typeof(owner_user_id) == "number"
		and owner_user_id == LOCAL_PLAYER.UserId
end

local function is_army_unit(model: Model): boolean
	return model:GetAttribute("IsPlayerArmy") == true
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function remove_highlight(model: Model)
	local highlight = tracked[model]
	if highlight then
		highlight:Destroy()
		tracked[model] = nil
		return
	end

	local existing = model:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		existing:Destroy()
	end
end

local function get_or_create_highlight(model: Model): Highlight
	local tracked_highlight = tracked[model]
	if tracked_highlight and tracked_highlight.Parent ~= nil then
		return tracked_highlight
	end

	local existing = model:FindFirstChild(HIGHLIGHT_NAME)
	local highlight: Highlight
	if existing and existing:IsA("Highlight") then
		highlight = existing
	else
		highlight = Instance.new("Highlight")
		highlight.Name = HIGHLIGHT_NAME
		highlight.Parent = model
	end

	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineColor = OUTLINE_COLOR
	highlight.FillColor = FILL_COLOR
	tracked[model] = highlight
	return highlight
end

local function apply_outline_if_needed(model: Model)
	if not is_army_unit(model) or not is_owned_by_local_player(model) then
		remove_highlight(model)
		return
	end
	get_or_create_highlight(model)
end

local function hook_model(model: Model)
	if model:GetAttribute("__local_army_outline_hooked") == true then
		apply_outline_if_needed(model)
		return
	end

	model:SetAttribute("__local_army_outline_hooked", true)
	apply_outline_if_needed(model)

	model:GetAttributeChangedSignal("ArmyOwnerUserId"):Connect(function()
		apply_outline_if_needed(model)
	end)
	model:GetAttributeChangedSignal("IsPlayerArmy"):Connect(function()
		apply_outline_if_needed(model)
	end)
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			remove_highlight(model)
		else
			apply_outline_if_needed(model)
		end
	end)
end

local function scan_existing(root: Instance)
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Model") then
			hook_model(inst)
		end
	end
end

local function update_distance_readability()
	local character = LOCAL_PLAYER.Character
	local player_root = character and character:FindFirstChild("HumanoidRootPart")
	if not (player_root and player_root:IsA("BasePart")) then
		return
	end

	for model, highlight in pairs(tracked) do
		if model.Parent == nil or highlight.Parent == nil then
			tracked[model] = nil
			continue
		end

		local root = get_root(model)
		if not root then
			continue
		end

		local distance = (root.Position - player_root.Position).Magnitude
		if distance <= CLOSE_DISTANCE then
			highlight.OutlineTransparency = 0.28
			highlight.FillTransparency = 0.97
		elseif distance <= MID_DISTANCE then
			highlight.OutlineTransparency = 0.55
			highlight.FillTransparency = 1
		else
			highlight.OutlineTransparency = 0.82
			highlight.FillTransparency = 1
		end
	end
end

local function main()
	local player_armies = Workspace:WaitForChild(PLAYER_ARMIES_FOLDER_NAME)
	scan_existing(player_armies)

	player_armies.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			hook_model(inst)
		end
	end)

	player_armies.DescendantRemoving:Connect(function(inst)
		if inst:IsA("Model") then
			remove_highlight(inst)
		end
	end)

	RunService.Heartbeat:Connect(function(delta_time)
		update_accumulator += delta_time
		if update_accumulator < UPDATE_SECONDS then
			return
		end
		update_accumulator = 0
		update_distance_readability()
	end)
end

main()
