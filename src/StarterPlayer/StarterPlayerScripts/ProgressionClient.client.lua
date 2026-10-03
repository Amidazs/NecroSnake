--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")
local GUI_NAME = "NecroProgressionGui"
local SLOT_KEYS = {
	Enum.KeyCode.Z,
	Enum.KeyCode.X,
	Enum.KeyCode.C,
}
local SLOT_KEY_NAMES = { "Z", "X", "C" }

local snapshot: any = nil
local cooldowns: { [string]: number } = {}
local editor_visible = false

--[[
	Creates rounded corners for a UI object.

	Args:
		instance (Instance): UI object receiving the corner.
		radius (number): Pixel corner radius.

	Returns:
		None.
]]
local function add_corner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

--[[
	Creates an outline for a UI object.

	Args:
		instance (Instance): UI object receiving the outline.
		transparency (number): Outline transparency.

	Returns:
		None.
]]
local function add_stroke(
	instance: Instance,
	transparency: number
)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(125, 85, 165)
	stroke.Transparency = transparency
	stroke.Thickness = 1
	stroke.Parent = instance
end

--[[
	Creates a text label.

	Args:
		parent (Instance): Label parent.
		text (string): Initial text.
		size (number): Font size.
		bold (boolean): Whether to use bold font.

	Returns:
		TextLabel: Created label.
]]
local function make_label(
	parent: Instance,
	text: string,
	size: number,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(236, 229, 245)
	label.TextSize = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

--[[
	Creates a reusable progression button.

	Args:
		parent (Instance): Button parent.
		text (string): Button text.
		width (number): Button width.

	Returns:
		TextButton: Created button.
]]
local function make_button(
	parent: Instance,
	text: string,
	width: number
): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width, 32)
	button.BackgroundColor3 = Color3.fromRGB(28, 21, 37)
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 221, 250)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent
	add_corner(button, 7)
	add_stroke(button, 0.55)
	return button
end

--[[
	Creates the progression HUD and Base skill editor.

	Args:
		None.

	Returns:
		table: References to the created UI elements.
]]
local function create_gui()
	local old = PLAYER_GUI:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = PLAYER_GUI

	local progress = Instance.new("Frame")
	progress.Name = "ProgressPanel"
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.new(1, -18, 0, 60)
	progress.Size = UDim2.fromOffset(220, 58)
	progress.BackgroundColor3 = Color3.fromRGB(14, 12, 19)
	progress.BackgroundTransparency = 0.12
	progress.Parent = gui
	add_corner(progress, 8)
	add_stroke(progress, 0.5)

	local level_label = make_label(progress, "Necromancer Lv 1", 14, true)
	level_label.Name = "Level"
	level_label.Position = UDim2.fromOffset(10, 7)
	level_label.Size = UDim2.new(1, -20, 0, 18)

	local xp_label = make_label(progress, "XP 0 / 80", 11, false)
	xp_label.Name = "XP"
	xp_label.Position = UDim2.fromOffset(10, 28)
	xp_label.Size = UDim2.new(1, -20, 0, 16)

	local prestige_label = make_label(progress, "", 10, false)
	prestige_label.Name = "Prestige"
	prestige_label.Position = UDim2.fromOffset(10, 43)
	prestige_label.Size = UDim2.new(1, -20, 0, 13)

	local skill_bar = Instance.new("Frame")
	skill_bar.Name = "SkillBar"
	skill_bar.AnchorPoint = Vector2.new(0.5, 1)
	skill_bar.Position = UDim2.new(0.5, 0, 1, -18)
	skill_bar.Size = UDim2.fromOffset(342, 64)
	skill_bar.BackgroundTransparency = 1
	skill_bar.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = skill_bar

	local slots: { TextButton } = {}
	for index = 1, 3 do
		local slot = make_button(
			skill_bar,
			("[%s] Locked"):format(SLOT_KEY_NAMES[index]),
			108
		)
		slot.Name = ("SkillSlot%d"):format(index)
		slot.Size = UDim2.fromOffset(108, 58)
		slot.TextWrapped = true
		table.insert(slots, slot)
	end

	local editor_button = make_button(gui, "Skills", 92)
	editor_button.Name = "EditorButton"
	editor_button.AnchorPoint = Vector2.new(1, 1)
	editor_button.Position = UDim2.new(1, -84, 1, -150)
	editor_button.Visible = false

	local editor = Instance.new("Frame")
	editor.Name = "SkillEditor"
	editor.AnchorPoint = Vector2.new(1, 1)
	editor.Position = UDim2.new(1, -84, 1, -188)
	editor.Size = UDim2.fromOffset(430, 410)
	editor.BackgroundColor3 = Color3.fromRGB(13, 10, 18)
	editor.BackgroundTransparency = 0.03
	editor.Visible = false
	editor.Parent = gui
	add_corner(editor, 12)
	add_stroke(editor, 0.2)

	local title = make_label(editor, "Necromancer Skills", 20, true)
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 24)

	local editor_summary = make_label(editor, "", 11, false)
	editor_summary.Name = "Summary"
	editor_summary.Position = UDim2.fromOffset(14, 38)
	editor_summary.Size = UDim2.new(1, -28, 0, 34)
	editor_summary.TextWrapped = true

	local list = Instance.new("ScrollingFrame")
	list.Name = "SkillList"
	list.Position = UDim2.fromOffset(14, 80)
	list.Size = UDim2.new(1, -28, 1, -134)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 5
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = editor

	local list_layout = Instance.new("UIListLayout")
	list_layout.Padding = UDim.new(0, 7)
	list_layout.Parent = list

	local rebirth_button = make_button(editor, "Rebirth", 116)
	rebirth_button.Name = "Rebirth"
	rebirth_button.AnchorPoint = Vector2.new(1, 1)
	rebirth_button.Position = UDim2.new(1, -14, 1, -12)

	local feedback = make_label(editor, "", 11, false)
	feedback.Name = "Feedback"
	feedback.Position = UDim2.new(0, 14, 1, -42)
	feedback.Size = UDim2.new(1, -150, 0, 24)
	feedback.TextWrapped = true

	return {
		gui = gui,
		progress = progress,
		level = level_label,
		xp = xp_label,
		prestige = prestige_label,
		skill_bar = skill_bar,
		slots = slots,
		editor_button = editor_button,
		editor = editor,
		editor_summary = editor_summary,
		list = list,
		rebirth = rebirth_button,
		feedback = feedback,
	}
end

local ui = create_gui()

--[[
	Returns a display name for a skill ID.

	Args:
		skill_id (string): Skill identifier.

	Returns:
		string: Skill name or the raw ID.
]]
local function skill_name(skill_id: string): string
	if not snapshot or typeof(snapshot.skills) ~= "table" then
		return skill_id
	end

	for _, definition in ipairs(snapshot.skills) do
		if definition.id == skill_id then
			return definition.name
		end
	end
	return skill_id
end

--[[
	Sends the current ordered loadout to the server.

	Args:
		skills (table): Ordered skill IDs.

	Returns:
		None.
]]
local function set_loadout(skills: { string })
	Remotes.progression():FireServer("SET_LOADOUT", {
		skills = skills,
	})
end

--[[
	Toggles one unlocked skill in the local loadout request.

	Args:
		skill_id (string): Skill to toggle.

	Returns:
		None.
]]
local function toggle_skill(skill_id: string)
	if not snapshot then
		return
	end

	local equipped = table.clone(snapshot.equippedSkills or {})
	local existing = table.find(equipped, skill_id)
	if existing then
		table.remove(equipped, existing)
		set_loadout(equipped)
		return
	end

	local slots = snapshot.skillSlots or 0
	if #equipped >= slots then
		ui.feedback.Text = "All unlocked skill slots are occupied."
		return
	end

	table.insert(equipped, skill_id)
	set_loadout(equipped)
end

--[[
	Casts an equipped slot.

	Args:
		slot_index (number): One-based skill slot index.

	Returns:
		None.
]]
local function cast_slot(slot_index: number)
	if not snapshot then
		return
	end

	local skill_id = snapshot.equippedSkills
		and snapshot.equippedSkills[slot_index]
	if not skill_id then
		return
	end

	local ready_at = cooldowns[skill_id] or 0
	if ready_at > Workspace:GetServerTimeNow() then
		return
	end

	Remotes.skills():FireServer("CAST", {
		skillId = skill_id,
	})
end

--[[
	Clears dynamic skill rows.

	Args:
		None.

	Returns:
		None.
]]
local function clear_skill_rows()
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

--[[
	Renders one skill row in the Base editor.

	Args:
		definition (table): Skill metadata from the server.

	Returns:
		None.
]]
local function render_skill_row(definition: any)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -5, 0, 66)
	row.BackgroundColor3 = Color3.fromRGB(24, 19, 31)
	row.BackgroundTransparency = 0.08
	row.Parent = ui.list
	add_corner(row, 8)
	add_stroke(row, 0.65)

	local title = make_label(
		row,
		tostring(definition.name or definition.id),
		13,
		true
	)
	title.Position = UDim2.fromOffset(10, 7)
	title.Size = UDim2.new(1, -120, 0, 18)

	local unlock_text = tostring(definition.description or "")
	if not definition.unlocked then
		local requirements = {
			("Lv %d"):format(definition.unlockLevel or 1),
			("Reliquary Lv %d"):format(
				definition.reliquaryLevel or 1
			),
		}
		if (definition.unlockRebirth or 0) > 0 then
			table.insert(
				requirements,
				("Rebirth %d"):format(
					definition.unlockRebirth
				)
			)
		end
		if definition.requiresSkillbook
			and not definition.hasSkillbook
		then
			table.insert(
				requirements,
				"Battlefield skillbook"
			)
		end
		unlock_text = "Requires: "
			.. table.concat(requirements, " • ")
	end
	local detail = make_label(row, unlock_text, 10, false)
	detail.Position = UDim2.fromOffset(10, 29)
	detail.Size = UDim2.new(1, -120, 0, 28)
	detail.TextWrapped = true
	detail.TextColor3 = Color3.fromRGB(177, 164, 190)

	local equipped = snapshot
		and table.find(
			snapshot.equippedSkills or {},
			definition.id
		) ~= nil
	local button = make_button(
		row,
		if equipped then "Unequip" else "Equip",
		88
	)
	button.Position = UDim2.new(1, -98, 0, 17)
	button.Active = definition.unlocked == true
	button.AutoButtonColor = definition.unlocked == true
	button.TextTransparency = if definition.unlocked then 0 else 0.5

	button.MouseButton1Click:Connect(function()
		if definition.unlocked then
			toggle_skill(definition.id)
		end
	end)
end

--[[
	Renders the progression snapshot into the HUD.

	Args:
		new_snapshot (table): Server progression payload.

	Returns:
		None.
]]
local function render_snapshot(new_snapshot: any)
	snapshot = new_snapshot

	ui.level.Text = ("Necromancer Lv %d"):format(
		new_snapshot.level or 1
	)
	if (new_snapshot.nextLevelXp or 0) > 0 then
		ui.xp.Text = ("XP %d / %d"):format(
			new_snapshot.xp or 0,
			new_snapshot.nextLevelXp
		)
	else
		ui.xp.Text = "MAX LEVEL — Rebirth available at Base"
	end
	ui.prestige.Text = ("Rebirth %d  |  Prestige Marks %d"):format(
		new_snapshot.rebirthCount or 0,
		new_snapshot.prestigeMarks or 0
	)

	local skill_slots = new_snapshot.skillSlots or 0
	for index, button in ipairs(ui.slots) do
		local skill_id = new_snapshot.equippedSkills
			and new_snapshot.equippedSkills[index]
		if index > skill_slots then
			button.Text = ("[%s] Locked"):format(
				SLOT_KEY_NAMES[index]
			)
			button.Active = false
		elseif skill_id then
			button.Text = ("[%s] %s"):format(
				SLOT_KEY_NAMES[index],
				skill_name(skill_id)
			)
			button.Active = true
		else
			button.Text = ("[%s] Empty"):format(
				SLOT_KEY_NAMES[index]
			)
			button.Active = true
		end
	end

	ui.editor_button.Visible = false
	if new_snapshot.inBase ~= true then
		editor_visible = false
		ui.editor.Visible = false
	end

	ui.editor_summary.Text = (
		"Reliquary Lv %d | Slots: %d/3 | Command: %d | "
			.. "Raise bonus: +%d%%"
	):format(
		new_snapshot.skillReliquaryLevel or 1,
		skill_slots,
		new_snapshot.commandCapacity or 5,
		math.floor((new_snapshot.raiseChanceBonus or 0) * 100)
	)

	clear_skill_rows()
	for _, definition in ipairs(new_snapshot.skills or {}) do
		render_skill_row(definition)
	end

	ui.rebirth.Visible = new_snapshot.canRebirth == true
end

--[[
	Updates visible cooldown text on equipped skill slots.

	Args:
		None.

	Returns:
		None.
]]
local function update_cooldowns()
	if not snapshot then
		return
	end

	local now = Workspace:GetServerTimeNow()
	for index, button in ipairs(ui.slots) do
		local skill_id = snapshot.equippedSkills
			and snapshot.equippedSkills[index]
		if skill_id then
			local remaining = math.max(
				0,
				(cooldowns[skill_id] or 0) - now
			)
			if remaining > 0 then
				button.Text = ("[%s] %s\n%.1fs"):format(
					SLOT_KEY_NAMES[index],
					skill_name(skill_id),
					remaining
				)
			else
				button.Text = ("[%s] %s"):format(
					SLOT_KEY_NAMES[index],
					skill_name(skill_id)
				)
			end
		end
	end
end

--[[
	Refreshes Base-only editor visibility after zone changes.

	Args:
		None.

	Returns:
		None.
]]
local function refresh_zone()
	local in_base = LOCAL_PLAYER:GetAttribute("PvPZone") == "SafeZone"
	ui.editor_button.Visible = false

	if not in_base then
		editor_visible = false
		ui.editor.Visible = false
	end

	if in_base
		and LOCAL_PLAYER:GetAttribute("SoulProfileLoaded") == true
	then
		Remotes.progression():FireServer("REQUEST")
	end
end

for index, button in ipairs(ui.slots) do
	button.MouseButton1Click:Connect(function()
		cast_slot(index)
	end)
end

ui.editor_button.MouseButton1Click:Connect(function()
	editor_visible = not editor_visible
	ui.editor.Visible = editor_visible
	if editor_visible then
		Remotes.progression():FireServer("REQUEST")
	end
end)

ui.rebirth.MouseButton1Click:Connect(function()
	Remotes.progression():FireServer("REBIRTH")
end)

for index, key_code in ipairs(SLOT_KEYS) do
	ContextActionService:BindAction(
		("NecroSkill%d"):format(index),
		function(
			_action_name: string,
			input_state: Enum.UserInputState
		)
			if input_state == Enum.UserInputState.Begin then
				cast_slot(index)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		key_code
	)
end

Remotes.progression().OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "SNAPSHOT" then
		render_snapshot(payload)
	elseif payload.kind == "RESULT" then
		ui.feedback.Text = tostring(payload.message or "")
	end
end)

Remotes.skills().OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table"
		or payload.kind ~= "CAST_RESULT"
	then
		return
	end

	local skill_id = payload.skillId
	if typeof(skill_id) == "string"
		and typeof(payload.readyAt) == "number"
	then
		cooldowns[skill_id] = payload.readyAt
	end
	ui.feedback.Text = tostring(payload.message or "")
end)

LOCAL_PLAYER:GetAttributeChangedSignal("PvPZone"):Connect(refresh_zone)
LOCAL_PLAYER:GetAttributeChangedSignal(
	"SoulProfileLoaded"
):Connect(refresh_zone)

RunService.RenderStepped:Connect(update_cooldowns)

task.defer(function()
	refresh_zone()
	Remotes.progression():FireServer("REQUEST")
end)
