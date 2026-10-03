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
local UPGRADE_GUI_NAME = "NecroPlotUpgradeGui"
local CRUCIBLE_GUI_NAME = "NecroSoulCrucibleGui"
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
		body = "Every successful Raise teaches you more about that exact "
			.. "unit type. Raise milestones unlock small permanent "
			.. "defence bonuses, limited by Codex level.",
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
		record (any): Reserve, Master Tube, or trophy record.

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
		max_slots (number?): Optional number of visible labelled slots.

	Returns:
		None.
]]
local function render_record_plinths(
	attribute_name: string,
	records: { any },
	empty_text: string,
	color: Color3,
	max_slots: number?
)
	for index, plinth in ipairs(get_plinths(attribute_name)) do
		if max_slots and index > max_slots then
			local old = plinth:FindFirstChild(
				PERSONAL_LABEL_NAME
			)
			if old then
				old:Destroy()
			end
			continue
		end

		local record = records[index]
		local text = if record
			then record_name(record)
			else empty_text
		set_plinth_label(plinth, text, color)
	end
end

--[[
	Collects captured boss identities from reserve and the Master Tube.

	Args:
		snapshot (any): Soul Collection snapshot.

	Returns:
		{ any }: Unique captured boss records.
]]
local function get_boss_records(snapshot: any): { any }
	local result = {}
	local found: { [string]: boolean } = {}
	for _, record in ipairs(snapshot.units or {}) do
		local template = tostring(record.template_name or "")
		if BOSS_TEMPLATES[template] and not found[template] then
			found[template] = true
			table.insert(result, record)
		end
	end

	local master = snapshot.masterTube
	if typeof(master) == "table" then
		local template = tostring(master.template_name or "")
		if BOSS_TEMPLATES[template] and not found[template] then
			found[template] = true
			table.insert(result, master)
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
	local bosses = get_boss_records(snapshot)
	local unlocked = tonumber(
		player:GetAttribute("BossTrophySlots")
	) or 4

	for index, plinth in ipairs(
		get_plinths("BossTrophySlot")
	) do
		local text = "Locked Trophy Display"
		local color = Color3.fromRGB(117, 108, 123)

		if index <= unlocked then
			local record = bosses[index]
			text = if record
				then record_name(record)
				else "Unclaimed Trophy"
			color = Color3.fromRGB(224, 181, 96)
		end

		set_plinth_label(plinth, text, color)
	end
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
		if not machine then
			local old = instance:FindFirstChild(
				PERSONAL_LABEL_NAME
			)
			if old then
				old:Destroy()
			end
			continue
		end

		local text = (
			"Clone Tube %d | Lv %d\n%d clone(s) ready"
		):format(
			index,
			tonumber(machine.level) or 1,
			tonumber(machine.outputCount) or 0
		)
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
	local reserve_slots = tonumber(
		player:GetAttribute("ReserveDisplaySlots")
	) or 6
	render_record_plinths(
		"ReserveDisplaySlot",
		snapshot.units or {},
		"Empty Reserve Alcove",
		Color3.fromRGB(190, 172, 205),
		reserve_slots
	)

	local roster_records = {}
	for _, template_name in ipairs(
		snapshot.ownedTemplates or {}
	) do
		table.insert(roster_records, {
			template_name = template_name,
		})
	end
	render_record_plinths(
		"UnitDisplaySlot",
		roster_records,
		"Empty Roster Slot",
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
	local entries = snapshot.codexEntries or {}
	if #entries == 0 then
		return "No Raise knowledge recorded yet. Successfully Raise the "
			.. "same unit type repeatedly to unlock permanent Codex "
			.. "defence bonuses for that exact template."
	end

	local lines = {
		"Raise knowledge grants small permanent defence bonuses:",
	}
	local shown = math.min(#entries, 6)
	for index = 1, shown do
		local entry = entries[index]
		local name = tostring(entry.templateName or "Unknown Unit")
		local raises = tonumber(entry.raiseCount) or 0
		local bonus = tonumber(entry.defenseBonus) or 0
		local bonus_percent = math.floor(bonus * 100 + 0.5)

		local progress = "All current milestones complete"
		if entry.nextRaiseCount then
			local next_count = tonumber(entry.nextRaiseCount) or raises
			local next_bonus =
				tonumber(entry.nextDefenseBonus) or bonus
			progress = ("next: %d Raises → +%d%% DEF"):format(
				next_count,
				math.floor(next_bonus * 100 + 0.5)
			)
		end

		table.insert(
			lines,
			("%s — %d Raises, +%d%% DEF (%s)"):format(
				name,
				raises,
				bonus_percent,
				progress
			)
		)
	end

	if #entries > shown then
		table.insert(
			lines,
			("...and %d more discovered unit type(s)."):format(
				#entries - shown
			)
		)
	end

	return table.concat(lines, "\n")
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
	Creates a text label used by the physical Upgrade Forge UI.

	Args:
		parent (Instance): Label parent.
		text (string): Initial text.
		size (number): Text size.
		bold (boolean): Whether to use the bold font.

	Returns:
		TextLabel: Created label.
]]
local function make_upgrade_label(
	parent: Instance,
	text: string,
	size: number,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = if bold
		then Enum.Font.GothamBold
		else Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(232, 223, 242)
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

--[[
	Creates a button used by the physical Upgrade Forge UI.

	Args:
		parent (Instance): Button parent.
		text (string): Button text.

	Returns:
		TextButton: Created button.
]]
local function make_upgrade_button(
	parent: Instance,
	text: string
): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(118, 32)
	button.BackgroundColor3 = Color3.fromRGB(41, 31, 49)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(239, 219, 255)
	button.TextSize = 12
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button
	return button
end

--[[
	Creates or retrieves the Upgrade Forge GUI.

	Args:
		None.

	Returns:
		ScreenGui: Upgrade Forge GUI.
		Frame: Main panel.
		TextLabel: Essence/discount summary.
		TextLabel: Result/status label.
		ScrollingFrame: Upgrade rows container.
]]
local function get_upgrade_gui(): (
	ScreenGui,
	Frame,
	TextLabel,
	TextLabel,
	ScrollingFrame
)
	local existing = player_gui:FindFirstChild(UPGRADE_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		local panel = existing:FindFirstChild("Panel")
		if panel and panel:IsA("Frame") then
			local summary = panel:FindFirstChild("Summary")
			local status = panel:FindFirstChild("Status")
			local content = panel:FindFirstChild("Content")
			if summary and summary:IsA("TextLabel")
				and status and status:IsA("TextLabel")
				and content
				and content:IsA("ScrollingFrame")
			then
				return existing, panel, summary, status, content
			end
		end
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = UPGRADE_GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = player_gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(640, 560)
	panel.BackgroundColor3 = Color3.fromRGB(14, 11, 18)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local panel_corner = Instance.new("UICorner")
	panel_corner.CornerRadius = UDim.new(0, 12)
	panel_corner.Parent = panel

	local title = make_upgrade_label(
		panel,
		"Foundry Upgrade Forge",
		22,
		true
	)
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -80, 0, 28)

	local summary = make_upgrade_label(panel, "", 13, false)
	summary.Name = "Summary"
	summary.Position = UDim2.fromOffset(18, 48)
	summary.Size = UDim2.new(1, -36, 0, 20)
	summary.TextColor3 = Color3.fromRGB(194, 174, 211)

	local status = make_upgrade_label(panel, "", 12, false)
	status.Name = "Status"
	status.Position = UDim2.fromOffset(18, 72)
	status.Size = UDim2.new(1, -36, 0, 20)
	status.TextColor3 = Color3.fromRGB(222, 193, 146)

	local close = make_upgrade_button(panel, "X")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(36, 30)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(18, 104)
	content.Size = UDim2.new(1, -36, 1, -122)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return gui, panel, summary, status, content
end

--[[
	Removes rendered Upgrade Forge rows while preserving its layout.

	Args:
		content (ScrollingFrame): Forge content container.

	Returns:
		None.
]]
local function clear_upgrade_rows(content: ScrollingFrame)
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

--[[
	Renders one facility or machine row in the Upgrade Forge.

	Args:
		content (ScrollingFrame): Row parent.
		title_text (string): Facility/machine title.
		detail_text (string): Active progression effect.
		button_text (string): Upgrade button text.
		enabled (boolean): Whether the purchase can be requested.
		action (string): Soul Collection action.
		payload (table): Action payload.

	Returns:
		None.
]]
local function render_upgrade_row(
	content: ScrollingFrame,
	title_text: string,
	detail_text: string,
	button_text: string,
	enabled: boolean,
	action: string,
	payload: { [string]: any }
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 68)
	row.BackgroundColor3 = Color3.fromRGB(24, 19, 30)
	row.BorderSizePixel = 0
	row.Parent = content

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local title = make_upgrade_label(row, title_text, 14, true)
	title.Position = UDim2.fromOffset(12, 9)
	title.Size = UDim2.new(1, -156, 0, 20)

	local detail = make_upgrade_label(
		row,
		detail_text,
		11,
		false
	)
	detail.Position = UDim2.fromOffset(12, 34)
	detail.Size = UDim2.new(1, -156, 0, 20)
	detail.TextColor3 = Color3.fromRGB(174, 161, 188)

	local button = make_upgrade_button(row, button_text)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Active = enabled
	button.AutoButtonColor = enabled
	if not enabled then
		button.BackgroundColor3 = Color3.fromRGB(38, 36, 41)
		button.TextColor3 = Color3.fromRGB(143, 137, 150)
	end
	button.Activated:Connect(function()
		if enabled then
			soul_remote:FireServer(action, payload)
		end
	end)
end

--[[
	Renders the complete physical Upgrade Forge state.

	Args:
		snapshot (any): Current Soul Collection snapshot.

	Returns:
		None.
]]
local function render_upgrade_forge(snapshot: any)
	local _, _, summary, _, content = get_upgrade_gui()
	clear_upgrade_rows(content)

	local essence = tonumber(snapshot.soulEssence) or 0
	local discount = tonumber(
		player:GetAttribute("PlotUpgradeDiscount")
	) or 0
	summary.Text = (
		"Soul Essence: %d   •   Forge discount: %d%%"
	):format(
		essence,
		math.floor(discount * 100 + 0.5)
	)

	for _, option in ipairs(snapshot.plotUpgradeOptions or {}) do
		local id = tostring(option.id or "")
		local name = tostring(option.name or id)
		local level = tonumber(option.level) or 1
		local plot_cap = tonumber(option.plotCap) or 1
		local cost = tonumber(option.upgradeCost)
		local effect = tostring(option.effect or "")
		local next_effect = option.nextEffect
		local enabled = cost ~= nil
		local button_text = if cost
			then ("Upgrade • %d"):format(cost)
			else "MAX"

		if id ~= "Plot" and level >= plot_cap and cost then
			enabled = false
			button_text = ("Plot Lv %d"):format(level + 1)
		elseif cost and essence < cost then
			enabled = false
			button_text = ("Need %d"):format(cost)
		end

		local detail = ("Current: %s"):format(effect)
		if next_effect then
			detail ..= ("  →  %s"):format(tostring(next_effect))
		end

		render_upgrade_row(
			content,
			("%s • Lv %d"):format(name, level),
			detail,
			button_text,
			enabled,
			"UPGRADE_FACILITY",
			{ facilityId = id }
		)
	end

	for index, machine in ipairs(snapshot.machines or {}) do
		local level = tonumber(machine.level) or 1
		local cost = tonumber(machine.upgradeCost)
		local enabled = cost ~= nil
		local button_text = if cost
			then ("Upgrade • %d"):format(cost)
			else "MAX"
		if cost and essence < cost then
			enabled = false
			button_text = ("Need %d"):format(cost)
		end

		render_upgrade_row(
			content,
			("Cloning Machine %d • Lv %d"):format(
				index,
				level
			),
			("Output storage: %d clone(s)"):format(
				tonumber(machine.capacity) or 0
			),
			button_text,
			enabled,
			"UPGRADE_MACHINE",
			{ machineId = tostring(machine.machineId or "") }
		)
	end
end

--[[
	Opens the physical Foundry Upgrade Forge interface.

	Args:
		None.

	Returns:
		None.
]]
local function open_upgrade_forge()
	local _, panel = get_upgrade_gui()
	panel.Visible = true
	if latest_snapshot then
		render_upgrade_forge(latest_snapshot)
	end
	request_snapshot()
end

--[[
	Creates or retrieves the physical Soul Crucible GUI.

	Args:
		None.

	Returns:
		ScreenGui: Crucible GUI.
		Frame: Main panel.
		TextLabel: Essence summary.
		TextLabel: Result/status label.
		ScrollingFrame: Sacrifice rows.
]]
local function get_crucible_gui(): (
	ScreenGui,
	Frame,
	TextLabel,
	TextLabel,
	ScrollingFrame
)
	local existing = player_gui:FindFirstChild(CRUCIBLE_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		local panel = existing:FindFirstChild("Panel")
		if panel and panel:IsA("Frame") then
			local summary = panel:FindFirstChild("Summary")
			local status = panel:FindFirstChild("Status")
			local content = panel:FindFirstChild("Content")
			if summary and summary:IsA("TextLabel")
				and status and status:IsA("TextLabel")
				and content
				and content:IsA("ScrollingFrame")
			then
				return existing, panel, summary, status, content
			end
		end
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = CRUCIBLE_GUI_NAME
	gui.ResetOnSpawn = false
	gui.Parent = player_gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 540)
	panel.BackgroundColor3 = Color3.fromRGB(18, 10, 12)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local title = make_upgrade_label(
		panel,
		"Sacrificial Soul Crucible",
		22,
		true
	)
	title.Position = UDim2.fromOffset(18, 14)
	title.Size = UDim2.new(1, -80, 0, 28)

	local summary = make_upgrade_label(panel, "", 13, false)
	summary.Name = "Summary"
	summary.Position = UDim2.fromOffset(18, 48)
	summary.Size = UDim2.new(1, -36, 0, 20)
	summary.TextColor3 = Color3.fromRGB(215, 169, 176)

	local status = make_upgrade_label(panel, "", 12, false)
	status.Name = "Status"
	status.Position = UDim2.fromOffset(18, 72)
	status.Size = UDim2.new(1, -36, 0, 20)
	status.TextColor3 = Color3.fromRGB(231, 188, 147)

	local close = make_upgrade_button(panel, "X")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(36, 30)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(18, 104)
	content.Size = UDim2.new(1, -36, 1, -122)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 6
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content

	return gui, panel, summary, status, content
end

--[[
	Renders units that can be sacrificed for Soul Essence.

	Args:
		snapshot (any): Current Soul Collection snapshot.

	Returns:
		None.
]]
local function render_crucible(snapshot: any)
	local _, _, summary, _, content = get_crucible_gui()
	clear_upgrade_rows(content)

	local essence = tonumber(snapshot.soulEssence) or 0
	local multiplier = tonumber(
		player:GetAttribute("SoulSacrificeMultiplier")
	) or 1
	summary.Text = (
		"Soul Essence: %d   •   Sacrifice yield: %d%%"
	):format(
		essence,
		math.floor(multiplier * 100 + 0.5)
	)

	local options = snapshot.sacrificeOptions or {}
	if #options == 0 then
		render_upgrade_row(
			content,
			"No stored units available",
			"Raise and extract unwanted units to sacrifice them here.",
			"",
			false,
			"SACRIFICE_UNIT",
			{}
		)
		return
	end

	for _, option in ipairs(options) do
		local template_name = tostring(
			option.templateName or "Unknown Unit"
		)
		local size_tier = tostring(option.sizeTier or "Normal")
		local trait = tostring(option.trait or "None")
		local value = tonumber(option.value) or 0
		local details = ("%s • %s"):format(
			size_tier,
			trait
		)

		render_upgrade_row(
			content,
			template_name,
			details,
			("Sacrifice +%d"):format(value),
			true,
			"SACRIFICE_UNIT",
			{ recordId = tostring(option.recordId or "") }
		)
	end
end

--[[
	Opens the physical Sacrificial Soul Crucible.

	Args:
		None.

	Returns:
		None.
]]
local function open_crucible()
	local _, panel = get_crucible_gui()
	panel.Visible = true
	if latest_snapshot then
		render_crucible(latest_snapshot)
	end
	request_snapshot()
end

--[[
	Opens the Soul Foundry interface.

	Args:
		tab_name (string): "Machines" or "Reserve" context.

	Returns:
		None.
]]
local function open_soul_foundry(tab_name: string)
	local gui = player_gui:FindFirstChild("NecroSoulFoundryGui")
	local panel = gui and gui:FindFirstChild("FoundryPanel")
	if panel and panel:IsA("GuiObject") then
		panel:SetAttribute("RequestedTab", tab_name)
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
	if station_id == "Upgrades" then
		open_upgrade_forge()
		return
	end

	if station_id == "SoulFoundry" then
		open_soul_foundry("Machines")
		return
	end

	if station_id == "ReserveCrypt" then
		open_soul_foundry("Reserve")
		return
	end

	if station_id == "SoulCrucible" then
		open_crucible()
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
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "SNAPSHOT" then
		latest_snapshot = payload
		schedule_base_render()

		local gui = player_gui:FindFirstChild(UPGRADE_GUI_NAME)
		local panel = gui and gui:FindFirstChild("Panel")
		if panel
			and panel:IsA("GuiObject")
			and panel.Visible
		then
			render_upgrade_forge(payload)
		end

		local crucible_gui =
			player_gui:FindFirstChild(CRUCIBLE_GUI_NAME)
		local crucible_panel = crucible_gui
			and crucible_gui:FindFirstChild("Panel")
		if crucible_panel
			and crucible_panel:IsA("GuiObject")
			and crucible_panel.Visible
		then
			render_crucible(payload)
		end
		return
	end

	if payload.kind == "RESULT" then
		for _, gui_name in ipairs({
			UPGRADE_GUI_NAME,
			CRUCIBLE_GUI_NAME,
		}) do
			local gui = player_gui:FindFirstChild(gui_name)
			local panel = gui and gui:FindFirstChild("Panel")
			local status = panel and panel:FindFirstChild("Status")
			if status and status:IsA("TextLabel") then
				status.Text = tostring(payload.message or "")
			end
		end
	end
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
