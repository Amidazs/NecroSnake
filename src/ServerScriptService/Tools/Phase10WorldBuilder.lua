--!strict

local Workspace = game:GetService("Workspace")

local Phase10WorldBuilder = {}

local ARENA_CENTER = Vector3.new(1000, 0, 1000)
local SAFE_CENTER = Vector3.new(3600, 0, 3600)
local AUTHORED_NAME = "Phase10Authored"
local FACILITIES_NAME = "Phase10Facilities"

local COLORS = {
	neutral = Color3.fromRGB(92, 86, 78),
	ossuary = Color3.fromRGB(166, 151, 116),
	mire = Color3.fromRGB(73, 105, 67),
	ashen = Color3.fromRGB(71, 61, 58),
	grave = Color3.fromRGB(72, 65, 83),
	soul = Color3.fromRGB(129, 81, 173),
	gold = Color3.fromRGB(188, 145, 72),
}

export type RegionSpec = {
	id: string,
	display_name: string,
	center: Vector3,
	top_y: number,
	color: Color3,
	material: Enum.Material,
}
local REGION_SPECS: { RegionSpec } = {
	{
		id = "OssuaryLegion",
		display_name = "OSSUARY LEGION",
		center = Vector3.new(520, 0, 520),
		top_y = 12,
		color = COLORS.ossuary,
		material = Enum.Material.Sandstone,
	},
	{
		id = "Mirebound",
		display_name = "MIREBOUND BROOD",
		center = Vector3.new(520, 0, 1480),
		top_y = 5,
		color = COLORS.mire,
		material = Enum.Material.Ground,
	},
	{
		id = "AshenCovenant",
		display_name = "ASHEN COVENANT",
		center = Vector3.new(1480, 0, 520),
		top_y = 22,
		color = COLORS.ashen,
		material = Enum.Material.Basalt,
	},
	{
		id = "GraveCourt",
		display_name = "GRAVE COURT",
		center = Vector3.new(1480, 0, 1480),
		top_y = 14,
		color = COLORS.grave,
		material = Enum.Material.Slate,
	},
}
--[[
	Creates a folder if it does not already exist.

	Args:
		parent (Instance): Parent for the folder.
		name (string): Folder name.

	Returns:
		Folder: Existing or newly created folder.
]]
local function get_or_create_folder(
	parent: Instance,
	name: string
): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--[[
	Removes an existing child so the builder is deterministic.

	Args:
		parent (Instance): Parent containing the child.
		name (string): Child name to remove.

	Returns:
		None.
]]
local function destroy_named_child(parent: Instance, name: string)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end
--[[
	Creates an anchored world part with explicit collision settings.

	Args:
		parent (Instance): Parent container.
		name (string): Part name.
		size (Vector3): Part size.
		cframe (CFrame): World transform.
		color (Color3): Part colour.
		material (Enum.Material): Surface material.
		can_collide (boolean): Whether the part blocks movement.
		transparency (number?): Optional transparency.

	Returns:
		Part: Created part.
]]
local function make_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	can_collide: boolean,
	transparency: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = can_collide
	part.CanQuery = true
	part.CanTouch = can_collide
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Parent = parent
	return part
end
--[[
	Creates a circular horizontal arena part.

	Args:
		parent (Instance): Parent container.
		name (string): Arena name.
		center (Vector3): Centre point at the arena surface.
		diameter (number): Arena diameter.
		color (Color3): Surface colour.
		material (Enum.Material): Surface material.

	Returns:
		Part: Created circular part.
]]
local function make_disc(
	parent: Instance,
	name: string,
	center: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Part
	local disc = make_part(
		parent,
		name,
		Vector3.new(2, diameter, diameter),
		CFrame.new(center - Vector3.new(0, 1, 0))
			* CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		true
	)
	disc.Shape = Enum.PartType.Cylinder
	return disc
end

--[[
	Creates a readable world-space location label.

	Args:
		parent (Instance): Parent container.
		name (string): Anchor name.
		position (Vector3): Label position.
		text (string): Display text.
		color (Color3): Accent colour.

	Returns:
		BasePart: Invisible label anchor.
]]
local function make_world_label(
	parent: Instance,
	name: string,
	position: Vector3,
	text: string,
	color: Color3
): BasePart
	local anchor = make_part(
		parent,
		name,
		Vector3.new(1, 1, 1),
		CFrame.new(position),
		color,
		Enum.Material.SmoothPlastic,
		false,
		1
	)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(330, 70)
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(18, 17, 20)
	label.BackgroundTransparency = 0.18
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
	return anchor
end
--[[
	Creates a traversable route between two world positions.

	Args:
		parent (Instance): Parent container.
		name (string): Route name.
		start_pos (Vector3): Route start.
		end_pos (Vector3): Route end.
		width (number): Route width.
		color (Color3): Route colour.
		material (Enum.Material): Route material.

	Returns:
		Part: Created route part.
]]
local function make_route(
	parent: Instance,
	name: string,
	start_pos: Vector3,
	end_pos: Vector3,
	width: number,
	color: Color3,
	material: Enum.Material
): Part
	local delta = end_pos - start_pos
	local midpoint = (start_pos + end_pos) * 0.5
	local route = make_part(
		parent,
		name,
		Vector3.new(width, 1, delta.Magnitude),
		CFrame.lookAt(midpoint, end_pos),
		color,
		material,
		true
	)
	return route
end
--[[
	Creates a simple lookout tower for long sightlines.

	Args:
		parent (Instance): Parent container.
		name (string): Tower name.
		position (Vector3): Tower base position.
		color (Color3): Tower colour.

	Returns:
		Model: Created lookout model.
]]
local function make_lookout(
	parent: Instance,
	name: string,
	position: Vector3,
	color: Color3
): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	make_part(
		model,
		"Pillar",
		Vector3.new(18, 40, 18),
		CFrame.new(position + Vector3.new(0, 20, 0)),
		color,
		Enum.Material.Slate,
		true
	)
	make_part(
		model,
		"Platform",
		Vector3.new(34, 3, 34),
		CFrame.new(position + Vector3.new(0, 41, 0)),
		color,
		Enum.Material.WoodPlanks,
		true
	)
	return model
end
--[[
	Creates non-uniform rock cover without invisible blockers.

	Args:
		parent (Instance): Parent container.
		prefix (string): Name prefix.
		center (Vector3): Cluster centre.
		color (Color3): Rock colour.

	Returns:
		None.
]]
local function make_rock_cluster(
	parent: Instance,
	prefix: string,
	center: Vector3,
	color: Color3
)
	local offsets = {
		Vector3.new(-18, 8, -7),
		Vector3.new(3, 12, 8),
		Vector3.new(19, 7, -3),
	}

	for index, offset in ipairs(offsets) do
		local rock = make_part(
			parent,
			("%s_%d"):format(prefix, index),
			Vector3.new(18 + index * 3, 14 + index * 5, 16),
			CFrame.new(center + offset)
				* CFrame.Angles(0.15, index * 0.7, 0.12),
			color,
			Enum.Material.Rock,
			true
		)
		rock.Shape = Enum.PartType.Ball
	end
end
--[[
	Creates the large ground plate for a faction region.

	Args:
		parent (Instance): Parent container.
		spec (RegionSpec): Region configuration.

	Returns:
		Part: Created region ground.
]]
local function make_region_ground(
	parent: Instance,
	spec: RegionSpec
): Part
	local thickness = 14
	local size = Vector3.new(760, thickness, 760)
	local position = Vector3.new(
		spec.center.X,
		spec.top_y - thickness * 0.5,
		spec.center.Z
	)
	local ground = make_part(
		parent,
		spec.id .. "Ground",
		size,
		CFrame.new(position),
		spec.color,
		spec.material,
		true
	)
	ground:SetAttribute("FactionId", spec.id)
	ground:SetAttribute("FactionRegion", true)
	return ground
end
--[[
	Adds landmark cover and high ground to one faction region.

	Args:
		parent (Instance): Region container.
		spec (RegionSpec): Region configuration.

	Returns:
		None.
]]
local function decorate_region(
	parent: Instance,
	spec: RegionSpec
)
	local top = spec.top_y
	make_world_label(
		parent,
		spec.id .. "Label",
		Vector3.new(spec.center.X, top + 55, spec.center.Z),
		spec.display_name,
		spec.color:Lerp(Color3.new(1, 1, 1), 0.35)
	)

	make_lookout(
		parent,
		spec.id .. "Lookout",
		Vector3.new(
			spec.center.X - 230,
			top,
			spec.center.Z - 190
		),
		spec.color
	)
	make_rock_cluster(
		parent,
		spec.id .. "Ambush",
		Vector3.new(
			spec.center.X + 170,
			top,
			spec.center.Z + 130
		),
		spec.color:Lerp(Color3.new(0.2, 0.2, 0.2), 0.45)
	)
end
--[[
	Adds Ossuary military ruins and bone-like regiment markers.

	Args:
		parent (Instance): Ossuary region container.
		spec (RegionSpec): Ossuary region configuration.

	Returns:
		None.
]]
local function decorate_ossuary(
	parent: Instance,
	spec: RegionSpec
)
	local gate_center = spec.center + Vector3.new(0, spec.top_y, 185)
	for _, x in ipairs({ -34, 34 }) do
		make_part(
			parent,
			"OssuaryGatePost",
			Vector3.new(16, 54, 16),
			CFrame.new(gate_center + Vector3.new(x, 27, 0)),
			Color3.fromRGB(185, 171, 132),
			Enum.Material.Sandstone,
			true
		)
	end
	make_part(
		parent,
		"OssuaryGateLintel",
		Vector3.new(84, 12, 16),
		CFrame.new(gate_center + Vector3.new(0, 52, 0)),
		COLORS.ossuary,
		Enum.Material.Sandstone,
		true
	)

	for index = 1, 5 do
		local z = spec.center.Z - 170 + index * 62
		make_part(
			parent,
			("LegionMarker%d"):format(index),
			Vector3.new(9, 32, 9),
			CFrame.new(spec.center.X - 250, spec.top_y + 16, z)
				* CFrame.Angles(0, 0, 0.08 * index),
			Color3.fromRGB(199, 187, 151),
			Enum.Material.Marble,
			true
		)
	end
end

--[[
	Adds Mirebound pools and reed silhouettes.

	Args:
		parent (Instance): Mirebound region container.
		spec (RegionSpec): Mirebound region configuration.

	Returns:
		None.
]]
local function decorate_mire(
	parent: Instance,
	spec: RegionSpec
)
	local pool_positions = {
		Vector3.new(-180, 1, -90),
		Vector3.new(155, 1, -145),
		Vector3.new(110, 1, 170),
	}
	for index, offset in ipairs(pool_positions) do
		make_disc(
			parent,
			("MirePool%d"):format(index),
			spec.center + offset + Vector3.new(0, spec.top_y, 0),
			82,
			Color3.fromRGB(48, 93, 79),
			Enum.Material.SmoothPlastic
		)
	end

	for index = 1, 12 do
		local angle = index * 1.7
		local radius = 120 + (index % 4) * 35
		local pos = spec.center + Vector3.new(
			math.cos(angle) * radius,
			spec.top_y + 11,
			math.sin(angle) * radius
		)
		make_part(
			parent,
			("ReedTotem%d"):format(index),
			Vector3.new(3, 22 + index % 5, 3),
			CFrame.new(pos),
			Color3.fromRGB(95, 122, 68),
			Enum.Material.Wood,
			true
		)
	end
end

--[[
	Adds Ashen basalt spires and glowing volcanic cracks.

	Args:
		parent (Instance): Ashen region container.
		spec (RegionSpec): Ashen region configuration.

	Returns:
		None.
]]
local function decorate_ashen(
	parent: Instance,
	spec: RegionSpec
)
	for index = 1, 7 do
		local angle = index * 0.91
		local radius = 145 + (index % 3) * 38
		local height = 34 + index * 5
		local pos = spec.center + Vector3.new(
			math.cos(angle) * radius,
			spec.top_y + height * 0.5,
			math.sin(angle) * radius
		)
		make_part(
			parent,
			("BasaltSpire%d"):format(index),
			Vector3.new(14, height, 18),
			CFrame.new(pos) * CFrame.Angles(0.08, angle, 0.12),
			Color3.fromRGB(49, 43, 42),
			Enum.Material.Basalt,
			true
		)
	end

	for index = 1, 5 do
		local offset = (index - 3) * 48
		make_part(
			parent,
			("EmberFissure%d"):format(index),
			Vector3.new(6, 0.6, 90),
			CFrame.new(
				spec.center.X + offset,
				spec.top_y + 0.35,
				spec.center.Z + 40
			) * CFrame.Angles(0, index * 0.28, 0),
			Color3.fromRGB(255, 97, 42),
			Enum.Material.Neon,
			false,
			0.08
		)
	end
end

--[[
	Adds Grave Court mausoleum rows and funeral lanterns.

	Args:
		parent (Instance): Grave Court region container.
		spec (RegionSpec): Grave Court region configuration.

	Returns:
		None.
]]
local function decorate_grave(
	parent: Instance,
	spec: RegionSpec
)
	for index = 1, 8 do
		local row = if index <= 4 then -1 else 1
		local slot = ((index - 1) % 4) - 1.5
		local pos = spec.center + Vector3.new(
			slot * 70,
			spec.top_y + 13,
			row * 190
		)
		make_part(
			parent,
			("MausoleumStone%d"):format(index),
			Vector3.new(32, 26, 12),
			CFrame.new(pos),
			Color3.fromRGB(82, 78, 92),
			Enum.Material.Slate,
			true
		)
	end

	for index = 1, 4 do
		local angle = index * math.pi * 0.5
		local pos = spec.center + Vector3.new(
			math.cos(angle) * 115,
			spec.top_y + 18,
			math.sin(angle) * 115
		)
		local lantern = make_part(
			parent,
			("FuneralLantern%d"):format(index),
			Vector3.new(7, 36, 7),
			CFrame.new(pos),
			Color3.fromRGB(91, 79, 106),
			Enum.Material.Metal,
			true
		)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(157, 93, 222)
		light.Brightness = 2
		light.Range = 22
		light.Parent = lantern
	end
end

--[[
	Adds faction-specific visual language to a region.

	Args:
		parent (Instance): Region container.
		spec (RegionSpec): Region configuration.

	Returns:
		None.
]]
local function decorate_faction_identity(
	parent: Instance,
	spec: RegionSpec
)
	if spec.id == "OssuaryLegion" then
		decorate_ossuary(parent, spec)
	elseif spec.id == "Mirebound" then
		decorate_mire(parent, spec)
	elseif spec.id == "AshenCovenant" then
		decorate_ashen(parent, spec)
	elseif spec.id == "GraveCourt" then
		decorate_grave(parent, spec)
	end
end

--[[
	Creates a dedicated boss arena with clear entry sightlines.

	Args:
		parent (Instance): Boss-space folder.
		spec (RegionSpec): Owning faction region.

	Returns:
		Part: Created boss floor.
]]
local function make_boss_space(
	parent: Instance,
	spec: RegionSpec
): Part
	local direction = (
		spec.center - ARENA_CENTER
	).Unit
	local center = Vector3.new(
		spec.center.X + direction.X * 215,
		spec.top_y + 1,
		spec.center.Z + direction.Z * 215
	)
	local floor = make_disc(
		parent,
		spec.id .. "BossArena",
		center,
		150,
		spec.color:Lerp(Color3.new(0.12, 0.12, 0.12), 0.3),
		spec.material
	)
	floor:SetAttribute("FactionId", spec.id)
	floor:SetAttribute("HighRewardZone", true)

	for index = 1, 6 do
		local angle = (math.pi * 2 / 6) * index
		local offset = Vector3.new(
			math.cos(angle) * 88,
			18,
			math.sin(angle) * 88
		)
		make_part(
			parent,
			("%sBossPillar%d"):format(spec.id, index),
			Vector3.new(10, 36, 10),
			CFrame.new(center + offset),
			spec.color,
			Enum.Material.Slate,
			true
		)
	end
	return floor
end
--[[
	Creates the central contested crossroads and arrival point.

	Args:
		parent (Instance): Authored Arena container.
		arena (Model): ArenaWorld model.

	Returns:
		None.
]]
local function build_contested_center(
	parent: Instance,
	arena: Model
)
	local paths = get_or_create_folder(parent, "Routes")
	local center_y = 4
	local center = Vector3.new(1000, center_y, 1000)

	make_part(
		paths,
		"CrossroadsNorthSouth",
		Vector3.new(180, 3, 720),
		CFrame.new(center),
		COLORS.neutral,
		Enum.Material.Cobblestone,
		true
	)
	make_part(
		paths,
		"CrossroadsEastWest",
		Vector3.new(720, 3, 180),
		CFrame.new(center),
		COLORS.neutral,
		Enum.Material.Cobblestone,
		true
	)
	make_disc(
		paths,
		"ArrivalCircle",
		center + Vector3.new(0, 2, 0),
		155,
		Color3.fromRGB(95, 88, 76),
		Enum.Material.Cobblestone
	)

	local spawn = arena:FindFirstChild("ArenaSpawnRegion")
	if spawn and spawn:IsA("BasePart") then
		spawn.Position = Vector3.new(1000, 45, 1000)
		spawn.Size = Vector3.new(150, 100, 150)
		spawn.Transparency = 1
		spawn.CanCollide = false
	end
end
--[[
	Creates the four faction districts and their travel routes.

	Args:
		parent (Instance): Authored Arena container.

	Returns:
		None.
]]
local function build_faction_regions(parent: Instance)
	local regions = get_or_create_folder(parent, "FactionRegions")
	local routes = get_or_create_folder(parent, "Routes")
	local boss_spaces = get_or_create_folder(parent, "BossSpaces")

	for _, spec in ipairs(REGION_SPECS) do
		local region = Instance.new("Model")
		region.Name = spec.id
		region:SetAttribute("FactionId", spec.id)
		region.Parent = regions

		make_region_ground(region, spec)
		decorate_region(region, spec)
		decorate_faction_identity(region, spec)
		make_boss_space(boss_spaces, spec)

		local start_pos = Vector3.new(1000, 4.5, 1000)
		local inward = (ARENA_CENTER - spec.center).Unit
		local corner_distance = 380 * math.sqrt(2)
		local route_y = spec.top_y - 0.5
		local entry_pos = Vector3.new(
			spec.center.X + inward.X * corner_distance,
			route_y,
			spec.center.Z + inward.Z * corner_distance
		)
		local center_pos = Vector3.new(
			spec.center.X,
			route_y,
			spec.center.Z
		)

		make_route(
			routes,
			spec.id .. "ApproachRamp",
			start_pos,
			entry_pos,
			58,
			COLORS.neutral,
			Enum.Material.Cobblestone
		)
		make_route(
			routes,
			spec.id .. "FactionRoad",
			entry_pos,
			center_pos,
			58,
			COLORS.neutral,
			Enum.Material.Cobblestone
		)
	end
end
--[[
	Creates side lanes that support ambushes and retreat choices.

	Args:
		parent (Instance): Authored Arena container.

	Returns:
		None.
]]
local function build_side_routes(parent: Instance)
	local routes = get_or_create_folder(parent, "Routes")
	local points = {
		{ "NorthPass", Vector3.new(520, 11.5, 320),
			Vector3.new(1480, 21.5, 320) },
		{ "SouthPass", Vector3.new(520, 4.5, 1680),
			Vector3.new(1480, 13.5, 1680) },
		{ "WestPass", Vector3.new(320, 11.5, 520),
			Vector3.new(320, 4.5, 1480) },
		{ "EastPass", Vector3.new(1680, 21.5, 520),
			Vector3.new(1680, 13.5, 1480) },
	}

	for _, entry in ipairs(points) do
		make_route(
			routes,
			entry[1] :: string,
			entry[2] :: Vector3,
			entry[3] :: Vector3,
			30,
			Color3.fromRGB(63, 59, 55),
			Enum.Material.Slate
		)
	end
end
--[[
	Creates dedicated high-risk event terrain.

	Args:
		parent (Instance): Authored Arena container.
		arena (Model): ArenaWorld model.

	Returns:
		None.
]]
local function build_event_space(
	parent: Instance,
	arena: Model
)
	local spaces = get_or_create_folder(parent, "EventSpaces")
	local center = Vector3.new(1000, 9, 470)
	make_disc(
		spaces,
		"SoulstormBasin",
		center,
		260,
		Color3.fromRGB(55, 64, 83),
		Enum.Material.Slate
	)
	make_world_label(
		spaces,
		"SoulstormLabel",
		center + Vector3.new(0, 44, 0),
		"SOULSTORM BASIN\nHIGH RISK EVOLUTION ZONE",
		Color3.fromRGB(126, 202, 255)
	)

	destroy_named_child(arena, "StormEventRegion")
	local region = make_part(
		arena,
		"StormEventRegion",
		Vector3.new(280, 80, 280),
		CFrame.new(center + Vector3.new(0, 30, 0)),
		Color3.fromRGB(80, 190, 255),
		Enum.Material.ForceField,
		false,
		1
	)
	region:SetAttribute("HighRiskZone", true)
end
--[[
	Builds the authored Arena while preserving compatibility parts.

	Args:
		None.

	Returns:
		boolean: True when the Arena was rebuilt.
]]
local function build_arena(): boolean
	local zones = Workspace:FindFirstChild("Zones")
	local arena = zones and zones:FindFirstChild("ArenaWorld")
	if not (arena and arena:IsA("Model")) then
		return false
	end

	destroy_named_child(arena, AUTHORED_NAME)
	local authored = Instance.new("Folder")
	authored.Name = AUTHORED_NAME
	authored.Parent = arena

	local floor = arena:FindFirstChild("ArenaFloor")
	if floor and floor:IsA("BasePart") then
		floor.Position = Vector3.new(1000, -8, 1000)
		floor.Size = Vector3.new(2000, 16, 2000)
		floor.Color = Color3.fromRGB(49, 55, 47)
		floor.Material = Enum.Material.Ground
	end

	build_contested_center(authored, arena)
	build_faction_regions(authored)
	build_side_routes(authored)
	build_event_space(authored, arena)
	return true
end
--[[
	Adds a station prompt used by BaseStationClient.

	Args:
		part (BasePart): Prompt parent.
		station_id (string): Station identifier.
		action_text (string): Prompt action text.

	Returns:
		ProximityPrompt: Created prompt.
]]
local function add_station_prompt(
	part: BasePart,
	station_id: string,
	action_text: string
): ProximityPrompt
	part:SetAttribute("BaseStationId", station_id)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BaseStationPrompt"
	prompt.ActionText = action_text
	prompt.ObjectText = station_id
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

--[[
	Creates a labelled Base station pad and interaction pedestal.

	Args:
		parent (Instance): Facilities container.
		name (string): Station name.
		position (Vector3): Station centre.
		color (Color3): Station accent.
		station_id (string): Client interaction identifier.

	Returns:
		Model: Created station model.
]]
local function make_station(
	parent: Instance,
	name: string,
	position: Vector3,
	color: Color3,
	station_id: string
): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent

	make_disc(
		model,
		"Floor",
		position,
		92,
		color:Lerp(Color3.fromRGB(32, 30, 34), 0.6),
		Enum.Material.Slate
	)

	local frame_color = color:Lerp(
		Color3.fromRGB(28, 27, 31),
		0.58
	)
	for _, offset in ipairs({
		Vector3.new(-32, 14, -24),
		Vector3.new(32, 14, -24),
		Vector3.new(-32, 14, 24),
		Vector3.new(32, 14, 24),
	}) do
		make_part(
			model,
			"StationColumn",
			Vector3.new(6, 28, 6),
			CFrame.new(position + offset),
			frame_color,
			Enum.Material.Slate,
			true
		)
	end
	make_part(
		model,
		"StationCanopy",
		Vector3.new(76, 3, 54),
		CFrame.new(position + Vector3.new(0, 29, 0)),
		frame_color,
		Enum.Material.Slate,
		true
	)

	local pedestal = make_part(
		model,
		"InteractionPedestal",
		Vector3.new(8, 8, 8),
		CFrame.new(position + Vector3.new(0, 5, 0)),
		color,
		Enum.Material.Neon,
		true
	)
	add_station_prompt(pedestal, station_id, "Use")
	make_world_label(
		model,
		"StationLabel",
		position + Vector3.new(0, 35, 0),
		name,
		color
	)
	return model
end
--[[
	Creates decorative clone chambers in the Soul Foundry.

	Args:
		parent (Instance): Soul Foundry station.
		center (Vector3): Foundry centre.

	Returns:
		None.
]]
local function add_clone_chambers(
	parent: Instance,
	center: Vector3
)
	for index = 1, 3 do
		local x = (index - 2) * 22
		local chamber = make_part(
			parent,
			("CloneChamber%d"):format(index),
			Vector3.new(10, 24, 10),
			CFrame.new(center + Vector3.new(x, 13, 18)),
			COLORS.soul,
			Enum.Material.Glass,
			true,
			0.38
		)
		chamber:SetAttribute("MachineIndex", index)
		local light = Instance.new("PointLight")
		light.Color = COLORS.soul
		light.Brightness = 1.5
		light.Range = 15
		light.Parent = chamber
	end
end
--[[
	Creates Master display plinths for visual army trophies.

	Args:
		parent (Instance): Gallery station.
		center (Vector3): Gallery centre.

	Returns:
		None.
]]
local function add_master_plinths(
	parent: Instance,
	center: Vector3
)
	for index = 1, 6 do
		local angle = (math.pi * 2 / 6) * index
		local offset = Vector3.new(
			math.cos(angle) * 28,
			2,
			math.sin(angle) * 28
		)
		local plinth = make_part(
			parent,
			("MasterPlinth%d"):format(index),
			Vector3.new(10, 4, 10),
			CFrame.new(center + offset),
			Color3.fromRGB(88, 74, 96),
			Enum.Material.Marble,
			true
		)
		plinth:SetAttribute("MasterDisplaySlot", index)
	end
end

--[[
	Creates deployable-unit display plinths around the Master Gallery.

	Args:
		parent (Instance): Gallery station.
		center (Vector3): Gallery centre.

	Returns:
		None.
]]
local function add_unit_plinths(
	parent: Instance,
	center: Vector3
)
	for index = 1, 6 do
		local angle = (math.pi * 2 / 6) * index + 0.52
		local offset = Vector3.new(
			math.cos(angle) * 40,
			1.5,
			math.sin(angle) * 40
		)
		local plinth = make_part(
			parent,
			("UnitPlinth%d"):format(index),
			Vector3.new(8, 3, 8),
			CFrame.new(center + offset),
			Color3.fromRGB(66, 71, 79),
			Enum.Material.Slate,
			true
		)
		plinth:SetAttribute("UnitDisplaySlot", index)
	end
end

--[[
	Creates boss trophy plinths for captured-major-boss presentation.

	Args:
		parent (Instance): Trophy Hall station.
		center (Vector3): Trophy Hall centre.

	Returns:
		None.
]]
local function add_trophy_plinths(
	parent: Instance,
	center: Vector3
)
	for index = 1, 4 do
		local x = if index % 2 == 0 then 23 else -23
		local z = if index <= 2 then -18 else 18
		local plinth = make_part(
			parent,
			("BossTrophyPlinth%d"):format(index),
			Vector3.new(14, 6, 14),
			CFrame.new(center + Vector3.new(x, 4, z)),
			Color3.fromRGB(111, 87, 54),
			Enum.Material.Marble,
			true
		)
		plinth:SetAttribute("BossTrophySlot", index)
	end
end

--[[
	Builds useful communal Base facilities around the town square.

	Args:
		None.

	Returns:
		boolean: True when facilities were rebuilt.
]]
local function build_base(): boolean
	local zones = Workspace:FindFirstChild("Zones")
	local safe = zones and zones:FindFirstChild("SafeZoneWorld")
	if not (safe and safe:IsA("Model")) then
		return false
	end

	destroy_named_child(safe, FACILITIES_NAME)
	local facilities = Instance.new("Folder")
	facilities.Name = FACILITIES_NAME
	facilities.Parent = safe
	local soul_pos = SAFE_CENTER + Vector3.new(0, 5, -220)
	local formation_pos = SAFE_CENTER + Vector3.new(-220, 5, 0)
	local skills_pos = SAFE_CENTER + Vector3.new(220, 5, 0)
	local codex_pos = SAFE_CENTER + Vector3.new(0, 5, 220)
	local master_pos = SAFE_CENTER + Vector3.new(175, 5, -175)
	local trophy_pos = SAFE_CENTER + Vector3.new(175, 5, 175)
	local forge_pos = SAFE_CENTER + Vector3.new(-175, 5, 175)

	local soul = make_station(
		facilities,
		"Soul Foundry & Cloning Hall",
		soul_pos,
		COLORS.soul,
		"SoulFoundry"
	)
	add_clone_chambers(soul, soul_pos)

	make_station(
		facilities,
		"Formation War Room",
		formation_pos,
		Color3.fromRGB(94, 160, 128),
		"FormationEditor"
	)
	make_station(
		facilities,
		"Skill Reliquary",
		skills_pos,
		Color3.fromRGB(168, 106, 75),
		"SkillLoadout"
	)
	make_station(
		facilities,
		"Necromancer Codex",
		codex_pos,
		Color3.fromRGB(99, 139, 175),
		"Codex"
	)

	local gallery = make_station(
		facilities,
		"Master Gallery",
		master_pos,
		Color3.fromRGB(150, 112, 174),
		"Masters"
	)
	add_master_plinths(gallery, master_pos)
	add_unit_plinths(gallery, master_pos)

	local trophy_hall = make_station(
		facilities,
		"Boss Trophy Hall",
		trophy_pos,
		COLORS.gold,
		"Trophies"
	)
	add_trophy_plinths(trophy_hall, trophy_pos)

	make_station(
		facilities,
		"Foundry Upgrade Forge",
		forge_pos,
		Color3.fromRGB(205, 112, 56),
		"Upgrades"
	)
	return true
end

--[[
	Builds all Phase 10 authored world geometry.

	Args:
		None.

	Returns:
		boolean: True when both Arena and Base were built.
]]
function Phase10WorldBuilder.build(): boolean
	local arena_ok = build_arena()
	local base_ok = build_base()
	return arena_ok and base_ok
end

return Phase10WorldBuilder
