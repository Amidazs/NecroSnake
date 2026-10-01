--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local result_remote = Remotes.necromancy_result()
local banish_remote = Remotes.banish_request()

local gui = Instance.new("ScreenGui")
gui.Name = "NecroNecromancyGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local capacity_label = Instance.new("TextLabel")
capacity_label.Name = "CommandCapacity"
capacity_label.AnchorPoint = Vector2.new(1, 0)
capacity_label.Position = UDim2.new(1, -18, 0, 18)
capacity_label.Size = UDim2.fromOffset(220, 36)
capacity_label.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
capacity_label.BackgroundTransparency = 0.18
capacity_label.BorderSizePixel = 0
capacity_label.TextColor3 = Color3.fromRGB(230, 230, 230)
capacity_label.TextStrokeTransparency = 0.55
capacity_label.Font = Enum.Font.GothamBold
capacity_label.TextSize = 17
capacity_label.Parent = gui

local capacity_corner = Instance.new("UICorner")
capacity_corner.CornerRadius = UDim.new(0, 7)
capacity_corner.Parent = capacity_label

local feedback = Instance.new("TextLabel")
feedback.Name = "NecromancyFeedback"
feedback.AnchorPoint = Vector2.new(0.5, 0)
feedback.Position = UDim2.new(0.5, 0, 0, 70)
feedback.Size = UDim2.fromOffset(560, 48)
feedback.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
feedback.BackgroundTransparency = 0.15
feedback.BorderSizePixel = 0
feedback.TextColor3 = Color3.fromRGB(235, 235, 235)
feedback.TextStrokeTransparency = 0.55
feedback.Font = Enum.Font.GothamBold
feedback.TextSize = 18
feedback.TextWrapped = true
feedback.Visible = false
feedback.Parent = gui

local feedback_corner = Instance.new("UICorner")
feedback_corner.CornerRadius = UDim.new(0, 8)
feedback_corner.Parent = feedback

local message_token = 0

local function update_capacity()
	local used = player:GetAttribute("UsedCommandCapacity")
	local maximum = player:GetAttribute("CommandCapacity")
	if typeof(used) ~= "number" then
		used = 0
	end
	if typeof(maximum) ~= "number" then
		maximum = 5
	end
	capacity_label.Text = ("Command: %d / %d"):format(used, maximum)
end

local function show_message(message: string, status: string?)
	message_token += 1
	local token = message_token
	feedback.Text = message

	if status == "SUCCESS" then
		feedback.TextColor3 = Color3.fromRGB(125, 255, 165)
	elseif status == "FAILED" or status == "DESTROYED" then
		feedback.TextColor3 = Color3.fromRGB(255, 145, 125)
	elseif status == "FULL" or status == "CLAIMED" then
		feedback.TextColor3 = Color3.fromRGB(255, 215, 105)
	else
		feedback.TextColor3 = Color3.fromRGB(235, 235, 235)
	end

	feedback.Visible = true
	task.delay(3.5, function()
		if message_token == token then
			feedback.Visible = false
		end
	end)
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

local function get_aimed_model(): Model?
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera then
		return nil
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
	if not result then
		return nil
	end
	return find_model_ancestor(result.Instance)
end

local function on_banish(
	_action_name: string,
	input_state: Enum.UserInputState,
	_input_object: InputObject
): Enum.ContextActionResult
	if input_state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	local target = get_aimed_model()
	if not target then
		show_message("Aim at one of your undead to Banish it.", "FAILED")
		return Enum.ContextActionResult.Sink
	end

	banish_remote:FireServer(target)
	return Enum.ContextActionResult.Sink
end

result_remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local message = payload.message
	if typeof(message) ~= "string" or message == "" then
		return
	end
	show_message(message, payload.status)
end)

player:GetAttributeChangedSignal("UsedCommandCapacity"):Connect(update_capacity)
player:GetAttributeChangedSignal("CommandCapacity"):Connect(update_capacity)
update_capacity()

ContextActionService:BindAction(
	"NecroBanish",
	on_banish,
	true,
	Enum.KeyCode.B,
	Enum.KeyCode.ButtonY
)
ContextActionService:SetTitle("NecroBanish", "Banish")
ContextActionService:SetPosition(
	"NecroBanish",
	UDim2.new(1, -130, 1, -210)
)
