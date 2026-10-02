--!strict

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local player_gui = player:WaitForChild("PlayerGui")

local INFO_GUI_NAME = "NecroBaseInfoGui"
local PERSONAL_LABEL_NAME = "PersonalBaseDisplay"
local BOSS_TEMPLATES = {
	GraveBaron = true,
	CryptWarden = true,
}

local latest_snapshot: any = nil

--[[
	Waits for the server-owned Soul Collection RemoteEvent.

	Args:
		None.

	Returns:
		RemoteEvent: Replicated Soul Collection event.
]]
local function get_soul_remote(): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local remote = folder:WaitForChild("SoulCollection")
	assert(
		remote:IsA("RemoteEvent"),
		"SoulCollection must be a RemoteEvent."
	)
	return remote
end

local soul_remote = get_soul_remote()

local INFO_TEXT: { [string]: { title: string, body: string } } = {
	Codex = {
		title = "Necromancer Codex",
		body = "Faction, role, rarity, evolution and boss discoveries "
			.. "will be recorded here as the roster art is replaced.",
	},
	Trophies = {
		title = "Boss Trophy Hall",
		body = "Captured major bosses and future boss achievements "
			.. "are represented in this hall.",
	},
}
--[[
	Returns the local player's assigned Sanctum plot index.

	Args:
		None.

	Returns:
		number?: Positive plot index when assigned.
]]
local function get_owned_plot_index(): number?
	local value = player:GetAttribute("SanctumPlotIndex")
	if typeof(value) ~= "number" or value <= 0 then
		return nil
	end
	return math.floor(value)
end

--[[
	Finds the local player's assigned Sanctum plot.

	Args:
		None.

	Returns:
		Model?: Owned plot when it is currently streamed.
]]
local function get_owned_plot(): Model?
	local plot_index = get_owned_plot_index()
	if not plot_index then
		return nil
	end

	local zones = workspace:FindFirstChild("Zones")
	local safe = zones and zones:FindFirstChild("SafeZoneWorld")
	local plots = safe and safe:FindFirstChild("Bases")
	if not (plots and plots:IsA("Folder")) then
		return nil
	end

	local named = plots:FindFirstChild(
		("Base%02d"):format(plot_index)
	)
	if named and named:IsA("Model") then
		return named
	end

	for _, child in ipairs(plots:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("PlotIndex") == plot_index
		then
			return child
		end
	end
	return nil
end

--[[
	Finds the functional facilities inside the owned plot.

	Args:
		None.

	Returns:
		Folder?: Facilities folder when currently streamed.
]]
local function get_facilities(): Folder?
	local plot = get_owned_plot()
	local facilities = plot
		and plot:FindFirstChild("Phase10Facilities")
	if facilities and facilities:IsA("Folder") then
		return facilities
	end
	return nil
end

--[[
	Returns whether a prompt belongs to the local player's plot.

	Args:
		prompt (ProximityPrompt): Prompt to inspect.

	Returns:
		boolean: True when the prompt belongs to the owned plot.
]]
local function owns_prompt(prompt: ProximityPrompt): boolean
	local plot_index = get_owned_plot_index()
	if not plot_index then
		return false
	end

	local parent = prompt.Parent
	if not parent then
		return false
	end
	return parent:GetAttribute("PlotIndex") == plot_index
end

--[[
	Locally enables only the player's own plot prompts.

	Args:
		instance (Instance): Streamed instance to inspect.

	Returns:
		None.
]]
local function update_prompt_access(instance: Instance)
	if not instance:IsA("ProximityPrompt")
		or instance.Name ~= "BaseStationPrompt"
	then
		return
	end
	instance.Enabled = owns_prompt(instance)
end

--[[
	Refreshes all currently streamed Base station prompts.

	Args:
		None.

	Returns:
		None.
]]
local function refresh_prompt_access()
	local zones = workspace:FindFirstChild("Zones")
	local safe = zones and zones:FindFirstChild("SafeZoneWorld")
	if not safe then
		return
	end

	for _, instance in ipairs(safe:GetDescendants()) do
		update_prompt_access(instance)
	end
end

--[[
	Builds a readable name for a persistent unit record.

	Args:
		record (any): Soul Vault or Master record.

	Returns:
		string: Display name including evolution state.
]]
local function record_name(record: any): string
	if typeof(record) ~= "table" then
		return "Empty"
	end

	local name = tostring(record.template_name or "Unknown Unit")
	local evolution = record.evolution_id
	if typeof(evolution) == "string" and evolution ~= "" then
		name = evolution .. " " .. name
	end
	return name
end

--[[
	Creates a player-local world label over a display plinth.

	Args:
		part (BasePart): Display plinth.
		text (string): Label text.
		color (Color3): Text accent.

	Returns:
		None.
]]
local function set_plinth_label(
	part: BasePart,
	text: string,
	color: Color3
)
	local old = part:FindFirstChild(PERSONAL_LABEL_NAME)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = PERSONAL_LABEL_NAME
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(170, 46)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(13, 12, 16)
	label.BackgroundTransparency = 0.2
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
end

--[[
	Finds display plinths by numeric slot attribute.

	Args:
		attribute_name (string): Numeric slot attribute.

	Returns:
		{ BasePart }: Plinths sorted by slot index.
]]
local function get_plinths(
	attribute_name: string
): { BasePart }
	local facilities = get_facilities()
	if not facilities then
		return {}
	end

	local result: { BasePart } = {}
	for _, instance in ipairs(facilities:GetDescendants()) do
		if instance:IsA("BasePart")
			and typeof(instance:GetAttribute(attribute_name)) == "number"
		then
			table.insert(result, instance)
		end
	end

	table.sort(result, function(left, right)
		return (left:GetAttribute(attribute_name) :: number)
			< (right:GetAttribute(attribute_name) :: number)
	end)
	return result
end

--[[
	Renders persistent records on player-local display plinths.

	Args:
		attribute_name (string): Slot attribute used by the plinths.
		records ({ any }): Records to display.
		empty_text (string): Text for unused slots.
		color (Color3): Label colour.

	Returns:
		None.
]]
local function render_record_plinths(
	attribute_name: string,
	records: { any },
	empty_text: string,
	color: Color3
)
	for index, plinth in ipairs(get_plinths(attribute_name)) do
		local record = records[index]
		local text = if record
			then record_name(record)
			else empty_text
		set_plinth_label(plinth, text, color)
	end
end

--[[
	Collects captured boss identities from Vault and Master records.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		{ any }: Unique captured boss records.
]]
local function get_boss_records(snapshot: any): { any }
	local result = {}
	local found: { [string]: boolean } = {}
	for _, collection_name in ipairs({ "units", "masters" }) do
		for _, record in ipairs(snapshot[collection_name] or {}) do
			local template = tostring(record.template_name or "")
			if BOSS_TEMPLATES[template] and not found[template] then
				found[template] = true
				table.insert(result, record)
			end
		end
	end
	return result
end

--[[
	Renders the player's captured bosses in the Trophy Hall.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		None.
]]
local function render_trophies(snapshot: any)
	render_record_plinths(
		"BossTrophySlot",
		get_boss_records(snapshot),
		"Unclaimed Trophy",
		Color3.fromRGB(224, 181, 96)
	)
end

--[[
	Renders clone-machine status on the physical Soul Foundry chambers.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		None.
]]
local function render_machines(snapshot: any)
	local facilities = get_facilities()
	if not facilities then
		return
	end

	local machines = snapshot.machines or {}
	for _, instance in ipairs(facilities:GetDescendants()) do
		if not instance:IsA("BasePart") then
			continue
		end
		local index = instance:GetAttribute("MachineIndex")
		if typeof(index) ~= "number" then
			continue
		end

		local machine = machines[index]
		local text = ("Machine %d"):format(index)
		if machine then
			text = ("Machine %d | Lv %d\n%d clone(s) ready"):format(
				index,
				tonumber(machine.level) or 1,
				tonumber(machine.outputCount) or 0
			)
		end
		set_plinth_label(
			instance,
			text,
			Color3.fromRGB(200, 157, 242)
		)
	end
end

--[[
	Renders player-specific Base displays from Soul Collection state.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		None.
]]
local function render_base_snapshot(snapshot: any)
	render_record_plinths(
		"MasterDisplaySlot",
		snapshot.masters or {},
		"Empty Master Slot",
		Color3.fromRGB(205, 166, 235)
	)
	render_record_plinths(
		"UnitDisplaySlot",
		snapshot.units or {},
		"Empty Unit Slot",
		Color3.fromRGB(164, 197, 218)
	)
	render_trophies(snapshot)
	render_machines(snapshot)
end

local render_pending = false

--[[
	Schedules a debounced refresh after streamed Base parts arrive.

	Args:
		None.

	Returns:
		None.
]]
local function schedule_base_render()
	if render_pending then
		return
	end
	render_pending = true

	task.delay(0.15, function()
		render_pending = false
		if latest_snapshot then
			render_base_snapshot(latest_snapshot)
		end
	end)
end

--[[
	Requests fresh Soul Collection state from the server.

	Args:
		None.

	Returns:
		None.
]]
local function request_snapshot()
	soul_remote:FireServer("REQUEST", {})
end

--[[
	Builds a compact discovery summary for the Codex station.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		string: Readable discovery summary.
]]
local function build_codex_text(snapshot: any): string
	local factions: { [string]: boolean } = {}
	local roles: { [string]: boolean } = {}
	local evolutions: { [string]: boolean } = {}
	for _, collection_name in ipairs({ "units", "masters" }) do
		for _, record in ipairs(snapshot[collection_name] or {}) do
			if record.faction_id then
				factions[tostring(record.faction_id)] = true
			end
			if record.combat_role then
				roles[tostring(record.combat_role)] = true
			end
			if record.evolution_id then
				evolutions[tostring(record.evolution_id)] = true
			end
		end
	end

	local function count_keys(values: { [string]: boolean }): number
		local count = 0
		for _ in pairs(values) do
			count += 1
		end
		return count
	end

	return (
		"Your Soul Vault currently records %d faction(s), "
		.. "%d combat role(s), and %d evolution type(s). "
		.. "The Codex will gain full creature pages as final R15 "
		.. "roster models replace the current backend placeholders."
	):format(
		count_keys(factions),
		count_keys(roles),
		count_keys(evolutions)
	)
end

--[[
	Builds a player-specific Trophy Hall summary.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		string: Trophy summary.
]]
local function build_trophy_text(snapshot: any): string
	local bosses = get_boss_records(snapshot)
	if #bosses == 0 then
		return "No major boss has been secured yet. Defeat, Raise and "
			.. "extract a boss to claim its trophy presentation."
	end

	local names = {}
	for _, record in ipairs(bosses) do
		table.insert(names, record_name(record))
	end
	return "Captured major bosses: " .. table.concat(names, ", ") .. "."
end

--[[
	Creates or retrieves the Base information GUI.

	Args:
		None.

	Returns:
		ScreenGui: Base information GUI.
		Frame: Main information panel.
		TextLabel: Title label.
		TextLabel: Body label.
]]
local function get_info_gui(): (
	ScreenGui,
	Frame,
	TextLabel,
	TextLabel
)
	local existing = player_gui:FindFirstChild(INFO_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		local panel = existing:FindFirstChild("Panel")
		if panel and panel:IsA("Frame") then
			local title = panel:FindFirstChild("Title")
			local body = panel:FindFirstChild("Body")
			if title and title:IsA("TextLabel")
				and body and body:IsA("TextLabel")
			then
				return existing, panel, title, body
			end
		end
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = INFO_GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = player_gui
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(520, 250)
	panel.BackgroundColor3 = Color3.fromRGB(15, 13, 19)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -70, 0, 30)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(226, 210, 242)
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(18, 58)
	body.Size = UDim2.new(1, -36, 1, -78)
	body.Font = Enum.Font.Gotham
	body.TextColor3 = Color3.fromRGB(202, 195, 211)
	body.TextSize = 15
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = panel
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 30)
	close.BackgroundColor3 = Color3.fromRGB(37, 31, 44)
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(235, 225, 244)
	close.TextSize = 14
	close.Parent = panel
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	return gui, panel, title, body
end

--[[
	Opens the Soul Foundry interface.

	Args:
		None.

	Returns:
		None.
]]
local function open_soul_foundry()
	local gui = player_gui:FindFirstChild("NecroSoulFoundryGui")
	local panel = gui and gui:FindFirstChild("FoundryPanel")
	if panel and panel:IsA("GuiObject") then
		panel.Visible = true
	end
	soul_remote:FireServer("REQUEST")
end
--[[
	Opens the existing Base Formation Editor.

	Args:
		None.

	Returns:
		None.
]]
local function open_formation_editor()
	local gui = player_gui:FindFirstChild("NecroFormationEditorGui")
	local panel = gui and gui:FindFirstChild("FormationEditor")
	if panel and panel:IsA("GuiObject") then
		panel.Visible = true
	end
	Remotes.formation_profile():FireServer("REQUEST")
end

--[[
	Opens the existing skill loadout editor.

	Args:
		None.

	Returns:
		None.
]]
local function open_skill_editor()
	local gui = player_gui:FindFirstChild("NecroProgressionGui")
	local editor = gui and gui:FindFirstChild("SkillEditor")
	if editor and editor:IsA("GuiObject") then
		editor.Visible = true
	end
	Remotes.progression():FireServer("REQUEST")
end

--[[
	Shows information for a non-editor Base station.

	Args:
		station_id (string): Station identifier.

	Returns:
		None.
]]
local function show_info(station_id: string)
	local info = INFO_TEXT[station_id]
	if not info then
		return
	end

	local text = info.body
	if latest_snapshot and station_id == "Codex" then
		text = build_codex_text(latest_snapshot)
	elseif latest_snapshot and station_id == "Trophies" then
		text = build_trophy_text(latest_snapshot)
	end

	local _, panel, title, body = get_info_gui()
	title.Text = info.title
	body.Text = text
	panel.Visible = true
end

--[[
	Dispatches a Base station prompt to the correct interface.

	Args:
		station_id (string): Base station identifier.

	Returns:
		None.
]]
local function activate_station(station_id: string)
	if station_id == "SoulFoundry"
		or station_id == "Masters"
		or station_id == "Upgrades"
	then
		open_soul_foundry()
		return
	end

	if station_id == "FormationEditor" then
		open_formation_editor()
		return
	end

	if station_id == "SkillLoadout" then
		open_skill_editor()
		return
	end

	show_info(station_id)
end
--[[
	Handles any ProximityPrompt fired in the Base district.

	Args:
		prompt (ProximityPrompt): Triggered prompt.
		triggering_player (Player): Player that used the prompt.

	Returns:
		None.
]]
local function on_prompt_triggered(
	prompt: ProximityPrompt,
	triggering_player: Player
)
	if triggering_player ~= player then
		return
	end
	if not owns_prompt(prompt) then
		return
	end

	local parent = prompt.Parent
	if not parent then
		return
	end

	local station_id = parent:GetAttribute("BaseStationId")
	if typeof(station_id) ~= "string" or station_id == "" then
		return
	end

	activate_station(station_id)
end

--[[
	Updates the physical Base presentation from Soul Collection state.

	Args:
		payload (any): Soul Collection server payload.

	Returns:
		None.
]]
local function on_soul_payload(payload: any)
	if typeof(payload) ~= "table" or payload.kind ~= "SNAPSHOT" then
		return
	end
	latest_snapshot = payload
	schedule_base_render()
end

local zones = workspace:WaitForChild("Zones")
local safe_world = zones:WaitForChild("SafeZoneWorld")

get_info_gui()
ProximityPromptService.PromptTriggered:Connect(on_prompt_triggered)
soul_remote.OnClientEvent:Connect(on_soul_payload)

safe_world.DescendantAdded:Connect(function(instance)
	update_prompt_access(instance)
	if instance:IsA("BasePart")
		or instance:IsA("ProximityPrompt")
	then
		schedule_base_render()
	end
end)

player:GetAttributeChangedSignal("PvPZone"):Connect(function()
	if player:GetAttribute("PvPZone") ~= "SafeZone" then
		return
	end

	task.delay(0.35, function()
		refresh_prompt_access()
		request_snapshot()
		schedule_base_render()
	end)
end)

player:GetAttributeChangedSignal(
	"SanctumPlotIndex"
):Connect(function()
	refresh_prompt_access()
	request_snapshot()
	schedule_base_render()
end)

task.defer(function()
	task.wait(1)
	refresh_prompt_access()
	request_snapshot()
end)
