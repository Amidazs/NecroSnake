--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WorldEventService = {}

local EVENT_ID = "Soulstorm"
local EVENT_NAME = "Soulstorm"
local EVENT_FOLDER_NAME = "WorldEvents"
local EVOLUTION_ID = "Stormcharged"

local INITIAL_DELAY_SECONDS = 120
local WARNING_SECONDS = 15
local ACTIVE_SECONDS = 75
local EVENT_COOLDOWN_SECONDS = 240
local EVENT_TICK_SECONDS = 0.25

local EVENT_RADIUS = 32
local EVENT_HEIGHT_LIMIT = 38
local EXPOSURE_REQUIRED_SECONDS = 10
local LIGHTNING_INTERVAL_SECONDS = 1.5
local LIGHTNING_DAMAGE_RATIO = 0.16
local LIGHTNING_MIN_DAMAGE = 10
local WARNING_COLOR = Color3.fromRGB(125, 95, 170)
local ACTIVE_COLOR = Color3.fromRGB(80, 190, 255)
local LIGHTNING_COLOR = Color3.fromRGB(185, 235, 255)

type EventOptions = {
	warning_seconds: number?,
	active_seconds: number?,
	exposure_seconds: number?,
	damage_ratio: number?,
	radius: number?,
}

type ActiveEvent = {
	token: number,
	state: string,
	center: Vector3,
	radius: number,
	ends_at: number,
	exposure_required: number,
	damage_ratio: number,
	model: Model,
	zone: BasePart,
	label: TextLabel,
	sparkles: Sparkles,
}

local army_service = nil :: any
local evolution_service = nil :: any
local did_start = false
local event_token = 0
local current_event: ActiveEvent? = nil
local exposure_by_model: { [Model]: number } = {}
local random = Random.new()

local function server_now(): number
	return Workspace:GetServerTimeNow()
end
local function get_events_folder(): Folder
	local existing = Workspace:FindFirstChild(EVENT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = EVENT_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function get_arena_region(): BasePart?
	local zones = Workspace:FindFirstChild("Zones")
	local arena = zones and zones:FindFirstChild("ArenaWorld")
	if not arena then
		return nil
	end

	local event_region = arena:FindFirstChild("StormEventRegion")
	if event_region and event_region:IsA("BasePart") then
		return event_region
	end

	local spawn_region = arena:FindFirstChild("ArenaSpawnRegion")
	if spawn_region and spawn_region:IsA("BasePart") then
		return spawn_region
	end
	return nil
end

local function project_to_ground(
	position: Vector3,
	excluded: Instance?
): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if excluded then
		params.FilterDescendantsInstances = { excluded }
	end
	local origin = position + Vector3.new(0, 500, 0)
	local result = Workspace:Raycast(
		origin,
		Vector3.new(0, -1200, 0),
		params
	)
	if result then
		return result.Position + Vector3.new(0, 0.3, 0)
	end
	return position
end

local function choose_event_center(): Vector3?
	local region = get_arena_region()
	if not region then
		return nil
	end

	local half_x = math.max(
		0,
		(region.Size.X * 0.5) - EVENT_RADIUS - 8
	)
	local half_z = math.max(
		0,
		(region.Size.Z * 0.5) - EVENT_RADIUS - 8
	)
	local local_point = Vector3.new(
		random:NextNumber(-half_x, half_x),
		0,
		random:NextNumber(-half_z, half_z)
	)
	local world_point = region.CFrame:PointToWorldSpace(local_point)
	return project_to_ground(world_point, region)
end
local function make_event_model(
	center: Vector3,
	radius: number
): (Model, BasePart, TextLabel, Sparkles)
	local model = Instance.new("Model")
	model.Name = EVENT_ID
	model.Parent = get_events_folder()

	local anchor = Instance.new("Part")
	anchor.Name = "StormAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = center + Vector3.new(0, 8, 0)
	anchor.Parent = model

	local zone = Instance.new("Part")
	zone.Name = "StormZone"
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Material = Enum.Material.Neon
	zone.Color = WARNING_COLOR
	zone.Transparency = 0.78
	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.35, radius * 2, radius * 2)
	zone.CFrame = CFrame.new(center)
		* CFrame.Angles(0, 0, math.pi / 2)
	zone.Parent = model
	local light = Instance.new("PointLight")
	light.Name = "StormLight"
	light.Color = WARNING_COLOR
	light.Brightness = 2
	light.Range = radius * 1.5
	light.Parent = anchor

	local sparkles = Instance.new("Sparkles")
	sparkles.Name = "StormSparks"
	sparkles.SparkleColor = WARNING_COLOR
	sparkles.Enabled = true
	sparkles.Parent = anchor

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StormBillboard"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(330, 70)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "EventLabel"
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(18, 14, 28)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = "SOULSTORM FORMING\nKeep valuable undead clear."
	label.Parent = billboard

	return model, zone, label, sparkles
end
local function set_visual_state(event: ActiveEvent)
	local active = event.state == "ACTIVE"
	event.zone.Color = if active then ACTIVE_COLOR else WARNING_COLOR
	event.zone.Transparency = if active then 0.55 else 0.78
	event.sparkles.SparkleColor = if active
		then ACTIVE_COLOR
		else WARNING_COLOR

	local anchor = event.model:FindFirstChild("StormAnchor")
	local light = anchor and anchor:FindFirstChild("StormLight")
	if light and light:IsA("PointLight") then
		light.Color = if active then ACTIVE_COLOR else WARNING_COLOR
		light.Brightness = if active then 4 else 2
	end

	if active then
		event.label.Text =
			"SOULSTORM ACTIVE\nRemain inside to become Stormcharged."
	else
		event.label.Text =
			"SOULSTORM FORMING\nA dangerous evolution zone is opening."
	end
end

local function state_payload(event: ActiveEvent): { [string]: any }
	return {
		kind = "STATE",
		eventId = EVENT_ID,
		eventName = EVENT_NAME,
		state = event.state,
		center = event.center,
		radius = event.radius,
		endsAt = event.ends_at,
		serverNow = server_now(),
	}
end
local function broadcast_state(event: ActiveEvent)
	Remotes.world_event():FireAllClients(state_payload(event))
end

local function notify_player(
	player: Player,
	kind: string,
	message: string,
	model: Model?
)
	Remotes.world_event():FireClient(player, {
		kind = kind,
		eventId = EVENT_ID,
		message = message,
		unitName = if model then model.Name else nil,
	})
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function is_inside_event(
	model: Model,
	event: ActiveEvent
): boolean
	local root = get_root(model)
	if not root then
		return false
	end

	local delta = root.Position - event.center
	if math.abs(delta.Y) > EVENT_HEIGHT_LIMIT then
		return false
	end
	local flat = Vector3.new(delta.X, 0, delta.Z)
	return flat.Magnitude <= event.radius
end
local function destroy_exposure_ui(model: Model)
	local root = get_root(model)
	if not root then
		return
	end
	local gui = root:FindFirstChild("StormExposureGui")
	if gui then
		gui:Destroy()
	end
end

local function update_exposure_ui(
	model: Model,
	ratio: number
)
	local root = get_root(model)
	if not root then
		return
	end

	local gui = root:FindFirstChild("StormExposureGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "StormExposureGui"
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(150, 32)
		gui.StudsOffset = Vector3.new(0, 4.8, 0)
		gui.Parent = root

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundColor3 = Color3.fromRGB(15, 24, 34)
		label.BackgroundTransparency = 0.2
		label.BorderSizePixel = 0
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = ACTIVE_COLOR
		label.TextScaled = true
		label.Parent = gui
	end
	local label = gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = ("Storm attunement %d%%"):format(
			math.floor(math.clamp(ratio, 0, 1) * 100)
		)
	end
end

local function clear_exposure(model: Model)
	exposure_by_model[model] = nil
	model:SetAttribute("StormExposure", nil)
	destroy_exposure_ui(model)
end

local function transform_unit(
	player: Player,
	model: Model
)
	local ok, result = evolution_service.transform_model(
		model,
		EVOLUTION_ID
	)
	clear_exposure(model)
	if not ok then
		return
	end

	model:SetAttribute("EvolutionEventId", EVENT_ID)
	notify_player(
		player,
		"UNIT_EVOLVED",
		("%s survived the Soulstorm and became %s."):format(
			model.Name,
			result
		),
		model
	)
end
local function update_exposure(
	event: ActiveEvent,
	delta_seconds: number
)
	local seen: { [Model]: boolean } = {}

	for _, player in ipairs(Players:GetPlayers()) do
		for _, model in ipairs(army_service.get_army_units(player)) do
			if model.Parent ~= nil and is_inside_event(model, event) then
				seen[model] = true
				local eligible = evolution_service.can_transform(
					model,
					EVOLUTION_ID
				)
				if eligible then
					local exposure = (exposure_by_model[model] or 0)
						+ delta_seconds
					exposure_by_model[model] = exposure
					local ratio = exposure / event.exposure_required
					model:SetAttribute(
						"StormExposure",
						math.clamp(ratio, 0, 1)
					)
					update_exposure_ui(model, ratio)
					if exposure >= event.exposure_required then
						transform_unit(player, model)
					end
				else
					clear_exposure(model)
				end
			end
		end
	end

	local to_clear: { Model } = {}
	for model, _ in pairs(exposure_by_model) do
		if not seen[model] or model.Parent == nil then
			table.insert(to_clear, model)
		end
	end
	for _, model in ipairs(to_clear) do
		clear_exposure(model)
	end
end
local function make_bolt_segment(
	from_position: Vector3,
	to_position: Vector3
)
	local delta = to_position - from_position
	if delta.Magnitude <= 0.05 then
		return
	end

	local part = Instance.new("Part")
	part.Name = "SoulstormLightning"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = LIGHTNING_COLOR
	part.Transparency = 0.08
	part.Size = Vector3.new(0.22, 0.22, delta.Magnitude)
	part.CFrame = CFrame.lookAt(
		(from_position + to_position) * 0.5,
		to_position
	)
	part.Parent = get_events_folder()
	Debris:AddItem(part, 0.18)
end

local function show_lightning(position: Vector3)
	local top = position + Vector3.new(
		random:NextNumber(-3, 3),
		34,
		random:NextNumber(-3, 3)
	)
	local middle = position + Vector3.new(
		random:NextNumber(-4, 4),
		17,
		random:NextNumber(-4, 4)
	)
	make_bolt_segment(top, middle)
	make_bolt_segment(middle, position)
end
local function get_units_inside(
	event: ActiveEvent
): { { player: Player, model: Model } }
	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		for _, model in ipairs(army_service.get_army_units(player)) do
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid
				and humanoid.Health > 0
				and is_inside_event(model, event)
			then
				table.insert(candidates, {
					player = player,
					model = model,
				})
			end
		end
	end
	return candidates
end

local function strike_random_unit(event: ActiveEvent)
	local candidates = get_units_inside(event)
	if #candidates == 0 then
		return
	end

	local target = candidates[random:NextInteger(1, #candidates)]
	local model = target.model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = get_root(model)
	if not (humanoid and root) then
		return
	end

	show_lightning(root.Position)
	model:SetAttribute("LastDamageSourceKind", "WORLD_EVENT")
	model:SetAttribute("LastHitOwnerUserId", 0)
	model:SetAttribute("EventLossReason", EVENT_ID)

	local damage = math.max(
		LIGHTNING_MIN_DAMAGE,
		humanoid.MaxHealth * event.damage_ratio
	)
	humanoid:TakeDamage(damage)
	if humanoid.Health <= 0 then
		notify_player(
			target.player,
			"UNIT_LOST",
			("%s was destroyed by the Soulstorm."):format(model.Name),
			model
		)
	end
end

local function clear_all_exposure()
	local models = {}
	for model, _ in pairs(exposure_by_model) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		if model.Parent ~= nil then
			clear_exposure(model)
		else
			exposure_by_model[model] = nil
		end
	end
end

local function cancel_current_event()
	event_token += 1
	clear_all_exposure()
	if current_event and current_event.model.Parent then
		current_event.model:Destroy()
	end
	current_event = nil
	Remotes.world_event():FireAllClients({
		kind = "STATE",
		eventId = EVENT_ID,
		eventName = EVENT_NAME,
		state = "INACTIVE",
		serverNow = server_now(),
	})
end

local function finish_event(event: ActiveEvent)
	if current_event ~= event then
		return
	end
	clear_all_exposure()
	event.state = "ENDED"
	event.ends_at = server_now()
	broadcast_state(event)
	if event.model.Parent then
		event.model:Destroy()
	end
	current_event = nil
end
local function run_active_loop(event: ActiveEvent)
	local next_strike = server_now() + LIGHTNING_INTERVAL_SECONDS
	local previous = server_now()

	while current_event == event
		and server_now() < event.ends_at
	do
		local now = server_now()
		local delta_seconds = math.max(0, now - previous)
		previous = now
		update_exposure(event, delta_seconds)

		if now >= next_strike then
			strike_random_unit(event)
			next_strike = now + LIGHTNING_INTERVAL_SECONDS
		end
		task.wait(EVENT_TICK_SECONDS)
	end

	finish_event(event)
end

local function begin_event(
	center: Vector3,
	options: EventOptions?
): boolean
	if current_event then
		return false
	end

	event_token += 1
	local token = event_token
	local warning_seconds = options
		and options.warning_seconds
		or WARNING_SECONDS
	local active_seconds = options
		and options.active_seconds
		or ACTIVE_SECONDS
	local exposure_seconds = options
		and options.exposure_seconds
		or EXPOSURE_REQUIRED_SECONDS
	local damage_ratio = options
		and options.damage_ratio
		or LIGHTNING_DAMAGE_RATIO
	local radius = options and options.radius or EVENT_RADIUS

	local model, zone, label, sparkles = make_event_model(
		center,
		radius
	)
	local event: ActiveEvent = {
		token = token,
		state = "WARNING",
		center = center,
		radius = radius,
		ends_at = server_now() + warning_seconds,
		exposure_required = exposure_seconds,
		damage_ratio = damage_ratio,
		model = model,
		zone = zone,
		label = label,
		sparkles = sparkles,
	}
	current_event = event
	set_visual_state(event)
	broadcast_state(event)

	task.spawn(function()
		if warning_seconds > 0 then
			task.wait(warning_seconds)
		end
		if current_event ~= event or event.token ~= event_token then
			return
		end

		event.state = "ACTIVE"
		event.ends_at = server_now() + active_seconds
		set_visual_state(event)
		broadcast_state(event)
		run_active_loop(event)
	end)
	return true
end
local function start_normal_event()
	local center = choose_event_center()
	if not center then
		warn("[WorldEventService] Arena event region not found.")
		return
	end
	begin_event(center, nil)
end

local function send_current_state(player: Player)
	local event = current_event
	if not event then
		Remotes.world_event():FireClient(player, {
			kind = "STATE",
			eventId = EVENT_ID,
			eventName = EVENT_NAME,
			state = "INACTIVE",
			serverNow = server_now(),
		})
		return
	end
	Remotes.world_event():FireClient(player, state_payload(event))
end

function WorldEventService.init(
	army_service_ref: any,
	evolution_service_ref: any
)
	army_service = army_service_ref
	evolution_service = evolution_service_ref
end

function WorldEventService.start()
	if did_start then
		return
	end
	did_start = true

	Players.PlayerAdded:Connect(function(player)
		task.defer(send_current_state, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(send_current_state, player)
	end
	task.spawn(function()
		task.wait(INITIAL_DELAY_SECONDS)
		while did_start do
			if not current_event then
				start_normal_event()
			end
			task.wait(EVENT_COOLDOWN_SECONDS)
		end
	end)

	print("[WorldEventService] Ready.")
end

function WorldEventService.get_current_state(): any?
	local event = current_event
	if not event then
		return nil
	end
	return state_payload(event)
end

function WorldEventService.debug_start_event(
	center: Vector3,
	options: EventOptions?
): boolean
	if not RunService:IsStudio() then
		return false
	end
	cancel_current_event()

	local resolved: EventOptions = options or {}
	if resolved.warning_seconds == nil then
		resolved.warning_seconds = 0
	end
	return begin_event(center, resolved)
end

function WorldEventService.debug_stop_event(): boolean
	if not RunService:IsStudio() then
		return false
	end
	cancel_current_event()
	return true
end

return WorldEventService
