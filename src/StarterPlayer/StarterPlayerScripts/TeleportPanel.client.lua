--!strict
-- TeleportPanel.client.lua (DEBUG)
-- Adds loud debugging to explain:
-- - Why button is hidden (region missing / root missing / outside regions)
-- - Why two UIs exist (prints which scripts are creating UIs + lists PlayerGui)
--
-- FIX: Avoid "Unknown" when distant region parts are not replicated (streaming).
-- We no longer require BOTH SafeZoneRegion and ArenaSpawnRegion to exist.
-- We detect the current zone from whichever region is available, and fall back
-- to coordinate bounds if region parts are missing locally.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

local DEBUG = true
local GUI_NAME = "NecroTeleportGui" -- this script will always create THIS one

local ZONES_FOLDER_NAME = "Zones"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local ARENA_MODEL_NAME = "ArenaWorld"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"
local ARENA_SPAWN_REGION_NAME = "ArenaSpawnRegion"

local REFRESH_SECONDS = 0.5

-- Arena definition (you stated: 0,0,0 to 2000x2000)
local ARENA_MIN_X = 0
local ARENA_MAX_X = 2000
local ARENA_MIN_Z = 0
local ARENA_MAX_Z = 2000

-- Safe zone fallback bounds.
-- IMPORTANT: If your safezone is not centred at 3600,3600 or size 1200x1200,
-- update these numbers to match your WorldBootstrap placement.
local SAFE_ZONE_CENTER_X = 3600
local SAFE_ZONE_CENTER_Z = 3600
local SAFE_ZONE_SIZE_X = 1200
local SAFE_ZONE_SIZE_Z = 1200

local function dprint(message: string)
	if DEBUG then
		print("[TeleportUI] " .. message)
	end
end

local function dwarn(message: string)
	if DEBUG then
		warn("[TeleportUI] " .. message)
	end
end

local function list_player_guis(player_gui: PlayerGui, label: string)
	if not DEBUG then
		return
	end

	local names = {}
	for _, child in ipairs(player_gui:GetChildren()) do
		if child:IsA("ScreenGui") then
			table.insert(names, child.Name)
		end
	end

	dprint(
		label
			.. " ScreenGuis ("
			.. tostring(#names)
			.. "): "
			.. table.concat(names, ", ")
	)
end

local function get_region_part(model_name: string, part_name: string): BasePart?
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

local function is_point_in_part_bounds(part: BasePart, world_pos: Vector3): boolean
	local local_pos = part.CFrame:PointToObjectSpace(world_pos)
	local half = part.Size * 0.5

	return math.abs(local_pos.X) <= half.X
		and math.abs(local_pos.Y) <= half.Y
		and math.abs(local_pos.Z) <= half.Z
end

local function is_in_arena_bounds(pos: Vector3): boolean
	return pos.X >= ARENA_MIN_X
		and pos.X <= ARENA_MAX_X
		and pos.Z >= ARENA_MIN_Z
		and pos.Z <= ARENA_MAX_Z
end

local function is_in_safe_bounds(pos: Vector3): boolean
	local half_x = SAFE_ZONE_SIZE_X * 0.5
	local half_z = SAFE_ZONE_SIZE_Z * 0.5

	return pos.X >= (SAFE_ZONE_CENTER_X - half_x)
		and pos.X <= (SAFE_ZONE_CENTER_X + half_x)
		and pos.Z >= (SAFE_ZONE_CENTER_Z - half_z)
		and pos.Z <= (SAFE_ZONE_CENTER_Z + half_z)
end

local function get_zone_and_reason(): (string, string)
	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if not zones then
		return "Unknown", "Workspace/Zones missing"
	end

	local character = player.Character
	if not character then
		return "Unknown", "Character missing"
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return "Unknown", "HumanoidRootPart missing"
	end

	local pos = root.Position

	-- Prefer region checks when available.
	local safe_region = get_region_part(SAFE_ZONE_MODEL_NAME, SAFE_ZONE_REGION_NAME)
	if safe_region and is_point_in_part_bounds(safe_region, pos) then
		return "SafeZone", "Inside SafeZoneRegion"
	end

	local arena_region = get_region_part(ARENA_MODEL_NAME, ARENA_SPAWN_REGION_NAME)
	if arena_region and is_point_in_part_bounds(arena_region, pos) then
		return "Arena", "Inside ArenaSpawnRegion"
	end

	-- Streaming/replication fallback: decide based on coordinates.
	if is_in_safe_bounds(pos) then
		return "SafeZone", "Region not loaded; using safe bounds"
	end

	if is_in_arena_bounds(pos) then
		return "Arena", "Region not loaded; using arena bounds"
	end

	-- Helpful debug if parts are missing locally
	if not safe_region and not arena_region then
		return "Unknown", "Both regions missing (streaming?)"
	end

	if not safe_region then
		return "Unknown", "SafeZoneRegion missing (streaming?)"
	end

	if not arena_region then
		return "Unknown", "ArenaSpawnRegion missing (streaming?)"
	end

	return "Unknown", "Outside zones"
end

local function destroy_existing_gui(player_gui: PlayerGui)
	local existing = player_gui:FindFirstChild(GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		dwarn("Destroying existing GUI with same name: " .. GUI_NAME)
		existing:Destroy()
	end
end

local function create_ui(player_gui: PlayerGui): ScreenGui
	destroy_existing_gui(player_gui)

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = player_gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.fromScale(0.985, 0.965)
	root.Size = UDim2.fromOffset(300, 140)
	root.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	root.BackgroundTransparency = 0.12
	root.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Transparency = 0.28
	stroke.Color = Color3.fromRGB(80, 255, 170)
	stroke.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromOffset(280, 24)
	title.Position = UDim2.fromOffset(12, 10)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(210, 255, 235)
	title.Text = "Veil Gate"
	title.Parent = root

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.fromOffset(280, 18)
	status.Position = UDim2.fromOffset(12, 34)
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextColor3 = Color3.fromRGB(170, 200, 190)
	status.Text = "Location: ..."
	status.Parent = root

	local button = Instance.new("TextButton")
	button.Name = "TeleportButton"
	button.Size = UDim2.fromOffset(276, 42)
	button.Position = UDim2.fromOffset(12, 58)
	button.Text = "Locating..."
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.fromRGB(235, 255, 245)
	button.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	button.AutoButtonColor = true
	button.Parent = root

	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.BackgroundTransparency = 1
	toast.Size = UDim2.fromOffset(276, 18)
	toast.Position = UDim2.fromOffset(12, 104)
	toast.Font = Enum.Font.Gotham
	toast.TextSize = 13
	toast.TextXAlignment = Enum.TextXAlignment.Left
	toast.TextColor3 = Color3.fromRGB(255, 200, 120)
	toast.Text = ""
	toast.Parent = root

	local debug_line = Instance.new("TextLabel")
	debug_line.Name = "Debug"
	debug_line.BackgroundTransparency = 1
	debug_line.Size = UDim2.fromOffset(276, 16)
	debug_line.Position = UDim2.fromOffset(12, 122)
	debug_line.Font = Enum.Font.Gotham
	debug_line.TextSize = 12
	debug_line.TextXAlignment = Enum.TextXAlignment.Left
	debug_line.TextColor3 = Color3.fromRGB(120, 140, 135)
	debug_line.Text = ""
	debug_line.Parent = root

	local pulse = TweenService:Create(
		stroke,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.08 }
	)
	pulse:Play()

	return gui
end

-- ===== Startup debugging =====
dprint("Script running from: " .. script:GetFullName())

local player_gui = player:WaitForChild("PlayerGui")
list_player_guis(player_gui, "BEFORE creating GUI")

local gui = create_ui(player_gui)
list_player_guis(player_gui, "AFTER creating GUI")

local root = gui:WaitForChild("Root") :: Frame
local button = root:WaitForChild("TeleportButton") :: TextButton
local toast = root:WaitForChild("Toast") :: TextLabel
local status = root:WaitForChild("Status") :: TextLabel
local debug_line = root:WaitForChild("Debug") :: TextLabel

local current_destination: string? = nil
local button_enabled = false
local last_zone: string? = nil
local last_reason: string? = nil

local function set_toast(text: string, ok: boolean)
	toast.Text = text
	if ok then
		toast.TextColor3 = Color3.fromRGB(160, 255, 200)
	else
		toast.TextColor3 = Color3.fromRGB(255, 170, 140)
	end
end

local function set_button_enabled(enabled: boolean)
	button_enabled = enabled
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.BackgroundTransparency = enabled and 0 or 0.2
	button.TextTransparency = enabled and 0 or 0.15
end

local function update_button()
	local zone, reason = get_zone_and_reason()

	status.Text = "Location: " .. zone
	debug_line.Text = reason

	if zone ~= last_zone or reason ~= last_reason then
		dprint("Zone=" .. zone .. " | " .. reason)
		last_zone = zone
		last_reason = reason
	end

	if zone == "SafeZone" then
		current_destination = "Arena"
		button.Text = "Enter Arena"
		set_button_enabled(true)
		return
	end

	if zone == "Arena" then
		current_destination = "SafeZone"
		button.Text = "Return to Sanctum"
		set_button_enabled(true)
		return
	end

	current_destination = nil
	button.Text = "Locating..."
	set_button_enabled(false)
end

button.MouseButton1Click:Connect(function()
	if not button_enabled or not current_destination then
		dwarn("Click ignored (button disabled or destination nil).")
		return
	end

	dprint("Teleport requested to: " .. current_destination)
	set_toast("Channeling...", true)
	Remotes.teleport_request():FireServer(current_destination)
end)

Remotes.teleport_result().OnClientEvent:Connect(function(ok: boolean, message: string)
	dprint("Teleport result ok=" .. tostring(ok) .. " msg=" .. message)
	set_toast(message, ok)
	task.delay(0.25, update_button)
end)

player.CharacterAdded:Connect(function()
	dprint("CharacterAdded fired.")
	task.wait(0.35)
	set_toast("", true)
	update_button()
end)

task.spawn(function()
	while true do
		update_button()
		task.wait(REFRESH_SECONDS)
	end
end)
