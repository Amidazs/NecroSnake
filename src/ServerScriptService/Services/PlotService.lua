--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlotService = {}

local PLOTS_FOLDER_NAME = "Bases"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"
local MAX_PLOTS = 8

local assigned_plot_by_user_id: { [number]: Model } = {}
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
		label.Text = ("PLOT %02d\n%s"):format(
			plot_index,
			display_name
		)
	else
		label.Text = ("PLOT %02d\nUNCLAIMED"):format(
			plot_index
		)
	end
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
