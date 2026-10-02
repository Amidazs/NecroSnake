--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")

local GUI_NAME = "NecroSocialGui"
local RELATION_GUI_NAME = "NecroSocialRelation"
local REFRESH_SECONDS = 0.75

local latest_party: any = nil
local friend_cache: { [number]: boolean } = {}
local refresh_accumulator = 0

--[[
	Returns whether another player is a Roblox friend.

	Args:
		player (Player): Player to inspect.

	Returns:
		boolean: True when Roblox friendship is confirmed.
]]
local function is_friend(player: Player): boolean
	local cached = friend_cache[player.UserId]
	if cached ~= nil then
		return cached
	end

	local ok, result = pcall(function()
		return LOCAL_PLAYER:IsFriendsWith(player.UserId)
	end)
	local value = ok and result == true
	friend_cache[player.UserId] = value
	return value
end

--[[
	Returns whether another player is in the local player's party.

	Args:
		player (Player): Player to inspect.

	Returns:
		boolean: True when both share a non-empty PartyId.
]]
local function is_party_member(player: Player): boolean
	local local_id = LOCAL_PLAYER:GetAttribute("PartyId")
	local other_id = player:GetAttribute("PartyId")
	return typeof(local_id) == "string"
		and local_id ~= ""
		and local_id == other_id
end

--[[
	Returns the relation label for another player.

	Args:
		player (Player): Player to inspect.

	Returns:
		string?: PARTY, FRIEND or nil.
]]
local function get_relation(player: Player): string?
	if player == LOCAL_PLAYER then
		return nil
	end
	if is_party_member(player) then
		return "PARTY"
	end
	if is_friend(player) then
		return "FRIEND"
	end
	return nil
end

--[[
	Removes an existing world relation label from a character.

	Args:
		character (Model): Character to clean.

	Returns:
		None.
]]
local function clear_relation_label(character: Model)
	local old = character:FindFirstChild(
		RELATION_GUI_NAME,
		true
	)
	if old then
		old:Destroy()
	end
end

--[[
	Updates one player's overhead social indicator.

	Args:
		player (Player): Player whose character should be labelled.

	Returns:
		None.
]]
local function update_relation_label(player: Player)
	local character = player.Character
	if not character then
		return
	end

	clear_relation_label(character)
	local relation = get_relation(player)
	if not relation then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = RELATION_GUI_NAME
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(105, 24)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(13, 15, 20)
	label.BackgroundTransparency = 0.18
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = relation
	label.TextColor3 = if relation == "PARTY"
		then Color3.fromRGB(128, 245, 173)
		else Color3.fromRGB(133, 199, 255)
	label.TextSize = 12
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label
end

--[[
	Refreshes all visible player relationship labels.

	Args:
		None.

	Returns:
		None.
]]
local function refresh_relation_labels()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LOCAL_PLAYER then
			update_relation_label(player)
		end
	end
end

--[[
	Creates a standard text label for the social panel.

	Args:
		parent (Instance): Parent UI object.
		name (string): Instance name.
		y (number): Y offset.
		height (number): Label height.

	Returns:
		TextLabel: Created label.
]]
local function make_label(
	parent: Instance,
	name: string,
	y: number,
	height: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(14, y)
	label.Size = UDim2.new(1, -28, 0, height)
	label.Font = Enum.Font.Gotham
	label.TextColor3 = Color3.fromRGB(226, 229, 235)
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

--[[
	Creates a reusable social-panel button.

	Args:
		parent (Instance): Parent UI object.
		name (string): Instance name.
		text (string): Button caption.
		position (UDim2): Button position.
		size (UDim2): Button size.

	Returns:
		TextButton: Created button.
]]
local function make_button(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = size
	button.BackgroundColor3 = Color3.fromRGB(31, 34, 43)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(233, 235, 241)
	button.TextSize = 13
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	return button
end

--[[
	Creates the Phase 11 social and party interface.

	Args:
		None.

	Returns:
		table: Important UI references.
]]
local function create_ui(): any
	local old = PLAYER_GUI:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = PLAYER_GUI

	local toggle = make_button(
		gui,
		"SocialToggle",
		"Social / Party",
		UDim2.new(0, 14, 1, -50),
		UDim2.fromOffset(138, 36)
	)

	local panel = Instance.new("Frame")
	panel.Name = "SocialPanel"
	panel.Position = UDim2.new(0, 14, 1, -458)
	panel.Size = UDim2.fromOffset(390, 398)
	panel.BackgroundColor3 = Color3.fromRGB(14, 16, 22)
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panel_corner = Instance.new("UICorner")
	panel_corner.CornerRadius = UDim.new(0, 10)
	panel_corner.Parent = panel

	local title = make_label(panel, "Title", 10, 26)
	title.Font = Enum.Font.GothamBold
	title.Text = "Necromancer Social"
	title.TextSize = 18

	local match = make_label(panel, "Matchmaking", 40, 22)
	match.TextColor3 = Color3.fromRGB(194, 167, 233)

	local party = make_label(panel, "PartyStatus", 64, 22)

	local friend_box = Instance.new("TextBox")
	friend_box.Name = "FriendUsername"
	friend_box.Position = UDim2.fromOffset(14, 94)
	friend_box.Size = UDim2.fromOffset(238, 34)
	friend_box.BackgroundColor3 = Color3.fromRGB(23, 26, 34)
	friend_box.BorderSizePixel = 0
	friend_box.ClearTextOnFocus = false
	friend_box.Font = Enum.Font.Gotham
	friend_box.PlaceholderText = "Friend Roblox username"
	friend_box.Text = ""
	friend_box.TextColor3 = Color3.fromRGB(235, 236, 240)
	friend_box.TextSize = 13
	friend_box.Parent = panel

	local box_corner = Instance.new("UICorner")
	box_corner.CornerRadius = UDim.new(0, 6)
	box_corner.Parent = friend_box

	local join_friend = make_button(
		panel,
		"JoinFriend",
		"Join Friend",
		UDim2.fromOffset(260, 94),
		UDim2.fromOffset(116, 34)
	)

	local leave = make_button(
		panel,
		"LeaveParty",
		"Leave Party",
		UDim2.fromOffset(260, 136),
		UDim2.fromOffset(116, 30)
	)

	local status = make_label(panel, "Status", 136, 30)
	status.Size = UDim2.new(1, -144, 0, 30)
	status.TextColor3 = Color3.fromRGB(245, 199, 130)
	status.TextWrapped = true

	local list = Instance.new("ScrollingFrame")
	list.Name = "PlayerList"
	list.Position = UDim2.fromOffset(14, 176)
	list.Size = UDim2.new(1, -28, 1, -190)
	list.BackgroundColor3 = Color3.fromRGB(19, 22, 29)
	list.BackgroundTransparency = 0.15
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel

	local list_layout = Instance.new("UIListLayout")
	list_layout.Padding = UDim.new(0, 5)
	list_layout.SortOrder = Enum.SortOrder.LayoutOrder
	list_layout.Parent = list

	toggle.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			Remotes.party_action():FireServer("REQUEST", {})
			Remotes.matchmaking_action():FireServer(
				"REQUEST",
				{}
			)
		end
	end)

	join_friend.Activated:Connect(function()
		if friend_box.Text == "" then
			status.Text = "Enter a Roblox username first."
			return
		end
		Remotes.matchmaking_action():FireServer(
			"JOIN_FRIEND",
			{
				username = friend_box.Text,
			}
		)
	end)

	leave.Activated:Connect(function()
		Remotes.party_action():FireServer("LEAVE", {})
	end)

	return {
		gui = gui,
		panel = panel,
		match = match,
		party = party,
		status = status,
		list = list,
		leave = leave,
	}
end

local ui = create_ui()

--[[
	Returns whether a user ID appears in the current party snapshot.

	Args:
		user_id (number): User ID to find.

	Returns:
		boolean: True when present.
]]
local function snapshot_has_member(user_id: number): boolean
	if not latest_party
		or typeof(latest_party.members) ~= "table"
	then
		return false
	end

	for _, member in ipairs(latest_party.members) do
		if member.userId == user_id then
			return true
		end
	end
	return false
end

--[[
	Clears dynamic player/invite rows from the social list.

	Args:
		None.

	Returns:
		None.
]]
local function clear_rows()
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

--[[
	Creates one social-list row.

	Args:
		name (string): Row display name.
		button_text (string): Action caption.
		callback (() -> ()): Button action.

	Returns:
		None.
]]
local function add_row(
	name: string,
	button_text: string,
	callback: () -> ()
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 38)
	row.BackgroundTransparency = 1
	row.Parent = ui.list

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -122, 1, 0)
	label.Font = Enum.Font.Gotham
	label.Text = name
	label.TextColor3 = Color3.fromRGB(220, 223, 230)
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	local button = make_button(
		row,
		"Action",
		button_text,
		UDim2.new(1, -112, 0, 3),
		UDim2.fromOffset(108, 32)
	)
	button.Activated:Connect(callback)
end

--[[
	Renders party invitations and current-server players.

	Args:
		None.

	Returns:
		None.
]]
local function render_rows()
	clear_rows()

	if latest_party
		and typeof(latest_party.invites) == "table"
	then
		for _, invite in ipairs(latest_party.invites) do
			add_row(
				("Invite from %s"):format(
					tostring(invite.fromName)
				),
				"Accept",
				function()
					Remotes.party_action():FireServer(
						"ACCEPT",
						{
							userId = invite.fromUserId,
						}
					)
				end
			)
		end
	end

	local local_leader = latest_party
		and latest_party.leaderUserId
		== LOCAL_PLAYER.UserId

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LOCAL_PLAYER then
			local relation = get_relation(player)
			local suffix = relation
				and (" [" .. relation .. "]")
				or ""
			local action = if snapshot_has_member(player.UserId)
				then "In Party"
				else "Invite"

			add_row(
				player.DisplayName .. suffix,
				action,
				function()
					if not local_leader
						and LOCAL_PLAYER:GetAttribute("PartyId")
							~= ""
					then
						ui.status.Text =
							"Only the party leader can invite."
						return
					end
					if not snapshot_has_member(
						player.UserId
					) then
						Remotes.party_action():FireServer(
							"INVITE",
							{
								userId = player.UserId,
							}
						)
					end
				end
			)
		end
	end
end

--[[
	Updates the top-level party and matchmaking labels.

	Args:
		None.

	Returns:
		None.
]]
local function update_summary()
	local score = LOCAL_PLAYER:GetAttribute("MatchStrength")
	local band = LOCAL_PLAYER:GetAttribute("MatchBandName")
	ui.match.Text = ("Matchmaking: %s | Strength %s | Target 8")
		:format(
			tostring(band or "Calculating"),
			tostring(score or "?")
		)

	local party_id = LOCAL_PLAYER:GetAttribute("PartyId")
	local party_size = LOCAL_PLAYER:GetAttribute("PartySize")
	local leader_id = LOCAL_PLAYER:GetAttribute(
		"PartyLeaderUserId"
	)
	if typeof(party_id) == "string" and party_id ~= "" then
		local role = if leader_id == LOCAL_PLAYER.UserId
			then "Leader"
			else "Member"
		ui.party.Text = ("Party: %s | %d/4")
			:format(
				role,
				tonumber(party_size) or 1
			)
		ui.leave.Visible = true
	else
		ui.party.Text = "Party: Solo"
		ui.leave.Visible = false
	end
end

Remotes.party_update().OnClientEvent:Connect(
	function(payload: any)
		if typeof(payload) ~= "table"
			or payload.kind ~= "SNAPSHOT"
		then
			return
		end
		latest_party = payload
		if payload.message and payload.message ~= "" then
			ui.status.Text = tostring(payload.message)
		end
		update_summary()
		render_rows()
		refresh_relation_labels()
	end
)

Remotes.matchmaking_update().OnClientEvent:Connect(
	function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.message then
			ui.status.Text = tostring(payload.message)
		end
		update_summary()
	end
)

Players.PlayerAdded:Connect(function(player)
	friend_cache[player.UserId] = nil
	player.CharacterAdded:Connect(function()
		task.delay(0.5, refresh_relation_labels)
	end)
	task.delay(0.5, render_rows)
end)

Players.PlayerRemoving:Connect(function(player)
	friend_cache[player.UserId] = nil
	task.defer(render_rows)
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LOCAL_PLAYER then
		player:GetAttributeChangedSignal("PartyId"):Connect(
			refresh_relation_labels
		)
	end
end

LOCAL_PLAYER:GetAttributeChangedSignal("PartyId"):Connect(
	function()
		update_summary()
		render_rows()
		refresh_relation_labels()
	end
)
LOCAL_PLAYER:GetAttributeChangedSignal("MatchStrength"):Connect(
	update_summary
)
LOCAL_PLAYER:GetAttributeChangedSignal("MatchBandName"):Connect(
	update_summary
)

RunService.Heartbeat:Connect(function(delta_time)
	refresh_accumulator += delta_time
	if refresh_accumulator < REFRESH_SECONDS then
		return
	end
	refresh_accumulator = 0

	update_summary()
	refresh_relation_labels()
end)

update_summary()
Remotes.party_action():FireServer("REQUEST", {})
Remotes.matchmaking_action():FireServer("REQUEST", {})
