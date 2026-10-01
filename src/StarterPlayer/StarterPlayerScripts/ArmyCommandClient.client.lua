--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local command_remote = Remotes.army_command()

local gui = Instance.new("ScreenGui")
gui.Name = "NecroArmyCommandGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "CommandBar"
frame.AnchorPoint = Vector2.new(0.5, 1)
frame.Position = UDim2.new(0.5, 0, 1, -92)
frame.Size = UDim2.fromOffset(590, 76)
frame.BackgroundColor3 = Color3.fromRGB(14, 17, 19)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Parent = gui

local frame_corner = Instance.new("UICorner")
frame_corner.CornerRadius = UDim.new(0, 9)
frame_corner.Parent = frame

local frame_stroke = Instance.new("UIStroke")
frame_stroke.Color = Color3.fromRGB(83, 116, 103)
frame_stroke.Transparency = 0.25
frame_stroke.Thickness = 1.2
frame_stroke.Parent = frame

local status = Instance.new("TextLabel")
status.Name = "Status"
status.Position = UDim2.fromOffset(12, 6)
status.Size = UDim2.new(1, -24, 0, 20)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.TextSize = 13
status.TextColor3 = Color3.fromRGB(195, 212, 204)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Army: FOLLOW"
status.Parent = frame

local button_row = Instance.new("Frame")
button_row.Name = "Buttons"
button_row.Position = UDim2.fromOffset(10, 30)
button_row.Size = UDim2.new(1, -20, 0, 36)
button_row.BackgroundTransparency = 1
button_row.Parent = frame

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 7)
layout.Parent = button_row

local BUTTONS = {
	{ mode = "FOLLOW", text = "Follow" },
	{ mode = "MOVE", text = "Move Here" },
	{ mode = "HOLD", text = "Hold" },
	{ mode = "ATTACK", text = "Attack Target" },
	{ mode = "RETREAT", text = "Retreat" },
}

local buttons: { [string]: TextButton } = {}
local targeting_mode: string? = nil
local active_mode = "FOLLOW"

local function make_button(
	mode: string,
	text: string,
	layout_order: number
): TextButton
	local button = Instance.new("TextButton")
	button.Name = mode .. "Button"
	button.LayoutOrder = layout_order
	button.Size = UDim2.fromOffset(mode == "ATTACK" and 125 or 98, 34)
	button.BackgroundColor3 = Color3.fromRGB(29, 35, 34)
	button.BackgroundTransparency = 0.05
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(224, 230, 226)
	button.Text = text
	button.Parent = button_row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "ModeStroke"
	stroke.Color = Color3.fromRGB(80, 110, 98)
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = button

	buttons[mode] = button
	return button
end

local function update_button_states()
	for mode, button in pairs(buttons) do
		local selected = mode == active_mode
		button.BackgroundColor3 = selected
			and Color3.fromRGB(42, 82, 64)
			or Color3.fromRGB(29, 35, 34)
		local stroke = button:FindFirstChild("ModeStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Color = selected
				and Color3.fromRGB(110, 220, 165)
				or Color3.fromRGB(80, 110, 98)
			stroke.Transparency = selected and 0.08 or 0.45
		end
	end
end

local function show_marker(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "LocalArmyCommandMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.12, 4.5, 4.5)
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(85, 225, 160)
	marker.Transparency = 0.18
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = Workspace
	Debris:AddItem(marker, 0.8)
end

local function find_model_ancestor(instance: Instance?): Model?
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function raycast_from_screen(screen_position: Vector2): RaycastResult?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local ray = camera:ViewportPointToRay(screen_position.X, screen_position.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = false
	return Workspace:Raycast(ray.Origin, ray.Direction * 500, params)
end

local function begin_targeting(mode: string)
	targeting_mode = mode
	if mode == "MOVE" then
		status.Text = "MOVE: click the ground."
	else
		status.Text = "ATTACK: click an enemy."
	end
end

local function issue_immediate(mode: string)
	targeting_mode = nil
	command_remote:FireServer(mode)
end

for index, config in ipairs(BUTTONS) do
	local button = make_button(config.mode, config.text, index)
	button.MouseButton1Click:Connect(function()
		if config.mode == "MOVE" or config.mode == "ATTACK" then
			begin_targeting(config.mode)
		else
			issue_immediate(config.mode)
		end
	end)
end

local function consume_targeting_click(input: InputObject)
	local mode = targeting_mode
	if not mode then
		return
	end

	local result = raycast_from_screen(Vector2.new(input.Position.X, input.Position.Y))
	if not result then
		status.Text = "No valid target under cursor."
		return
	end

	if mode == "MOVE" then
		targeting_mode = nil
		show_marker(result.Position)
		command_remote:FireServer("MOVE", result.Position)
		return
	end

	if mode == "ATTACK" then
		local model = find_model_ancestor(result.Instance)
		if not model then
			status.Text = "ATTACK: click a living enemy."
			return
		end
		targeting_mode = nil
		command_remote:FireServer("ATTACK", model)
	end
end

UserInputService.InputBegan:Connect(function(input, game_processed)
	if game_processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape and targeting_mode then
		targeting_mode = nil
		status.Text = "Army: " .. active_mode
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		consume_targeting_click(input)
	end
end)

command_remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local mode = payload.mode
	if typeof(mode) == "string" then
		active_mode = mode
	end

	local message = payload.message
	if typeof(message) == "string" and message ~= "" then
		status.Text = message
	else
		status.Text = "Army: " .. active_mode
	end

	targeting_mode = nil
	update_button_states()
end)

player:GetAttributeChangedSignal("ArmyCommandMode"):Connect(function()
	local mode = player:GetAttribute("ArmyCommandMode")
	if typeof(mode) == "string" then
		active_mode = mode
		update_button_states()
	end
end)

local initial_mode = player:GetAttribute("ArmyCommandMode")
if typeof(initial_mode) == "string" then
	active_mode = initial_mode
end
update_button_states()
