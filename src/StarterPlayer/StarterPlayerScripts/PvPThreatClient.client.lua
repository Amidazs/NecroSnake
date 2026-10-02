--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local SCOUT_DISTANCE = 125
local REFRESH_SECONDS = 0.25

local function get_root(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function get_number_attr(
	player: Player,
	name: string,
	default_value: number
): number
	local value = player:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return default_value
end

local function get_level_band(player: Player): string
	local level = math.max(
		1,
		math.floor(get_number_attr(player, "NecromancerLevel", 1))
	)
	local first = math.floor((level - 1) / 5) * 5 + 1
	return ("Lv %d-%d"):format(first, first + 4)
end

local function get_rebirth_band(player: Player): string
	local rebirths = math.max(
		0,
		math.floor(get_number_attr(player, "RebirthCount", 0))
	)

	if rebirths == 0 then
		return "No Rebirth"
	elseif rebirths <= 2 then
		return "Low Rebirth"
	elseif rebirths <= 5 then
		return "Seasoned"
	end
	return "Veteran"
end

local function get_army_threat(player: Player): string
	local used = math.max(
		0,
		get_number_attr(player, "UsedCommandCapacity", 0)
	)

	if used <= 0 then
		return "Army: None"
	elseif used <= 5 then
		return "Army: Small"
	elseif used <= 15 then
		return "Army: Growing"
	elseif used <= 35 then
		return "Army: Dangerous"
	elseif used <= 80 then
		return "Army: Massive"
	end
	return "Army: Horde"
end

--[[
	Returns whether a player shares the local player's party.

	Args:
		player (Player): Player to inspect.

	Returns:
		boolean: True when both players share a PartyId.
]]
local function is_party_member(player: Player): boolean
	local local_id = LOCAL_PLAYER:GetAttribute("PartyId")
	local other_id = player:GetAttribute("PartyId")
	return typeof(local_id) == "string"
		and local_id ~= ""
		and local_id == other_id
end

local function find_nearest_enemy(): (Player?, number)
	local local_root = get_root(LOCAL_PLAYER)
	if not local_root then
		return nil, math.huge
	end

	local best_player: Player? = nil
	local best_distance = SCOUT_DISTANCE

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LOCAL_PLAYER
			and not is_party_member(player)
			and player:GetAttribute("PvPZone") ~= "SafeZone"
		then
			local root = get_root(player)
			if root then
				local distance = (
					root.Position - local_root.Position
				).Magnitude
				if distance <= best_distance then
					best_player = player
					best_distance = distance
				end
			end
		end
	end

	return best_player, best_distance
end

local function make_label(
	parent: Instance,
	name: string,
	height: number,
	position_y: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 0, height)
	label.Position = UDim2.fromOffset(12, position_y)
	label.Font = Enum.Font.Gotham
	label.TextColor3 = Color3.fromRGB(225, 229, 235)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function create_gui(): (Frame, TextLabel, TextLabel, TextLabel)
	local player_gui = LOCAL_PLAYER:WaitForChild("PlayerGui")
	local old = player_gui:FindFirstChild("NecroPvPScoutGui")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "NecroPvPScoutGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player_gui

	local panel = Instance.new("Frame")
	panel.Name = "ScoutPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 22)
	panel.Size = UDim2.fromOffset(360, 104)
	panel.BackgroundColor3 = Color3.fromRGB(17, 20, 26)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(115, 79, 150)
	stroke.Transparency = 0.2
	stroke.Thickness = 1
	stroke.Parent = panel

	local title = make_label(panel, "Title", 26, 8)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(224, 190, 255)
	title.TextSize = 16

	local details = make_label(panel, "Details", 22, 38)
	local stats = make_label(panel, "Stats", 22, 64)

	return panel, title, details, stats
end

local function format_status(player: Player): string
	if player:GetAttribute("PvPProtected") == true then
		local until_time = get_number_attr(
			player,
			"PvPProtectedUntil",
			0
		)
		local remaining = math.max(
			0,
			until_time - Workspace:GetServerTimeNow()
		)
		return ("Warded %.0fs"):format(remaining)
	end

	if player:GetAttribute("CombatTagged") == true then
		return "In Combat"
	end
	return "Open"
end

local panel, title, details, stats = create_gui()
local accumulator = 0

RunService.Heartbeat:Connect(function(delta_time)
	accumulator += delta_time
	if accumulator < REFRESH_SECONDS then
		return
	end
	accumulator = 0

	if LOCAL_PLAYER:GetAttribute("PvPZone") == "SafeZone" then
		panel.Visible = false
		return
	end

	local target, distance = find_nearest_enemy()
	if not target then
		panel.Visible = false
		return
	end

	panel.Visible = true
	local relation = ""
	local friend_ok, friend = pcall(function()
		return LOCAL_PLAYER:IsFriendsWith(target.UserId)
	end)
	if friend_ok and friend then
		relation = " [FRIEND]"
	end
	title.Text = ("Scouting: %s%s"):format(
		target.DisplayName,
		relation
	)
	details.Text = ("%s   |   %s   |   %.0f studs"):format(
		get_level_band(target),
		get_rebirth_band(target),
		distance
	)
	stats.Text = ("%s   |   %s   |   Kills %d"):format(
		get_army_threat(target),
		format_status(target),
		math.floor(get_number_attr(target, "PvPKills", 0))
	)
end)
