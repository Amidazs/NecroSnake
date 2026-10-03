--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local remote = Remotes.formation_profile()

local COHORTS = {
	"Frontline",
	"SecondLine",
	"Ranged",
	"Flanks",
	"RearGuard",
	"PersonalGuard",
}

local COHORT_LABELS: { [string]: string } = {
	Frontline = "Frontline",
	SecondLine = "Second Line",
	Ranged = "Ranged",
	Flanks = "Flanks",
	RearGuard = "Rear Guard",
	PersonalGuard = "Personal Guard",
}

type TemplateRow = {
	name: string,
	cohort: string,
	defaultCohort: string,
	overridden: boolean,
}

local templates: { TemplateRow } = {}
local selected_template: string? = nil
local persistence_available = false
local last_safe_zone_state = false

local gui = Instance.new("ScreenGui")
gui.Name = "NecroFormationEditorGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local open_button = Instance.new("TextButton")
open_button.Name = "OpenFormationEditor"
open_button.AnchorPoint = Vector2.new(0.5, 1)
open_button.Position = UDim2.new(0.5, 0, 1, -178)
open_button.Size = UDim2.fromOffset(190, 38)
open_button.BackgroundColor3 = Color3.fromRGB(31, 43, 38)
open_button.BackgroundTransparency = 0.05
open_button.BorderSizePixel = 0
open_button.Font = Enum.Font.GothamBold
open_button.TextSize = 14
open_button.TextColor3 = Color3.fromRGB(220, 235, 226)
open_button.Text = "Base Formation Editor"
open_button.Visible = false
open_button.Parent = gui

local open_corner = Instance.new("UICorner")
open_corner.CornerRadius = UDim.new(0, 7)
open_corner.Parent = open_button

local open_stroke = Instance.new("UIStroke")
open_stroke.Color = Color3.fromRGB(100, 160, 130)
open_stroke.Transparency = 0.25
open_stroke.Thickness = 1.2
open_stroke.Parent = open_button

local panel = Instance.new("Frame")
panel.Name = "FormationEditor"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(760, 410)
panel.BackgroundColor3 = Color3.fromRGB(12, 15, 17)
panel.BackgroundTransparency = 0.03
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local panel_corner = Instance.new("UICorner")
panel_corner.CornerRadius = UDim.new(0, 10)
panel_corner.Parent = panel

local panel_stroke = Instance.new("UIStroke")
panel_stroke.Color = Color3.fromRGB(91, 133, 114)
panel_stroke.Transparency = 0.16
panel_stroke.Thickness = 1.3
panel_stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Position = UDim2.fromOffset(18, 12)
title.Size = UDim2.new(1, -70, 0, 26)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(225, 238, 230)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Base Formation Editor"
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromOffset(18, 40)
subtitle.Size = UDim2.new(1, -36, 0, 34)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextColor3 = Color3.fromRGB(155, 180, 168)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextWrapped = true
subtitle.Text = "Choose the default cohort for each unit type. "
	.. "Newly deployed, raised, or cloned units inherit this rule."
subtitle.Parent = panel

local close_button = Instance.new("TextButton")
close_button.Name = "Close"
close_button.AnchorPoint = Vector2.new(1, 0)
close_button.Position = UDim2.new(1, -12, 0, 10)
close_button.Size = UDim2.fromOffset(36, 30)
close_button.BackgroundColor3 = Color3.fromRGB(43, 31, 34)
close_button.BorderSizePixel = 0
close_button.Font = Enum.Font.GothamBold
close_button.TextSize = 16
close_button.TextColor3 = Color3.fromRGB(235, 215, 220)
close_button.Text = "X"
close_button.Parent = panel

local close_corner = Instance.new("UICorner")
close_corner.CornerRadius = UDim.new(0, 6)
close_corner.Parent = close_button

local persistence_label = Instance.new("TextLabel")
persistence_label.Name = "Persistence"
persistence_label.Position = UDim2.fromOffset(18, 75)
persistence_label.Size = UDim2.new(1, -36, 0, 20)
persistence_label.BackgroundTransparency = 1
persistence_label.Font = Enum.Font.GothamMedium
persistence_label.TextSize = 11
persistence_label.TextColor3 = Color3.fromRGB(185, 200, 190)
persistence_label.TextXAlignment = Enum.TextXAlignment.Left
persistence_label.Text = "Loading saved formation profile..."
persistence_label.Parent = panel

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(278, 103)
divider.Size = UDim2.new(0, 1, 1, -121)
divider.BackgroundColor3 = Color3.fromRGB(70, 87, 79)
divider.BorderSizePixel = 0
divider.Parent = panel

local template_list = Instance.new("ScrollingFrame")
template_list.Name = "Templates"
template_list.Position = UDim2.fromOffset(16, 104)
template_list.Size = UDim2.fromOffset(248, 286)
template_list.BackgroundColor3 = Color3.fromRGB(18, 23, 24)
template_list.BackgroundTransparency = 0.2
template_list.BorderSizePixel = 0
template_list.ScrollBarThickness = 5
template_list.CanvasSize = UDim2.new()
template_list.AutomaticCanvasSize = Enum.AutomaticSize.Y
template_list.Parent = panel

local template_padding = Instance.new("UIPadding")
template_padding.PaddingTop = UDim.new(0, 6)
template_padding.PaddingBottom = UDim.new(0, 6)
template_padding.PaddingLeft = UDim.new(0, 6)
template_padding.PaddingRight = UDim.new(0, 6)
template_padding.Parent = template_list

local template_layout = Instance.new("UIListLayout")
template_layout.Padding = UDim.new(0, 5)
template_layout.SortOrder = Enum.SortOrder.LayoutOrder
template_layout.Parent = template_list

local selected_title = Instance.new("TextLabel")
selected_title.Position = UDim2.fromOffset(298, 108)
selected_title.Size = UDim2.new(1, -316, 0, 28)
selected_title.BackgroundTransparency = 1
selected_title.Font = Enum.Font.GothamBold
selected_title.TextSize = 18
selected_title.TextColor3 = Color3.fromRGB(224, 235, 228)
selected_title.TextXAlignment = Enum.TextXAlignment.Left
selected_title.Text = "Select a unit type"
selected_title.Parent = panel

local selected_info = Instance.new("TextLabel")
selected_info.Position = UDim2.fromOffset(298, 138)
selected_info.Size = UDim2.new(1, -316, 0, 42)
selected_info.BackgroundTransparency = 1
selected_info.Font = Enum.Font.Gotham
selected_info.TextSize = 12
selected_info.TextColor3 = Color3.fromRGB(160, 182, 170)
selected_info.TextXAlignment = Enum.TextXAlignment.Left
selected_info.TextYAlignment = Enum.TextYAlignment.Top
selected_info.TextWrapped = true
selected_info.Text = "Its saved default cohort will appear here."
selected_info.Parent = panel

local cohort_container = Instance.new("Frame")
cohort_container.Position = UDim2.fromOffset(298, 190)
cohort_container.Size = UDim2.new(1, -316, 0, 116)
cohort_container.BackgroundTransparency = 1
cohort_container.Parent = panel

local cohort_grid = Instance.new("UIGridLayout")
cohort_grid.CellSize = UDim2.fromOffset(137, 46)
cohort_grid.CellPadding = UDim2.fromOffset(8, 8)
cohort_grid.FillDirection = Enum.FillDirection.Horizontal
cohort_grid.SortOrder = Enum.SortOrder.LayoutOrder
cohort_grid.Parent = cohort_container

local cohort_buttons: { [string]: TextButton } = {}

local reset_button = Instance.new("TextButton")
reset_button.Name = "ResetDefault"
reset_button.Position = UDim2.fromOffset(298, 323)
reset_button.Size = UDim2.fromOffset(180, 36)
reset_button.BackgroundColor3 = Color3.fromRGB(44, 39, 28)
reset_button.BorderSizePixel = 0
reset_button.Font = Enum.Font.GothamBold
reset_button.TextSize = 12
reset_button.TextColor3 = Color3.fromRGB(235, 220, 180)
reset_button.Text = "Reset to unit default"
reset_button.Parent = panel

local reset_corner = Instance.new("UICorner")
reset_corner.CornerRadius = UDim.new(0, 6)
reset_corner.Parent = reset_button

local feedback = Instance.new("TextLabel")
feedback.Position = UDim2.fromOffset(298, 365)
feedback.Size = UDim2.new(1, -316, 0, 28)
feedback.BackgroundTransparency = 1
feedback.Font = Enum.Font.GothamMedium
feedback.TextSize = 11
feedback.TextColor3 = Color3.fromRGB(165, 195, 177)
feedback.TextXAlignment = Enum.TextXAlignment.Left
feedback.TextWrapped = true
feedback.Text = ""
feedback.Parent = panel

local function format_cohort(cohort: string): string
	return COHORT_LABELS[cohort] or cohort
end

local function find_template(name: string): TemplateRow?
	for _, row in ipairs(templates) do
		if row.name == name then
			return row
		end
	end
	return nil
end

local function update_selected_details()
	local name = selected_template
	local row = name and find_template(name) or nil
	if not row then
		selected_title.Text = "Select a unit type"
		selected_info.Text = "Its saved default cohort will appear here."
		for _, button in pairs(cohort_buttons) do
			button.BackgroundColor3 = Color3.fromRGB(28, 34, 32)
		end
		return
	end

	selected_title.Text = row.name
	local source = row.overridden and "Saved override" or "Unit default"
	selected_info.Text = ("%s: %s\nCatalogue default: %s"):format(
		source,
		format_cohort(row.cohort),
		format_cohort(row.defaultCohort)
	)

	for cohort, button in pairs(cohort_buttons) do
		button.BackgroundColor3 = cohort == row.cohort
			and Color3.fromRGB(43, 85, 65)
			or Color3.fromRGB(28, 34, 32)
	end
end

local function rebuild_template_list()
	for _, child in ipairs(template_list:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for index, row in ipairs(templates) do
		local button = Instance.new("TextButton")
		button.Name = row.name .. "Template"
		button.LayoutOrder = index
		button.Size = UDim2.new(1, 0, 0, 38)
		button.BackgroundColor3 = Color3.fromRGB(26, 33, 31)
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.Font = Enum.Font.GothamMedium
		button.TextSize = 12
		button.TextColor3 = Color3.fromRGB(220, 229, 223)
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = ("  %s  —  %s%s"):format(
			row.name,
			format_cohort(row.cohort),
			row.overridden and " *" or ""
		)
		button.Parent = template_list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = button

		button.Activated:Connect(function()
			selected_template = row.name
			update_selected_details()
		end)
	end

	if selected_template and not find_template(selected_template) then
		selected_template = nil
	end
	if not selected_template and #templates > 0 then
		selected_template = templates[1].name
	end
	update_selected_details()
end

for index, cohort in ipairs(COHORTS) do
	local button = Instance.new("TextButton")
	button.Name = cohort .. "Default"
	button.LayoutOrder = index
	button.BackgroundColor3 = Color3.fromRGB(28, 34, 32)
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = Color3.fromRGB(218, 230, 222)
	button.TextWrapped = true
	button.Text = format_cohort(cohort)
	button.Parent = cohort_container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	button.Activated:Connect(function()
		if not selected_template then
			feedback.Text = "Choose a unit type first."
			return
		end
		remote:FireServer("SET_TEMPLATE", {
			template = selected_template,
			cohort = cohort,
		})
	end)

	cohort_buttons[cohort] = button
end

reset_button.Activated:Connect(function()
	if not selected_template then
		feedback.Text = "Choose a unit type first."
		return
	end
	remote:FireServer("RESET_TEMPLATE", {
		template = selected_template,
	})
end)

local function get_safe_zone_region(): BasePart?
	local zones = Workspace:FindFirstChild("Zones")
	local safe_world = zones and zones:FindFirstChild("SafeZoneWorld")
	local region = safe_world and safe_world:FindFirstChild("SafeZoneRegion")
	if region and region:IsA("BasePart") then
		return region
	end
	return nil
end

local function is_in_safe_zone(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local region = get_safe_zone_region()
	if not (root and root:IsA("BasePart") and region) then
		return false
	end

	local local_position = region.CFrame:PointToObjectSpace(root.Position)
	local half = region.Size * 0.5
	return math.abs(local_position.X) <= half.X
		and math.abs(local_position.Y) <= half.Y
		and math.abs(local_position.Z) <= half.Z
end

open_button.Activated:Connect(function()
	panel.Visible = true
	feedback.Text = ""
	remote:FireServer("REQUEST")
end)

close_button.Activated:Connect(function()
	panel.Visible = false
end)

remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "SNAPSHOT" then
		local incoming = payload.templates
		if typeof(incoming) == "table" then
			templates = incoming
			rebuild_template_list()
		end

		persistence_available = payload.persistent == true
		if persistence_available then
			persistence_label.Text = "Saved profile: persistent across sessions."
			persistence_label.TextColor3 = Color3.fromRGB(145, 220, 170)
		else
			persistence_label.Text =
				"Studio/session fallback: profile changes work now; "
				.. "published servers save them persistently."
			persistence_label.TextColor3 = Color3.fromRGB(225, 190, 115)
		end
		return
	end

	if payload.kind == "RESULT" then
		local ok = payload.ok == true
		local message = payload.message
		if typeof(message) == "string" then
			feedback.Text = message
			feedback.TextColor3 = ok
				and Color3.fromRGB(145, 220, 170)
				or Color3.fromRGB(235, 145, 125)
		end
	end
end)

task.spawn(function()
	while gui.Parent ~= nil do
		local safe = is_in_safe_zone()
		open_button.Visible = false
		if not safe and panel.Visible then
			panel.Visible = false
		end
		if safe and not last_safe_zone_state then
			remote:FireServer("REQUEST")
		end
		last_safe_zone_state = safe
		task.wait(0.4)
	end
end)
