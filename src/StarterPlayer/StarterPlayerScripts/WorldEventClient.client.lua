--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local remote = Remotes.world_event()

local current_state = "INACTIVE"
local event_name = "Soulstorm"
local ends_at = 0
local notification_token = 0

local gui = Instance.new("ScreenGui")
gui.Name = "NecroWorldEventGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Name = "EventBanner"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, 18)
frame.Size = UDim2.fromOffset(430, 72)
frame.BackgroundColor3 = Color3.fromRGB(18, 15, 30)
frame.BackgroundTransparency = 0.12
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Transparency = 0.2
stroke.Color = Color3.fromRGB(125, 185, 255)
stroke.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 7)
title.Size = UDim2.new(1, -24, 0, 27)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 21
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame
local detail = Instance.new("TextLabel")
detail.Name = "Detail"
detail.BackgroundTransparency = 1
detail.Position = UDim2.fromOffset(12, 35)
detail.Size = UDim2.new(1, -24, 0, 28)
detail.Font = Enum.Font.Gotham
detail.TextColor3 = Color3.fromRGB(195, 215, 235)
detail.TextSize = 14
detail.TextWrapped = true
detail.TextXAlignment = Enum.TextXAlignment.Left
detail.Parent = frame

local notice = Instance.new("TextLabel")
notice.Name = "Notice"
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.new(0.5, 0, 0, 98)
notice.Size = UDim2.fromOffset(520, 42)
notice.BackgroundColor3 = Color3.fromRGB(15, 20, 30)
notice.BackgroundTransparency = 0.12
notice.BorderSizePixel = 0
notice.Font = Enum.Font.GothamBold
notice.TextColor3 = Color3.fromRGB(205, 230, 255)
notice.TextSize = 16
notice.TextWrapped = true
notice.Visible = false
notice.Parent = gui

local notice_corner = Instance.new("UICorner")
notice_corner.CornerRadius = UDim.new(0, 7)
notice_corner.Parent = notice
local function get_remaining_seconds(): number
	return math.max(
		0,
		ends_at - Workspace:GetServerTimeNow()
	)
end

local function render_state()
	if current_state == "INACTIVE" or current_state == "ENDED" then
		frame.Visible = false
		return
	end

	frame.Visible = true
	local remaining = math.ceil(get_remaining_seconds())
	if current_state == "WARNING" then
		title.Text = event_name .. " forming"
		detail.Text = (
			"Dangerous evolution zone opens in %ds. "
			.. "Only secured undead can transform."
		):format(remaining)
		stroke.Color = Color3.fromRGB(155, 110, 205)
		return
	end

	title.Text = event_name .. " active"
	detail.Text = (
		"%ds remaining - keep an eligible undead inside the storm "
		.. "long enough to evolve. Lightning can destroy it."
	):format(remaining)
	stroke.Color = Color3.fromRGB(90, 205, 255)
end

local function show_notice(message: string, is_loss: boolean)
	notification_token += 1
	local token = notification_token
	notice.Text = message
	notice.TextColor3 = if is_loss
		then Color3.fromRGB(255, 150, 150)
		else Color3.fromRGB(180, 235, 255)
	notice.Visible = true

	task.delay(5, function()
		if token == notification_token then
			notice.Visible = false
		end
	end)
end
remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local kind = payload.kind
	if kind == "STATE" then
		current_state = tostring(payload.state or "INACTIVE")
		event_name = tostring(payload.eventName or "Soulstorm")
		if typeof(payload.endsAt) == "number" then
			ends_at = payload.endsAt
		else
			ends_at = 0
		end
		render_state()
		return
	end

	if kind == "UNIT_EVOLVED" then
		show_notice(
			tostring(payload.message or "An undead evolved."),
			false
		)
	elseif kind == "UNIT_LOST" then
		show_notice(
			tostring(payload.message or "An undead was lost."),
			true
		)
	end
end)

RunService.RenderStepped:Connect(function()
	if current_state == "WARNING"
		or current_state == "ACTIVE"
	then
		render_state()
	end
end)
