--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer

local PLAYER_ARMIES_FOLDER_NAME = "PlayerArmies"
local HIGHLIGHT_NAME = "ArmyOutlineHighlight"

-- Change this to whatever you want your outline colour to be.
local OUTLINE_COLOR = Color3.fromRGB(0, 255, 255)
local OUTLINE_TRANSPARENCY = 0
local FILL_TRANSPARENCY = 1

local function is_owned_by_local_player(model: Model): boolean
	local owner_user_id = model:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) ~= "number" then
		return false
	end
	return owner_user_id == LOCAL_PLAYER.UserId
end

local function is_army_unit(model: Model): boolean
	return model:GetAttribute("IsPlayerArmy") == true
end

local function get_or_create_highlight(model: Model): Highlight
	local existing = model:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		return existing
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = model
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	return highlight
end

local function remove_highlight(model: Model)
	local existing = model:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then
		existing:Destroy()
	end
end

local function apply_outline_if_needed(model: Model)
	if not is_army_unit(model) then
		remove_highlight(model)
		return
	end

	if not is_owned_by_local_player(model) then
		remove_highlight(model)
		return
	end

	local highlight = get_or_create_highlight(model)
	highlight.OutlineColor = OUTLINE_COLOR
	highlight.OutlineTransparency = OUTLINE_TRANSPARENCY
	highlight.FillTransparency = FILL_TRANSPARENCY
end

local function hook_model(model: Model)
	apply_outline_if_needed(model)

	model:GetAttributeChangedSignal("ArmyOwnerUserId"):Connect(function()
		apply_outline_if_needed(model)
	end)

	model:GetAttributeChangedSignal("IsPlayerArmy"):Connect(function()
		apply_outline_if_needed(model)
	end)

	model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			return
		end
		apply_outline_if_needed(model)
	end)
end

local function scan_existing(root: Instance)
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Model") then
			hook_model(inst)
		end
	end
end

local function main()
	local player_armies = Workspace:WaitForChild(PLAYER_ARMIES_FOLDER_NAME)

	-- Existing units
	scan_existing(player_armies)

	-- Future units
	player_armies.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			hook_model(inst)
		end
	end)

	-- Cleanup when models go away
	player_armies.DescendantRemoving:Connect(function(inst)
		if inst:IsA("Model") then
			remove_highlight(inst)
		end
	end)
end

main()
