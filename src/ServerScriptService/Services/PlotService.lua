--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlotUpgradeConfig = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("PlotUpgradeConfig")
)

local PlotService = {}

local PLOTS_FOLDER_NAME = "Bases"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local MAX_PLOTS = 8

local UPGRADE_ATTRIBUTES = {
	"PlotLevel",
	"SoulFoundryLevel",
	"FormationLevel",
	"SkillReliquaryLevel",
	"CodexLevel",
	"MasterGalleryLevel",
	"TrophyHallLevel",
	"UpgradeForgeLevel",
}

local assigned_plot_by_user_id: { [number]: Model } = {}
local connections_by_user_id: {
	[number]: { RBXScriptConnection },
} = {}
local did_start = false

--[[
	Finds the Sanctum plot folder.

	Args:
		None.

	Returns:
		Folder?: Plot folder when the authored Sanctum is available.
]]
local function get_plots_folder(): Folder?
	local zones = Workspace:FindFirstChild("Zones")
	local safe = zones and zones:FindFirstChild(
		SAFE_ZONE_MODEL_NAME
	)
	local plots = safe and safe:FindFirstChild(PLOTS_FOLDER_NAME)
	if plots and plots:IsA("Folder") then
		return plots
	end
	return nil
end

--[[
	Returns Sanctum plots sorted by their PlotIndex.

	Args:
		None.

	Returns:
		{ Model }: Ordered plot models.
]]
local function get_sorted_plots(): { Model }
	local folder = get_plots_folder()
	if not folder then
		return {}
	end

	local plots: { Model } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model")
			and typeof(child:GetAttribute("PlotIndex")) == "number"
		then
			table.insert(plots, child)
		end
	end

	table.sort(plots, function(left, right)
		return (left:GetAttribute("PlotIndex") :: number)
			< (right:GetAttribute("PlotIndex") :: number)
	end)
	return plots
end

--[[
	Finds the public owner label for one plot.

	Args:
		plot (Model): Plot containing the owner sign.

	Returns:
		TextLabel?: Owner label when available.
]]
local function get_owner_label(plot: Model): TextLabel?
	local sign = plot:FindFirstChild("PlotOwnerSign")
	local billboard = sign
		and sign:FindFirstChild("OwnerBillboard")
	local label = billboard
		and billboard:FindFirstChild("OwnerText")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

--[[
	Updates the replicated owner sign for a plot.

	Args:
		plot (Model): Plot whose sign should change.
		display_name (string?): Owner display name.

	Returns:
		None.
]]
local function update_owner_sign(
	plot: Model,
	display_name: string?
)
	local label = get_owner_label(plot)
	if not label then
		return
	end

	local plot_index = tonumber(
		plot:GetAttribute("PlotIndex")
	) or 0
	if display_name and display_name ~= "" then
		local plot_level = tonumber(
			plot:GetAttribute("PlotLevel")
		) or 1
		label.Text = ("PLOT %02d • LV %d\n%s"):format(
			plot_index,
			plot_level,
			display_name
		)
	else
		label.Text = ("PLOT %02d\nUNCLAIMED"):format(
			plot_index
		)
	end
end

--[[
	Creates one lightweight visual upgrade part.

	Args:
		parent (Instance): Visual folder receiving the part.
		name (string): Part name.
		size (Vector3): Part dimensions.
		cframe (CFrame): World transform.
		color (Color3): Part colour.
		material (Enum.Material): Part material.

	Returns:
		Part: Created non-colliding anchored part.
]]
local function make_upgrade_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

--[[
	Rebuilds visible progression details for one facility.

	Level two adds twin ritual pylons. Level three adds a glowing crest over
	the station canopy. These are replicated, so visitors can see another
	player's upgraded plot without being able to use it.

	Args:
		station (Model): Physical facility model.
		level (number): Facility level.

	Returns:
		None.
]]
local function apply_station_visual(
	station: Model,
	level: number
)
	local existing = station:FindFirstChild("ProgressionVisuals")
	if existing then
		existing:Destroy()
	end

	station:SetAttribute("FacilityLevel", level)

	local anchor = station:FindFirstChild("StationLabel")
	local billboard = anchor and anchor:FindFirstChild("Label")
	local label = billboard
		and billboard:FindFirstChildOfClass("TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = ("%s\nLEVEL %d"):format(
			station.Name,
			level
		)
	end

	if level <= 1 then
		return
	end

	local canopy = station:FindFirstChild("StationCanopy")
	if not (canopy and canopy:IsA("BasePart")) then
		return
	end

	local visuals = Instance.new("Folder")
	visuals.Name = "ProgressionVisuals"
	visuals.Parent = station

	local offset = canopy.Size.X * 0.34
	local pylon_color = Color3.fromRGB(139, 105, 61)
	for _, x in ipairs({ -offset, offset }) do
		make_upgrade_part(
			visuals,
			"RitualPylon",
			Vector3.new(2.5, 10, 2.5),
			canopy.CFrame * CFrame.new(x, 5, 0),
			pylon_color,
			Enum.Material.Slate
		)
	end

	if level < 3 then
		return
	end

	local crest = make_upgrade_part(
		visuals,
		"AscendantCrest",
		Vector3.new(canopy.Size.X * 0.62, 1.5, 2),
		canopy.CFrame * CFrame.new(0, 8.5, 0),
		Color3.fromRGB(171, 116, 220),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = crest.Color
	light.Brightness = 1.2
	light.Range = 20
	light.Parent = crest
end

--[[
	Rebuilds visible Plot-level progression details.

	Args:
		plot (Model): Assigned player plot.
		level (number): Plot level.

	Returns:
		None.
]]
local function apply_plot_visual(
	plot: Model,
	level: number
)
	local existing = plot:FindFirstChild("PlotProgressionVisuals")
	if existing then
		existing:Destroy()
	end
	if level <= 1 then
		return
	end

	local floor = plot:FindFirstChild("Plot")
	if not (floor and floor:IsA("BasePart")) then
		return
	end

	local visuals = Instance.new("Folder")
	visuals.Name = "PlotProgressionVisuals"
	visuals.Parent = plot

	local front_z = -(floor.Size.Z * 0.5 - 14)
	local side_x = floor.Size.X * 0.5 - 22
	local height = if level >= 3 then 22 else 15
	for _, x in ipairs({ -side_x, side_x }) do
		make_upgrade_part(
			visuals,
			"PlotStandard",
			Vector3.new(3, height, 3),
			floor.CFrame * CFrame.new(
				x,
				floor.Size.Y * 0.5 + height * 0.5,
				front_z
			),
			Color3.fromRGB(96, 72, 49),
			Enum.Material.Wood
		)
	end

	if level >= 3 then
		make_upgrade_part(
			visuals,
			"PlotCrest",
			Vector3.new(30, 2, 3),
			floor.CFrame * CFrame.new(
				0,
				floor.Size.Y * 0.5 + 20,
				front_z
			),
			Color3.fromRGB(171, 116, 220),
			Enum.Material.Neon
		)
	end
end

--[[
	Applies one player's persisted progression to their assigned plot.

	Args:
		player (Player): Plot owner.
		plot (Model): Assigned plot.

	Returns:
		None.
]]
local function apply_player_progression(
	player: Player,
	plot: Model
)
	for _, attribute_name in ipairs(UPGRADE_ATTRIBUTES) do
		local value = player:GetAttribute(attribute_name)
		local level = if typeof(value) == "number"
			then math.clamp(math.floor(value), 1, 3)
			else 1
		plot:SetAttribute(attribute_name, level)
	end

	apply_plot_visual(
		plot,
		plot:GetAttribute("PlotLevel") :: number
	)

	local facilities = plot:FindFirstChild("Phase10Facilities")
	if facilities then
		for _, child in ipairs(facilities:GetChildren()) do
			if not child:IsA("Model") then
				continue
			end
			local upgrade_key =
				child:GetAttribute("PlotUpgradeKey")
			if typeof(upgrade_key) ~= "string" then
				continue
			end
			local level = plot:GetAttribute(upgrade_key)
			if typeof(level) ~= "number" then
				level = 1
			end
			apply_station_visual(child, level)
		end
	end

	local foundry_level = plot:GetAttribute("SoulFoundryLevel")
	if typeof(foundry_level) ~= "number" then
		foundry_level = 1
	end

	local trophy_level = plot:GetAttribute("TrophyHallLevel")
	if typeof(trophy_level) ~= "number" then
		trophy_level = 1
	end
	local trophy_slots =
		PlotUpgradeConfig.get_trophy_slots(trophy_level)

	if facilities then
		for _, instance in ipairs(facilities:GetDescendants()) do
			if not instance:IsA("BasePart") then
				continue
			end

			local machine_index =
				instance:GetAttribute("MachineIndex")
			if typeof(machine_index) == "number" then
				local unlocked = machine_index <= foundry_level
				instance.Transparency = if unlocked
					then 0.38
					else 0.86
				instance.CanCollide = unlocked
			end

			local trophy_index =
				instance:GetAttribute("BossTrophySlot")
			if typeof(trophy_index) == "number" then
				local unlocked = trophy_index <= trophy_slots
				instance.Transparency = if unlocked
					then 0
					else 0.72
				instance.CanCollide = unlocked
			end
		end
	end

	update_owner_sign(plot, player.DisplayName)
end

--[[
	Disconnects progression listeners for one user.

	Args:
		user_id (number): User ID whose listeners should be removed.

	Returns:
		None.
]]
local function disconnect_player_connections(user_id: number)
	local connections = connections_by_user_id[user_id]
	if not connections then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections_by_user_id[user_id] = nil
end

--[[
	Connects plot progression attributes for one assigned player.

	Args:
		player (Player): Assigned player.
		plot (Model): Assigned plot.

	Returns:
		None.
]]
local function connect_player_progression(
	player: Player,
	plot: Model
)
	disconnect_player_connections(player.UserId)

	local connections: { RBXScriptConnection } = {}
	for _, attribute_name in ipairs(UPGRADE_ATTRIBUTES) do
		table.insert(
			connections,
			player:GetAttributeChangedSignal(
				attribute_name
			):Connect(function()
				if player.Parent and plot.Parent then
					apply_player_progression(player, plot)
				end
			end)
		)
	end
	connections_by_user_id[player.UserId] = connections
	apply_player_progression(player, plot)
end

--[[
	Clears one plot back to its unassigned server state.

	Args:
		plot (Model): Plot to release.

	Returns:
		None.
]]
local function clear_plot(plot: Model)
	local user_id = plot:GetAttribute("PlotOwnerUserId")
	if typeof(user_id) == "number" and user_id ~= 0 then
		assigned_plot_by_user_id[user_id] = nil
	end

	plot:SetAttribute("PlotOwnerUserId", 0)
	plot:SetAttribute("PlotOwnerName", "")
	plot:SetAttribute("PlotOwnerDisplayName", "")
	plot:SetAttribute("PlotOccupied", false)

	for _, attribute_name in ipairs(UPGRADE_ATTRIBUTES) do
		plot:SetAttribute(attribute_name, 1)
	end
	apply_plot_visual(plot, 1)

	local facilities = plot:FindFirstChild("Phase10Facilities")
	if facilities then
		for _, child in ipairs(facilities:GetChildren()) do
			if child:IsA("Model") then
				apply_station_visual(child, 1)
			end
		end

		for _, instance in ipairs(facilities:GetDescendants()) do
			if not instance:IsA("BasePart") then
				continue
			end

			local machine_index =
				instance:GetAttribute("MachineIndex")
			if typeof(machine_index) == "number" then
				local unlocked = machine_index <= 1
				instance.Transparency = if unlocked
					then 0.38
					else 0.86
				instance.CanCollide = unlocked
			end

			local trophy_index =
				instance:GetAttribute("BossTrophySlot")
			if typeof(trophy_index) == "number" then
				local unlocked = trophy_index <= 4
				instance.Transparency = if unlocked
					then 0
					else 0.72
				instance.CanCollide = unlocked
			end
		end
	end

	update_owner_sign(plot, nil)
end

--[[
	Claims the first free plot for a user ID.

	Args:
		user_id (number): User ID receiving a plot.
		username (string): Account username.
		display_name (string): Public display name.

	Returns:
		Model?: Assigned plot, or nil when all eight are occupied.
]]
local function claim_plot(
	user_id: number,
	username: string,
	display_name: string
): Model?
	local existing = assigned_plot_by_user_id[user_id]
	if existing and existing.Parent then
		return existing
	end

	for _, plot in ipairs(get_sorted_plots()) do
		local owner = plot:GetAttribute("PlotOwnerUserId")
		if owner == user_id then
			assigned_plot_by_user_id[user_id] = plot
			update_owner_sign(plot, display_name)
			return plot
		end
	end

	for _, plot in ipairs(get_sorted_plots()) do
		local owner = plot:GetAttribute("PlotOwnerUserId")
		if owner == nil or owner == 0 then
			plot:SetAttribute("PlotOwnerUserId", user_id)
			plot:SetAttribute("PlotOwnerName", username)
			plot:SetAttribute(
				"PlotOwnerDisplayName",
				display_name
			)
			plot:SetAttribute("PlotOccupied", true)
			assigned_plot_by_user_id[user_id] = plot
			update_owner_sign(plot, display_name)
			return plot
		end
	end

	return nil
end

--[[
	Applies plot assignment attributes to one player.

	Args:
		player (Player): Player receiving a plot.

	Returns:
		Model?: Assigned plot.
]]
local function assign_player(player: Player): Model?
	local plot = claim_plot(
		player.UserId,
		player.Name,
		player.DisplayName
	)
	if not plot then
		player:SetAttribute("SanctumPlotIndex", 0)
		player:SetAttribute("SanctumPlotName", "")
		warn(
			("[PlotService] No free plot for %s.")
				:format(player.Name)
		)
		return nil
	end

	local plot_index = tonumber(
		plot:GetAttribute("PlotIndex")
	) or 0
	player:SetAttribute("SanctumPlotIndex", plot_index)
	player:SetAttribute("SanctumPlotName", plot.Name)
	connect_player_progression(player, plot)
	return plot
end

--[[
	Releases the leaving player's plot.

	Args:
		player (Player): Player leaving the server.

	Returns:
		None.
]]
local function release_player(player: Player)
	disconnect_player_connections(player.UserId)

	local plot = assigned_plot_by_user_id[player.UserId]
	if plot then
		clear_plot(plot)
	end
	assigned_plot_by_user_id[player.UserId] = nil
end

--[[
	Resets stale saved ownership before live assignments begin.

	Args:
		None.

	Returns:
		None.
]]
local function reset_plot_ownership()
	assigned_plot_by_user_id = {}
	for _, plot in ipairs(get_sorted_plots()) do
		clear_plot(plot)
	end
end

--[[
	Starts automatic eight-player Sanctum plot assignment.

	Args:
		None.

	Returns:
		None.
]]
function PlotService.start()
	if did_start then
		return
	end
	did_start = true

	local plots = get_sorted_plots()
	if #plots ~= MAX_PLOTS then
		warn(
			("[PlotService] Expected %d plots, found %d.")
				:format(MAX_PLOTS, #plots)
		)
	end

	reset_plot_ownership()

	Players.PlayerAdded:Connect(assign_player)
	Players.PlayerRemoving:Connect(release_player)

	for _, player in ipairs(Players:GetPlayers()) do
		assign_player(player)
	end

	print(
		("[PlotService] Ready with %d Sanctum plots.")
			:format(#plots)
	)
end

--[[
	Returns the plot assigned to a player.

	Args:
		player (Player): Player whose plot is requested.

	Returns:
		Model?: Assigned plot.
]]
function PlotService.get_plot(player: Player): Model?
	local plot = assigned_plot_by_user_id[player.UserId]
	if plot and plot.Parent then
		return plot
	end

	return assign_player(player)
end

--[[
	Returns a safe arrival transform inside a player's plot.

	Args:
		player (Player): Player returning to the Sanctum.

	Returns:
		CFrame?: Plot spawn transform.
]]
function PlotService.get_spawn_cframe(
	player: Player
): CFrame?
	local plot = PlotService.get_plot(player)
	if not plot then
		return nil
	end

	local spawn = plot:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame * CFrame.new(0, 4, 0)
	end
	return nil
end

--[[
	Returns whether an instance belongs to the player's plot.

	Args:
		player (Player): Player being checked.
		instance (Instance): Plot descendant to inspect.

	Returns:
		boolean: True when the instance belongs to the assigned plot.
]]
function PlotService.owns_instance(
	player: Player,
	instance: Instance
): boolean
	local plot = PlotService.get_plot(player)
	if not plot then
		return false
	end
	return instance:IsDescendantOf(plot)
end

--[[
	Returns the number of authored plots.

	Args:
		None.

	Returns:
		number: Plot count.
]]
function PlotService.get_plot_count(): number
	return #get_sorted_plots()
end

--[[
	Claims a synthetic plot during Studio acceptance tests.

	Args:
		user_id (number): Synthetic user ID.
		display_name (string): Synthetic display name.

	Returns:
		number?: Assigned plot index.
]]
function PlotService.debug_claim_plot(
	user_id: number,
	display_name: string
): number?
	if not RunService:IsStudio() then
		return nil
	end

	local plot = claim_plot(
		user_id,
		display_name,
		display_name
	)
	if not plot then
		return nil
	end
	return tonumber(plot:GetAttribute("PlotIndex"))
end

--[[
	Releases a synthetic Studio plot assignment.

	Args:
		user_id (number): Synthetic user ID.

	Returns:
		boolean: True when Studio testing is active.
]]
function PlotService.debug_release_plot(
	user_id: number
): boolean
	if not RunService:IsStudio() then
		return false
	end

	local plot = assigned_plot_by_user_id[user_id]
	if plot then
		clear_plot(plot)
	end
	assigned_plot_by_user_id[user_id] = nil
	return true
end

return PlotService
