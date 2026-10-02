--!strict
-- BackpackPanel.client.lua
-- Responsive "Army Manager" UI (viewport-based):
-- - Anchored bottom-left with margins (icon + panel never off-screen)
-- - Panel size clamps to camera.ViewportSize (works on any resolution)
-- - Disabled in Arena (entire UI disabled + hidden)
-- - Drag units from Backpack -> Arena Team
-- - Click a filled Arena slot to return 1 unit back to Backpack

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local player_gui = player:WaitForChild("PlayerGui")

local DEBUG = false
local GUI_NAME = "NecroBackpackGui"

type UnitSnapshot = {
	record_id: string?,
	template_name: string,
	size_tier: string?,
	trait: string?,
	evolution_id: string?,
	ability_ids: { string }?,
	source_master_id: string?,
	deployed_master_id: string?,
	acquisition_kind: string?,
	command_cost: number?,
}

type StackedEntry = {
	key: string,
	template_name: string,
	size_tier: string?,
	trait: string?,
	evolution_id: string?,
	ability_ids: { string }?,
	deployed_master_id: string?,
	total_count: number,
}

local function dprint(msg: string)
	if DEBUG then
		print("[BackpackUI] " .. msg)
	end
end

local function unit_key(u: UnitSnapshot): string
	return table.concat({
		u.template_name,
		u.size_tier or "",
		u.trait or "",
		u.evolution_id or "",
		table.concat(u.ability_ids or {}, ","),
		u.deployed_master_id or "",
	}, "|")
end

-- =========================
-- Zones
-- =========================

local ZONES_FOLDER_NAME = "Zones"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local ARENA_MODEL_NAME = "ArenaWorld"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"

local ARENA_REGION_CANDIDATES = {
	"ArenaSpawnRegion",
	"ArenaRegion",
}

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

local function get_arena_region_part(): BasePart?
	for _, name in ipairs(ARENA_REGION_CANDIDATES) do
		local part = get_region_part(ARENA_MODEL_NAME, name)
		if part then
			return part
		end
	end
	return nil
end

local function get_zone(): string
	local character = player.Character
	if not character then
		return "Unknown"
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return "Unknown"
	end

	local safe_region = get_region_part(SAFE_ZONE_MODEL_NAME, SAFE_ZONE_REGION_NAME)
	local arena_region = get_arena_region_part()

	if safe_region and is_point_in_part_bounds(safe_region, root.Position) then
		return "SafeZone"
	end

	if arena_region and is_point_in_part_bounds(arena_region, root.Position) then
		return "Arena"
	end

	return "Unknown"
end

local function is_in_arena(): boolean
	return get_zone() == "Arena"
end

-- =========================
-- Rarity styling
-- =========================

local RARITY_COLOURS: { [string]: Color3 } = {
	Normal = Color3.fromRGB(120, 200, 170),
	Small = Color3.fromRGB(140, 180, 255),
	Giant = Color3.fromRGB(255, 140, 140),
	Tough = Color3.fromRGB(255, 210, 120),
	Frenzied = Color3.fromRGB(255, 120, 200),
	None = Color3.fromRGB(120, 200, 170),
}

local RARITY_RANK: { [string]: number } = {
	Normal = 1,
	None = 1,
	Small = 2,
	Tough = 3,
	Frenzied = 4,
	Giant = 5,
}

local function rarity_rank(size_tier: string?, trait: string?): number
	if trait and RARITY_RANK[trait] then
		return RARITY_RANK[trait]
	end
	if size_tier and RARITY_RANK[size_tier] then
		return RARITY_RANK[size_tier]
	end
	return 1
end

local function rarity_colour(size_tier: string?, trait: string?): Color3
	if trait and RARITY_COLOURS[trait] then
		return RARITY_COLOURS[trait]
	end
	if size_tier and RARITY_COLOURS[size_tier] then
		return RARITY_COLOURS[size_tier]
	end
	return RARITY_COLOURS.Normal
end

local function display_name(entry: StackedEntry): string
	local name = entry.template_name
	if entry.size_tier and entry.size_tier ~= "" and entry.size_tier ~= "Normal" then
		name = entry.size_tier .. " " .. name
	end
	if entry.trait and entry.trait ~= "" and entry.trait ~= "None" then
		name = entry.trait .. " " .. name
	end
	if entry.evolution_id and entry.evolution_id ~= "" then
		name ..= " [" .. entry.evolution_id .. "]"
	end
	if entry.deployed_master_id then
		name = "MASTER AT RISK: " .. name
	end
	return name
end

local function stack_units(units: { UnitSnapshot }): { StackedEntry }
	local map: { [string]: StackedEntry } = {}

	for _, u in ipairs(units) do
		local key = unit_key(u)
		if not map[key] then
			map[key] = {
				key = key,
				template_name = u.template_name,
				size_tier = u.size_tier,
				trait = u.trait,
				evolution_id = u.evolution_id,
				ability_ids = u.ability_ids,
				deployed_master_id = u.deployed_master_id,
				total_count = 0,
			}
		end
		map[key].total_count += 1
	end

	local out: { StackedEntry } = {}
	for _, e in pairs(map) do
		table.insert(out, e)
	end

	return out
end

-- =========================
-- UI construction
-- =========================

local function destroy_existing_gui()
	local existing = player_gui:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end
end

local function make_corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function make_stroke(
	inst: Instance,
	thickness: number,
	colour: Color3,
	transparency: number
): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = colour
	s.Transparency = transparency
	s.Parent = inst
	return s
end

local function make_label(
	parent: Instance,
	name: string,
	text: string,
	size: number,
	bold: boolean
): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Name = name
	lbl.BackgroundTransparency = 1
	lbl.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	lbl.TextColor3 = Color3.fromRGB(235, 255, 245)
	lbl.TextSize = size
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.Parent = parent
	return lbl
end

local function apply_rarity_glow(stroke: UIStroke, size_tier: string?, trait: string?)
	stroke.Color = rarity_colour(size_tier, trait)
	stroke.Transparency = 0.25
end

local function create_gui()
	destroy_existing_gui()

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player_gui

	local icon_button = Instance.new("TextButton")
	icon_button.Name = "Icon"
	icon_button.AnchorPoint = Vector2.new(0, 1)
	icon_button.Size = UDim2.fromOffset(54, 54)
	icon_button.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	icon_button.Text = "🎒"
	icon_button.TextSize = 28
	icon_button.Font = Enum.Font.GothamBold
	icon_button.TextColor3 = Color3.fromRGB(210, 255, 235)
	icon_button.Parent = gui
	make_corner(icon_button, 12)

	local icon_stroke = make_stroke(icon_button, 2, Color3.fromRGB(80, 255, 170), 0.18)
	TweenService:Create(
		icon_stroke,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.05 }
	):Play()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	panel.BackgroundTransparency = 0.12
	panel.Visible = false
	panel.Parent = gui
	panel.ClipsDescendants = true
	make_corner(panel, 14)

	local panel_stroke = make_stroke(panel, 2, Color3.fromRGB(80, 255, 170), 0.22)
	TweenService:Create(
		panel_stroke,
		TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.08 }
	):Play()

	local title = make_label(panel, "Title", "Army Manager", 20, true)
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 24)

	local subtitle = make_label(
		panel,
		"Subtitle",
		"Drag units from Backpack into Arena Team. Click Arena slot to return.",
		12,
		false
	)
	subtitle.Position = UDim2.fromOffset(14, 36)
	subtitle.Size = UDim2.new(1, -28, 0, 30)
	subtitle.TextColor3 = Color3.fromRGB(170, 200, 190)
	subtitle.TextWrapped = true

	local sort_btn = Instance.new("TextButton")
	sort_btn.Name = "SortBtn"
	sort_btn.AnchorPoint = Vector2.new(1, 0)
	sort_btn.Position = UDim2.new(1, -14, 0, 10)
	sort_btn.Size = UDim2.fromOffset(96, 26)
	sort_btn.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	sort_btn.TextColor3 = Color3.fromRGB(235, 255, 245)
	sort_btn.Font = Enum.Font.GothamBold
	sort_btn.TextSize = 12
	sort_btn.Text = "Sort: Rarity"
	sort_btn.Parent = panel
	make_corner(sort_btn, 10)
	make_stroke(sort_btn, 1, Color3.fromRGB(80, 255, 170), 0.45)

	local arena_section = Instance.new("Frame")
	arena_section.Name = "ArenaSection"
	arena_section.Position = UDim2.fromOffset(14, 76)
	arena_section.Size = UDim2.new(1, -28, 0, 92)
	arena_section.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	arena_section.BackgroundTransparency = 0.15
	arena_section.Parent = panel
	arena_section.ClipsDescendants = true
	make_corner(arena_section, 12)
	local arena_stroke = make_stroke(
		arena_section,
		1,
		Color3.fromRGB(80, 255, 170),
		0.75
	)
	arena_stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border


	local arena_title = make_label(arena_section, "ArenaTitle", "Arena Team", 13, false)
	arena_title.Position = UDim2.fromOffset(10, 8)
	arena_title.Size = UDim2.new(1, -20, 0, 16)
	arena_title.TextColor3 = Color3.fromRGB(190, 220, 210)

	local clear_btn = Instance.new("TextButton")
	clear_btn.Name = "ClearBtn"
	clear_btn.AnchorPoint = Vector2.new(1, 0)
	clear_btn.Position = UDim2.new(1, -10, 0, 8)
	clear_btn.Size = UDim2.fromOffset(80, 18)
	clear_btn.BackgroundTransparency = 1
	clear_btn.TextXAlignment = Enum.TextXAlignment.Right
	clear_btn.Text = "Clear"
	clear_btn.Font = Enum.Font.GothamBold
	clear_btn.TextSize = 12
	clear_btn.TextColor3 = Color3.fromRGB(255, 200, 120)
	clear_btn.Parent = arena_section

	local slot_container = Instance.new("Frame")
	slot_container.Name = "SlotContainer"
	slot_container.Position = UDim2.fromOffset(10, 32)
	slot_container.Size = UDim2.new(1, -20, 0, 52)
	slot_container.BackgroundTransparency = 1
	slot_container.Parent = arena_section

	local slot_layout = Instance.new("UIListLayout")
	slot_layout.FillDirection = Enum.FillDirection.Horizontal
	slot_layout.Padding = UDim.new(0, 8)
	slot_layout.Parent = slot_container

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Position = UDim2.fromOffset(14, 178)
	divider.Size = UDim2.new(1, -28, 0, 1)
	divider.BackgroundColor3 = Color3.fromRGB(80, 255, 170)
	divider.BackgroundTransparency = 0.80
	divider.Parent = panel

	local backpack_title = make_label(panel, "BackpackTitle", "Backpack", 13, false)
	backpack_title.Position = UDim2.fromOffset(14, 188)
	backpack_title.Size = UDim2.new(1, -28, 0, 16)
	backpack_title.TextColor3 = Color3.fromRGB(190, 220, 210)

	local hint = make_label(panel, "Hint", "Drag to add. Counts update instantly.", 12, false)
	hint.Position = UDim2.fromOffset(14, 206)
	hint.Size = UDim2.new(1, -28, 0, 14)
	hint.TextColor3 = Color3.fromRGB(150, 180, 170)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.Position = UDim2.fromOffset(14, 228)
	scroll.Size = UDim2.new(1, -28, 1, -242)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(68, 68)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.Visible = false
	tooltip.Size = UDim2.fromOffset(220, 74)
	tooltip.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	tooltip.BackgroundTransparency = 0.10
	tooltip.Parent = gui
	make_corner(tooltip, 12)
	make_stroke(tooltip, 2, Color3.fromRGB(80, 255, 170), 0.20)

	local tip_title = make_label(tooltip, "TipTitle", "Unit", 14, true)
	tip_title.Position = UDim2.fromOffset(12, 8)
	tip_title.Size = UDim2.fromOffset(196, 18)

	local tip_body = make_label(tooltip, "TipBody", "Details", 12, false)
	tip_body.Position = UDim2.fromOffset(12, 28)
	tip_body.Size = UDim2.fromOffset(196, 40)
	tip_body.TextColor3 = Color3.fromRGB(170, 200, 190)
	tip_body.TextWrapped = true

	return gui, icon_button, panel, scroll, grid, tooltip, slot_container, sort_btn, clear_btn
end

local gui, icon_button, panel, scroll, grid, tooltip, slot_container, sort_btn, clear_btn =
	create_gui()

-- =========================
-- Responsive layout (FIXED: use camera.ViewportSize, not ScreenGui.AbsoluteSize)
-- =========================

local ICON_MARGIN = 16
local PANEL_MARGIN = 16
local ICON_PANEL_GAP = 10

local PANEL_MAX_WIDTH = 360
local PANEL_MAX_HEIGHT = 440
local PANEL_MIN_WIDTH = 300
local PANEL_MIN_HEIGHT = 340

local function clamp(v: number, min_v: number, max_v: number): number
	return math.max(min_v, math.min(max_v, v))
end

local function get_viewport_size(): Vector2
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function apply_responsive_layout()
	local viewport = get_viewport_size()
	local view_w = viewport.X
	local view_h = viewport.Y

	-- Icon stays bottom-left
	icon_button.Position = UDim2.fromOffset(ICON_MARGIN, view_h - ICON_MARGIN)

	-- Panel size clamps to viewport
	local max_w = math.max(PANEL_MIN_WIDTH, view_w - (PANEL_MARGIN * 2))
	local max_h = math.max(PANEL_MIN_HEIGHT, view_h - (PANEL_MARGIN * 2) - 20)

	local panel_w = clamp(PANEL_MAX_WIDTH, PANEL_MIN_WIDTH, max_w)
	local panel_h = clamp(PANEL_MAX_HEIGHT, PANEL_MIN_HEIGHT, max_h)

	panel.Size = UDim2.fromOffset(panel_w, panel_h)

	-- Panel sits above icon, anchored bottom-left
	local panel_bottom_y =
		(view_h - ICON_MARGIN) - icon_button.AbsoluteSize.Y - ICON_PANEL_GAP
	panel.Position = UDim2.fromOffset(PANEL_MARGIN, panel_bottom_y)

	-- Keep scroll height correct if panel height changes
	scroll.Size = UDim2.new(1, -28, 1, -242)
end

apply_responsive_layout()

local function connect_viewport_listener()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		apply_responsive_layout()
	end)
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	task.wait()
	connect_viewport_listener()
	apply_responsive_layout()
end)

connect_viewport_listener()

-- =========================
-- State
-- =========================

local latest_snapshot: { UnitSnapshot } = {}
local sort_mode: "Rarity" | "Name" = "Rarity"
local loadout_counts: { [string]: number } = {}
local latest_entry_by_key: { [string]: StackedEntry } = {}
local MAX_SLOTS = 5


local render: (({ UnitSnapshot }) -> ())? = nil

local function set_panel_open(open: boolean)
	panel.Visible = open
end

local function send_loadout_to_server()
	Remotes.backpack_set_loadout():FireServer(loadout_counts)
end

local function refresh_ui_after_loadout_change()
	if render and latest_snapshot then
		render(latest_snapshot)
	end
end

icon_button.MouseButton1Click:Connect(function()
	if is_in_arena() then
		return
	end
	set_panel_open(not panel.Visible)
end)

sort_btn.MouseButton1Click:Connect(function()
	if sort_mode == "Rarity" then
		sort_mode = "Name"
		sort_btn.Text = "Sort: Name"
	else
		sort_mode = "Rarity"
		sort_btn.Text = "Sort: Rarity"
	end

	if latest_snapshot and render then
		render(latest_snapshot)
	end
end)

-- =========================
-- Tooltip
-- =========================

local function hide_tooltip()
	tooltip.Visible = false
end

local function show_tooltip(entry: StackedEntry, remaining: number)
	local title = tooltip:FindFirstChild("TipTitle") :: TextLabel?
	local body = tooltip:FindFirstChild("TipBody") :: TextLabel?
	if not title or not body then
		return
	end

	title.Text = display_name(entry)

	local selected = loadout_counts[entry.key] or 0
	body.Text = ("Backpack: %d\nSelected: %d\nAvailable: %d\n"
		.. "(Drag to add, click slot to return)"):format(
		entry.total_count,
		selected,
		remaining
	)

	tooltip.Visible = true
end

UserInputService.InputChanged:Connect(function(input)
	if not tooltip.Visible then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local pos = input.Position
	tooltip.Position = UDim2.fromOffset(pos.X + 14, pos.Y + 14)
end)

-- =========================
-- UI helpers
-- =========================

local function clear_tiles()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function clear_slots()
	for _, child in ipairs(slot_container:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function render_slots()
	clear_slots()

	local entries: { { key: string, count: number } } = {}
	for k, c in pairs(loadout_counts) do
		if c > 0 then
			table.insert(entries, { key = k, count = c })
		end
	end

	table.sort(entries, function(a, b)
		return a.key < b.key
	end)

	local slot_index = 0

	for _, e in ipairs(entries) do
		slot_index += 1
		if slot_index > MAX_SLOTS then
			break
		end

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(62, 52)
		btn.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		btn.Text = ""
		btn.Parent = slot_container
		make_corner(btn, 10)
		make_stroke(btn, 1, Color3.fromRGB(80, 255, 170), 0.45)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 11
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(235, 255, 245)

		local entry = latest_entry_by_key[e.key]

		local name_to_show = e.key:split("|")[1]
		if entry then
			name_to_show = display_name(entry)
		end

		label.Text = ("x%d\n%s"):format(e.count, name_to_show)

		label.Parent = btn

		btn.MouseButton1Click:Connect(function()
			if is_in_arena() then
				return
			end

			local current = loadout_counts[e.key] or 0
			if current <= 0 then
				return
			end

			loadout_counts[e.key] = current - 1
			if loadout_counts[e.key] <= 0 then
				loadout_counts[e.key] = nil
			end

			render_slots()
			send_loadout_to_server()
			refresh_ui_after_loadout_change()
		end)
	end

	while slot_index < MAX_SLOTS do
		slot_index += 1

		local empty = Instance.new("TextButton")
		empty.Size = UDim2.fromOffset(62, 52)
		empty.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		empty.BackgroundTransparency = 0.2
		empty.Text = "+"
		empty.Font = Enum.Font.GothamBold
		empty.TextSize = 18
		empty.TextColor3 = Color3.fromRGB(120, 140, 135)
		empty.Parent = slot_container
		make_corner(empty, 10)
		make_stroke(empty, 1, Color3.fromRGB(80, 255, 170), 0.65)
	end
end

clear_btn.MouseButton1Click:Connect(function()
	if is_in_arena() then
		return
	end

	loadout_counts = {}
	render_slots()
	send_loadout_to_server()
	refresh_ui_after_loadout_change()
end)

-- =========================
-- Drag logic
-- =========================

local dragging = false
local drag_entry: StackedEntry? = nil
local drag_ghost: Frame? = nil

local function make_ghost(entry: StackedEntry): Frame
	local g = Instance.new("Frame")
	g.Size = UDim2.fromOffset(68, 68)
	g.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	g.BackgroundTransparency = 0.05
	g.Parent = gui
	make_corner(g, 10)

	local s = make_stroke(g, 2, rarity_colour(entry.size_tier, entry.trait), 0.10)
	apply_rarity_glow(s, entry.size_tier, entry.trait)

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 12
	t.TextWrapped = true
	t.TextColor3 = Color3.fromRGB(235, 255, 245)
	t.Text = display_name(entry)
	t.Parent = g

	return g
end

local function cancel_drag()
	dragging = false
	drag_entry = nil

	if drag_ghost then
		drag_ghost:Destroy()
		drag_ghost = nil
	end
end

local function begin_drag(entry: StackedEntry)
	if is_in_arena() then
		return
	end

	dragging = true
	drag_entry = entry
	hide_tooltip()
	drag_ghost = make_ghost(entry)
end

local function end_drag()
	if is_in_arena() then
		cancel_drag()
		return
	end

	if not dragging or not drag_entry then
		return
	end

	local key = drag_entry.key
	local selected = loadout_counts[key] or 0
	local remaining = drag_entry.total_count - selected

	if remaining > 0 then
		loadout_counts[key] = selected + 1
		render_slots()
		send_loadout_to_server()
		refresh_ui_after_loadout_change()
	end

	cancel_drag()
end

UserInputService.InputChanged:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	if drag_ghost then
		local p = input.Position
		drag_ghost.Position = UDim2.fromOffset(p.X - 34, p.Y - 34)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if dragging then
		end_drag()
	end
end)

-- =========================
-- Rendering tiles
-- =========================

local function sort_entries(entries: { StackedEntry })
	table.sort(entries, function(a, b)
		if sort_mode == "Name" then
			local an = display_name(a)
			local bn = display_name(b)
			if an == bn then
				return a.key < b.key
			end
			return an < bn
		end

		local ar = rarity_rank(a.size_tier, a.trait)
		local br = rarity_rank(b.size_tier, b.trait)
		if ar == br then
			local an = display_name(a)
			local bn = display_name(b)
			if an == bn then
				return a.key < b.key
			end
			return an < bn
		end
		return ar > br
	end)
end

render = function(snapshot: { UnitSnapshot })
	latest_snapshot = snapshot

	clear_tiles()

	local entries = stack_units(snapshot)

	-- Build lookup so Arena Team slots can display full rarity names
	latest_entry_by_key = {}
	for _, e in ipairs(entries) do
		latest_entry_by_key[e.key] = e
	end

	sort_entries(entries)


	for i, entry in ipairs(entries) do
		local selected = loadout_counts[entry.key] or 0
		local remaining = entry.total_count - selected
		if remaining < 0 then
			remaining = 0
		end

		local tile = Instance.new("TextButton")
		tile.Size = UDim2.fromOffset(68, 68)
		tile.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
		tile.Text = ""
		tile.Parent = scroll
		tile.LayoutOrder = i
		make_corner(tile, 10)

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = tile
		apply_rarity_glow(stroke, entry.size_tier, entry.trait)

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 11
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(235, 255, 245)
		label.Text = ("%s\nx%d"):format(display_name(entry), remaining)
		label.Parent = tile

		if remaining == 0 then
			tile.AutoButtonColor = false
			tile.Active = false
			tile.BackgroundTransparency = 0.35
			label.TextTransparency = 0.35
		end

		tile.MouseEnter:Connect(function()
			show_tooltip(entry, remaining)
		end)

		tile.MouseLeave:Connect(function()
			hide_tooltip()
		end)

		tile.MouseButton1Down:Connect(function()
			if remaining <= 0 then
				return
			end
			begin_drag(entry)
		end)
	end

	task.wait()
	scroll.CanvasSize = UDim2.fromOffset(0, grid.AbsoluteContentSize.Y + 10)
	render_slots()
end

-- =========================
-- Arena disabling (hard disable)
-- =========================

local function apply_zone_visibility()
	local zone = get_zone()
	local in_arena = zone == "Arena"

	gui.Enabled = not in_arena
	icon_button.Visible = not in_arena

	if in_arena then
		panel.Visible = false
		hide_tooltip()
		cancel_drag()
	end
end

player.CharacterAdded:Connect(function()
	task.wait(0.35)
	apply_zone_visibility()
end)

task.spawn(function()
	while true do
		apply_zone_visibility()
		task.wait(0.35)
	end
end)

Remotes.backpack_update().OnClientEvent:Connect(function(snapshot: { UnitSnapshot })
	dprint("BackpackUpdate received: " .. tostring(#snapshot))
	if render then
		render(snapshot)
	end
end)

task.defer(function()
	dprint("Requesting backpack snapshot...")
	Remotes.backpack_request():FireServer()
end)
