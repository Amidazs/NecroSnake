--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_GUI = LOCAL_PLAYER:WaitForChild("PlayerGui")
local GUI_NAME = "NecroSoulFoundryGui"

type UnitRecord = {
	record_id: string,
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

type MachineSnapshot = {
	machineId: string,
	level: number,
	masterId: string?,
	master: UnitRecord?,
	outputCount: number,
	capacity: number,
	cloneCost: number?,
	cloneSeconds: number?,
	secondsRemaining: number?,
	paused: boolean,
	upgradeCost: number?,
}

type SoulSnapshot = {
	kind: string,
	persistent: boolean,
	inSafeZone: boolean,
	soulEssence: number,
	baseLevel: number,
	baseUpgradeCost: number?,
	units: { UnitRecord },
	masters: { UnitRecord },
	machines: { MachineSnapshot },
}

local active_tab = "Vault"
local latest_snapshot: SoulSnapshot? = nil

local function make_corner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function make_stroke(
	instance: Instance,
	transparency: number
)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(154, 102, 205)
	stroke.Transparency = transparency
	stroke.Thickness = 1
	stroke.Parent = instance
end

local function make_label(
	parent: Instance,
	text: string,
	text_size: number,
	bold: boolean
): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	label.Text = text
	label.TextColor3 = Color3.fromRGB(235, 228, 245)
	label.TextSize = text_size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

local function make_button(
	parent: Instance,
	text: string,
	width: number
): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(width, 28)
	button.BackgroundColor3 = Color3.fromRGB(32, 24, 42)
	button.Text = text
	button.TextColor3 = Color3.fromRGB(238, 220, 255)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.Parent = parent
	make_corner(button, 7)
	make_stroke(button, 0.5)
	return button
end

local function destroy_existing()
	local existing = PLAYER_GUI:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy()
	end
end

local function create_gui()
	destroy_existing()

	local gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = PLAYER_GUI

	local icon = Instance.new("TextButton")
	icon.Name = "FoundryIcon"
	icon.AnchorPoint = Vector2.new(1, 1)
	icon.Position = UDim2.new(1, -18, 1, -18)
	icon.Size = UDim2.fromOffset(58, 58)
	icon.BackgroundColor3 = Color3.fromRGB(19, 14, 26)
	icon.Text = "☠"
	icon.TextSize = 28
	icon.TextColor3 = Color3.fromRGB(218, 180, 255)
	icon.Font = Enum.Font.GothamBold
	icon.Visible = false
	icon.Parent = gui
	make_corner(icon, 12)
	make_stroke(icon, 0.2)

	local panel = Instance.new("Frame")
	panel.Name = "FoundryPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -18, 1, -86)
	panel.Size = UDim2.fromOffset(560, 520)
	panel.BackgroundColor3 = Color3.fromRGB(13, 10, 18)
	panel.BackgroundTransparency = 0.04
	panel.Visible = false
	panel.Parent = gui
	make_corner(panel, 14)
	make_stroke(panel, 0.15)

	local title = make_label(panel, "Soul Foundry", 22, true)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -82, 0, 26)

	local close = make_button(panel, "X", 36)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 12)
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)

	local summary = make_label(panel, "", 13, false)
	summary.Name = "Summary"
	summary.Position = UDim2.fromOffset(16, 42)
	summary.Size = UDim2.new(1, -32, 0, 20)
	summary.TextColor3 = Color3.fromRGB(190, 172, 205)

	local status = make_label(panel, "", 12, false)
	status.Name = "Status"
	status.Position = UDim2.fromOffset(16, 68)
	status.Size = UDim2.new(1, -32, 0, 20)
	status.TextColor3 = Color3.fromRGB(199, 187, 215)

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Position = UDim2.fromOffset(16, 96)
	tabs.Size = UDim2.new(1, -32, 0, 32)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel

	local tabs_layout = Instance.new("UIListLayout")
	tabs_layout.FillDirection = Enum.FillDirection.Horizontal
	tabs_layout.Padding = UDim.new(0, 8)
	tabs_layout.Parent = tabs

	for _, tab_name in ipairs({ "Vault", "Masters", "Machines" }) do
		local button = make_button(tabs, tab_name, 104)
		button.Name = tab_name .. "Tab"
	end

	local base_upgrade = make_button(panel, "Upgrade at Forge", 142)
	base_upgrade.Name = "BaseUpgrade"
	base_upgrade.Visible = false
	base_upgrade.Active = false
	base_upgrade.AnchorPoint = Vector2.new(1, 0)
	base_upgrade.Position = UDim2.new(1, -16, 0, 12)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Position = UDim2.fromOffset(16, 140)
	scroll.Size = UDim2.new(1, -32, 1, -156)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	return gui, icon, panel, summary, status, tabs, base_upgrade, scroll
end

local gui, icon, panel, summary, status, tabs, base_upgrade, scroll =
	create_gui()

local function send_action(action: string, payload: any?)
	Remotes.soul_collection():FireServer(action, payload or {})
end

local function clear_content()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function unit_name(record: UnitRecord): string
	local parts: { string } = {}
	if record.size_tier
		and record.size_tier ~= ""
		and record.size_tier ~= "Normal"
	then
		table.insert(parts, record.size_tier)
	end
	if record.trait
		and record.trait ~= ""
		and record.trait ~= "None"
	then
		table.insert(parts, record.trait)
	end
	table.insert(parts, record.template_name)

	local name = table.concat(parts, " ")
	if record.evolution_id then
		name ..= " [" .. record.evolution_id .. "]"
	end
	return name
end

local function make_row(height: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, height)
	row.BackgroundColor3 = Color3.fromRGB(24, 19, 31)
	row.BackgroundTransparency = 0.08
	row.Parent = scroll
	make_corner(row, 10)
	make_stroke(row, 0.65)
	return row
end

local function make_empty_row(text: string)
	local row = make_row(54)
	local label = make_label(row, text, 13, false)
	label.Position = UDim2.fromOffset(12, 16)
	label.Size = UDim2.new(1, -24, 0, 22)
	label.TextColor3 = Color3.fromRGB(160, 150, 172)
end

local function render_vault(snapshot: SoulSnapshot)
	if #snapshot.units == 0 then
		make_empty_row("No secured deployable units in the Soul Vault.")
		return
	end

	for _, record in ipairs(snapshot.units) do
		local row = make_row(72)
		local title = make_label(row, unit_name(record), 14, true)
		title.Position = UDim2.fromOffset(12, 8)
		title.Size = UDim2.new(1, -250, 0, 20)

		local detail = "Individual unit"
		if record.deployed_master_id then
			detail = "MASTER AT RISK — deploy or return to safety"
		elseif record.source_master_id then
			detail = "Clone / descendant of a Master"
		end

		local detail_label = make_label(row, detail, 11, false)
		detail_label.Position = UDim2.fromOffset(12, 34)
		detail_label.Size = UDim2.new(1, -250, 0, 18)
		detail_label.TextColor3 = Color3.fromRGB(171, 158, 185)

		if record.deployed_master_id then
			local shelve = make_button(row, "Shelve", 92)
			shelve.Position = UDim2.new(1, -104, 0, 21)
			shelve.MouseButton1Click:Connect(function()
				send_action("SHELVE_MASTER", {
					recordId = record.record_id,
				})
			end)
		else
			local imprint = make_button(row, "Imprint", 92)
			imprint.Position = UDim2.new(1, -104, 0, 21)
			imprint.MouseButton1Click:Connect(function()
				send_action("IMPRINT_MASTER", {
					recordId = record.record_id,
				})
			end)
		end
	end
end

local function render_master_machine_buttons(
	row: Frame,
	record: UnitRecord,
	machines: { MachineSnapshot }
)
	local x_offset = 204
	for index, machine in ipairs(machines) do
		local label = ("M%d"):format(index)
		local button = make_button(row, label, 44)
		button.Position = UDim2.new(1, -x_offset, 0, 42)
		x_offset -= 50
		button.MouseButton1Click:Connect(function()
			send_action("ASSIGN_MACHINE", {
				machineId = machine.machineId,
				masterId = record.record_id,
			})
		end)
	end
end

local function render_masters(snapshot: SoulSnapshot)
	if #snapshot.masters == 0 then
		make_empty_row(
			"No Masters yet. Imprint an extracted unit from the Vault."
		)
		return
	end

	for _, record in ipairs(snapshot.masters) do
		local row = make_row(88)
		local title = make_label(
			row,
			"MASTER: " .. unit_name(record),
			14,
			true
		)
		title.Position = UDim2.fromOffset(12, 8)
		title.Size = UDim2.new(1, -220, 0, 20)

		local abilities = #(record.ability_ids or {})
		local detail = (
			"Trait: %s | Size: %s | Evolution: %s | Abilities: %d"
		):format(
			record.trait or "None",
			record.size_tier or "Normal",
			record.evolution_id or "None",
			abilities
		)
		local detail_label = make_label(row, detail, 11, false)
		detail_label.Position = UDim2.fromOffset(12, 30)
		detail_label.Size = UDim2.new(1, -220, 0, 18)
		detail_label.TextColor3 = Color3.fromRGB(171, 158, 185)

		local risk = make_button(row, "Risk Master", 110)
		risk.Position = UDim2.new(1, -122, 0, 14)
		risk.MouseButton1Click:Connect(function()
			send_action("DEPLOY_MASTER", {
				masterId = record.record_id,
			})
		end)

		render_master_machine_buttons(
			row,
			record,
			snapshot.machines
		)
	end
end

local function machine_status(machine: MachineSnapshot): string
	if not machine.master then
		return "Idle — assign a Master"
	end
	if machine.paused then
		if machine.outputCount >= machine.capacity then
			return "Paused — output storage full"
		end
		return "Paused — needs Soul Essence or assignment"
	end
	if machine.secondsRemaining then
		return ("Cloning — ~%ds remaining"):format(
			math.ceil(machine.secondsRemaining)
		)
	end
	return "Ready"
end

local function render_machine_buttons(
	row: Frame,
	machine: MachineSnapshot
)
	local collect = make_button(row, "Collect", 82)
	collect.Position = UDim2.new(1, -270, 0, 57)
	collect.MouseButton1Click:Connect(function()
		send_action("COLLECT_OUTPUT", {
			machineId = machine.machineId,
		})
	end)

	local unassign = make_button(row, "Unassign", 82)
	unassign.Position = UDim2.new(1, -180, 0, 57)
	unassign.MouseButton1Click:Connect(function()
		send_action("UNASSIGN_MACHINE", {
			machineId = machine.machineId,
		})
	end)

	local forge_note = make_label(
		row,
		"Upgrade at your Foundry Upgrade Forge",
		10,
		false
	)
	forge_note.Position = UDim2.new(1, -260, 0, 82)
	forge_note.Size = UDim2.fromOffset(248, 16)
	forge_note.TextColor3 = Color3.fromRGB(142, 130, 153)
end

local function render_machines(snapshot: SoulSnapshot)
	for index, machine in ipairs(snapshot.machines) do
		local row = make_row(100)
		local title = make_label(
			row,
			("Machine %d — Level %d"):format(
				index,
				machine.level
			),
			14,
			true
		)
		title.Position = UDim2.fromOffset(12, 8)
		title.Size = UDim2.new(1, -24, 0, 20)

		local master_name = if machine.master
			then unit_name(machine.master)
			else "None"
		local line = make_label(
			row,
			("Master: %s | Output: %d/%d"):format(
				master_name,
				machine.outputCount,
				machine.capacity
			),
			11,
			false
		)
		line.Position = UDim2.fromOffset(12, 30)
		line.Size = UDim2.new(1, -24, 0, 18)

		local status_line = make_label(
			row,
			machine_status(machine),
			11,
			false
		)
		status_line.Position = UDim2.fromOffset(12, 49)
		status_line.Size = UDim2.new(1, -290, 0, 18)
		status_line.TextColor3 = Color3.fromRGB(171, 158, 185)

		render_machine_buttons(row, machine)
	end
end

local function render_snapshot(snapshot: SoulSnapshot)
	latest_snapshot = snapshot
	summary.Text = (
		"Soul Essence: %d   |   Foundry Lv %d   |   Machines: %d"
	):format(
		snapshot.soulEssence,
		snapshot.baseLevel,
		#snapshot.machines
	)

	if snapshot.persistent then
		status.Text = "Cloud persistence active."
	else
		status.Text = "Studio session fallback; cloud save unavailable."
	end

	base_upgrade.Text = if snapshot.baseUpgradeCost
		then ("Upgrade Foundry — %d"):format(
			snapshot.baseUpgradeCost
		)
		else "Foundry Max Level"

	clear_content()
	if active_tab == "Vault" then
		render_vault(snapshot)
	elseif active_tab == "Masters" then
		render_masters(snapshot)
	else
		render_machines(snapshot)
	end
end

local function set_tab(tab_name: string)
	if tab_name ~= "Vault"
		and tab_name ~= "Masters"
		and tab_name ~= "Machines"
	then
		return
	end

	active_tab = tab_name

	local title = panel:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		if tab_name == "Masters" then
			title.Text = "Master Archive"
		elseif tab_name == "Machines" then
			title.Text = "Soul Foundry"
		else
			title.Text = "Soul Vault"
		end
	end

	if latest_snapshot then
		render_snapshot(latest_snapshot)
	end
end

panel:GetAttributeChangedSignal("RequestedTab"):Connect(function()
	local requested = panel:GetAttribute("RequestedTab")
	if typeof(requested) == "string" then
		set_tab(requested)
	end
end)

for _, tab_name in ipairs({ "Vault", "Masters", "Machines" }) do
	local button = tabs:FindFirstChild(
		tab_name .. "Tab"
	)
	if button and button:IsA("TextButton") then
		button.MouseButton1Click:Connect(function()
			set_tab(tab_name)
		end)
	end
end

base_upgrade.MouseButton1Click:Connect(function()
	-- Upgrade purchases live at the physical Upgrade Forge.
end)

icon.MouseButton1Click:Connect(function()
	-- The Foundry no longer exposes a permanent HUD shortcut.
end)

local function update_zone_visibility()
	local in_safe_zone =
		LOCAL_PLAYER:GetAttribute("PvPZone") == "SafeZone"
	local loaded =
		LOCAL_PLAYER:GetAttribute("SoulProfileLoaded") == true

	icon.Visible = false
	if not in_safe_zone or not loaded then
		panel.Visible = false
	end
end

LOCAL_PLAYER:GetAttributeChangedSignal("PvPZone"):Connect(
	update_zone_visibility
)
LOCAL_PLAYER:GetAttributeChangedSignal(
	"SoulProfileLoaded"
):Connect(update_zone_visibility)

LOCAL_PLAYER.CharacterAdded:Connect(function()
	task.wait(0.25)
	update_zone_visibility()
end)

Remotes.soul_collection().OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	if payload.kind == "SNAPSHOT" then
		render_snapshot(payload :: SoulSnapshot)
		update_zone_visibility()
	elseif payload.kind == "RESULT" then
		status.Text = tostring(payload.message or "")
	end
end)

task.defer(function()
	update_zone_visibility()
	send_action("REQUEST")
end)

task.spawn(function()
	while gui.Parent do
		if panel.Visible then
			send_action("REQUEST")
		end
		task.wait(2)
	end
end)
