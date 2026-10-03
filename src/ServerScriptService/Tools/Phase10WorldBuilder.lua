--!strict

local Workspace = game:GetService("Workspace")

local Phase10WorldBuilder = {}

local ARENA_CENTER = Vector3.new(1000, 0, 1000)
local SAFE_CENTER = Vector3.new(3600, 0, 3600)
local AUTHORED_NAME = "Phase10Authored"
local FACILITIES_NAME = "Phase10Facilities"
local PLOTS_FOLDER_NAME = "Bases"
local PLOT_COUNT = 8

local COLORS = {
	neutral = Color3.fromRGB(92, 86, 78),
	ossuary = Color3.fromRGB(166, 151, 116),
	mire = Color3.fromRGB(73, 105, 67),
	ashen = Color3.fromRGB(71, 61, 58),
	grave = Color3.fromRGB(72, 65, 83),
	soul = Color3.fromRGB(129, 81, 173),
	gold = Color3.fromRGB(188, 145, 72),
}

local FACILITY_PURPOSE: { [string]: string } = {
	SoulFoundry = "MASTER TUBE • GROW CLONES",
	FormationEditor = "EDIT ARMY FORMATIONS",
	SkillLoadout = "EQUIP & LEARN SKILLS",
	Codex = "RAISE UNITS • UNLOCK BONUSES",
	SoulCrucible = "SACRIFICE UNITS FOR ESSENCE",
	ReserveCrypt = "STORE & MANAGE RESERVE UNITS",
	Trophies = "DISPLAY DEFEATED BOSSES",
	Upgrades = "UPGRADE YOUR SANCTUM",
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
		plot_index (number): Owning Sanctum plot index.
		upgrade_key (string): Future physical-upgrade identifier.

	Returns:
		ProximityPrompt: Created prompt.
]]
local function add_station_prompt(
	part: BasePart,
	station_id: string,
	action_text: string,
	plot_index: number,
	upgrade_key: string
): ProximityPrompt
	part:SetAttribute("BaseStationId", station_id)
	part:SetAttribute("PlotIndex", plot_index)
	part:SetAttribute("PlotUpgradeKey", upgrade_key)

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
	Adds the War Room's physical command-table identity.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_war_room_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	local table_part = make_part(
		parent,
		"WarTable",
		Vector3.new(18, 3, 12),
		station_cf * CFrame.new(0, 2.5, 4),
		Color3.fromRGB(58, 52, 48),
		Enum.Material.WoodPlanks,
		true
	)
	make_part(
		parent,
		"WarMap",
		Vector3.new(15, 0.25, 9),
		table_part.CFrame * CFrame.new(0, 1.65, 0),
		color,
		Enum.Material.Neon,
		false,
		0.28
	)
end

--[[
	Adds the Reliquary's paired rune-pedestal identity.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_reliquary_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	for _, x in ipairs({ -8, 8 }) do
		local pillar = make_part(
			parent,
			"ReliquaryPillar",
			Vector3.new(6, 9, 6),
			station_cf * CFrame.new(x, 4.5, 5),
			Color3.fromRGB(77, 65, 60),
			Enum.Material.Slate,
			true
		)
		make_part(
			parent,
			"RuneTome",
			Vector3.new(7, 0.7, 5),
			pillar.CFrame * CFrame.new(0, 4.85, 0),
			color,
			Enum.Material.Neon,
			false,
			0.18
		)
	end
end

--[[
	Adds the Codex's reading desk and archive shelf.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_codex_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	make_part(
		parent,
		"CodexShelf",
		Vector3.new(24, 13, 3),
		station_cf * CFrame.new(0, 6.5, 9),
		Color3.fromRGB(52, 57, 66),
		Enum.Material.WoodPlanks,
		true
	)
	local desk = make_part(
		parent,
		"CodexDesk",
		Vector3.new(12, 4, 7),
		station_cf * CFrame.new(0, 2, 1),
		Color3.fromRGB(66, 59, 55),
		Enum.Material.WoodPlanks,
		true
	)
	make_part(
		parent,
		"OpenCodex",
		Vector3.new(8, 0.45, 5),
		desk.CFrame * CFrame.new(0, 2.25, 0),
		color,
		Enum.Material.Neon,
		false,
		0.25
	)
end

--[[
	Adds the Soul Crucible's ritual basin.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_crucible_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	local position = station_cf.Position
	make_disc(
		parent,
		"CrucibleBasin",
		position + Vector3.new(0, 3.2, 0),
		18,
		Color3.fromRGB(55, 42, 45),
		Enum.Material.Slate
	)
	local core = make_disc(
		parent,
		"CrucibleCore",
		position + Vector3.new(0, 4.1, 0),
		11,
		color,
		Enum.Material.Neon
	)
	core.CanCollide = false
end

--[[
	Adds the Reserve Crypt's stone alcove identity.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_reserve_crypt_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	make_part(
		parent,
		"CryptRearWall",
		Vector3.new(44, 15, 3),
		station_cf * CFrame.new(0, 7.5, 18),
		color:Lerp(Color3.fromRGB(37, 34, 42), 0.65),
		Enum.Material.Slate,
		true
	)
	for _, x in ipairs({ -18, -6, 6, 18 }) do
		make_part(
			parent,
			"CryptPillar",
			Vector3.new(3, 15, 4),
			station_cf * CFrame.new(x, 7.5, 15),
			Color3.fromRGB(59, 54, 65),
			Enum.Material.Slate,
			true
		)
	end
end

--[[
	Adds the Trophy Hall's paired victory standards.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_trophy_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	for _, x in ipairs({ -17, 17 }) do
		make_part(
			parent,
			"TrophyStandard",
			Vector3.new(4, 20, 4),
			station_cf * CFrame.new(x, 10, 15),
			color,
			Enum.Material.Metal,
			true
		)
	end
end

--[[
	Adds the Upgrade Forge's hearth and anvil silhouette.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_forge_identity(
	parent: Instance,
	station_cf: CFrame,
	color: Color3
)
	local hearth = make_part(
		parent,
		"ForgeHearth",
		Vector3.new(14, 8, 8),
		station_cf * CFrame.new(0, 4, 7),
		Color3.fromRGB(67, 55, 49),
		Enum.Material.Slate,
		true
	)
	make_part(
		parent,
		"ForgeFire",
		Vector3.new(9, 4, 1),
		hearth.CFrame * CFrame.new(0, 0, -4.4),
		color,
		Enum.Material.Neon,
		false,
		0.08
	)
	make_part(
		parent,
		"ForgeAnvil",
		Vector3.new(9, 4, 5),
		station_cf * CFrame.new(0, 2, -1),
		Color3.fromRGB(62, 60, 64),
		Enum.Material.Metal,
		true
	)
end

--[[
	Adds props that make a facility readable before its UI is opened.

	Args:
		parent (Instance): Station model receiving the props.
		station_cf (CFrame): Station transform.
		station_id (string): Functional station identifier.
		color (Color3): Station accent colour.

	Returns:
		None.
]]
local function add_station_identity(
	parent: Instance,
	station_cf: CFrame,
	station_id: string,
	color: Color3
)
	if station_id == "FormationEditor" then
		add_war_room_identity(parent, station_cf, color)
	elseif station_id == "SkillLoadout" then
		add_reliquary_identity(parent, station_cf, color)
	elseif station_id == "Codex" then
		add_codex_identity(parent, station_cf, color)
	elseif station_id == "SoulCrucible" then
		add_crucible_identity(parent, station_cf, color)
	elseif station_id == "ReserveCrypt" then
		add_reserve_crypt_identity(parent, station_cf, color)
	elseif station_id == "Trophies" then
		add_trophy_identity(parent, station_cf, color)
	elseif station_id == "Upgrades" then
		add_forge_identity(parent, station_cf, color)
	end
end

--[[
	Creates an open-front, purpose-labelled facility.

	The front of every plot is local negative Z. Keeping the front open makes
	each station's unique gameplay prop readable from the natural approach.

	Args:
		parent (Instance): Plot facilities container.
		name (string): Station display name.
		station_cf (CFrame): Station world transform.
		color (Color3): Station accent.
		station_id (string): Client interaction identifier.
		plot_index (number): Owning plot index.
		diameter (number): Station floor diameter.
		upgrade_key (string): Physical-upgrade identifier.

	Returns:
		Model: Created station model.
]]
local function make_station(
	parent: Instance,
	name: string,
	station_cf: CFrame,
	color: Color3,
	station_id: string,
	plot_index: number,
	diameter: number,
	upgrade_key: string
): Model
	local model = Instance.new("Model")
	model.Name = name
	model:SetAttribute("BaseStationId", station_id)
	model:SetAttribute("PlotIndex", plot_index)
	model:SetAttribute("PlotUpgradeKey", upgrade_key)
	model:SetAttribute(
		"FacilityPurpose",
		FACILITY_PURPOSE[station_id] or "OPEN FACILITY"
	)
	model.Parent = parent

	local position = station_cf.Position
	make_disc(
		model,
		"Floor",
		position,
		diameter,
		color:Lerp(Color3.fromRGB(30, 29, 33), 0.68),
		Enum.Material.Slate
	)
	local inset = make_disc(
		model,
		"FloorAccent",
		position + Vector3.new(0, 0.15, 0),
		diameter * 0.74,
		color:Lerp(Color3.fromRGB(28, 27, 31), 0.48),
		Enum.Material.SmoothPlastic
	)
	inset.CanCollide = false

	local frame_color = color:Lerp(
		Color3.fromRGB(28, 27, 31),
		0.58
	)
	local x_offset = diameter * 0.32
	local rear_z = diameter * 0.22
	for _, x in ipairs({ -x_offset, x_offset }) do
		make_part(
			model,
			"RearColumn",
			Vector3.new(4, 20, 4),
			station_cf * CFrame.new(x, 10, rear_z),
			frame_color,
			Enum.Material.Slate,
			true
		)
	end

	make_part(
		model,
		"StationCanopy",
		Vector3.new(
			diameter * 0.78,
			2,
			diameter * 0.42
		),
		station_cf * CFrame.new(0, 21, rear_z * 0.45),
		frame_color,
		Enum.Material.Slate,
		true
	)

	add_station_identity(
		model,
		station_cf,
		station_id,
		color
	)

	local console_z = -(diameter * 0.32)
	local pedestal = make_part(
		model,
		"InteractionPedestal",
		Vector3.new(9, 4.5, 5),
		station_cf * CFrame.new(0, 2.25, console_z),
		frame_color,
		Enum.Material.Metal,
		true
	)
	local glow = make_part(
		model,
		"ConsoleGlow",
		Vector3.new(7, 0.4, 3),
		pedestal.CFrame * CFrame.new(0, 2.4, 0),
		color,
		Enum.Material.Neon,
		false,
		0.08
	)
	glow.CanQuery = false

	local prompt = add_station_prompt(
		pedestal,
		station_id,
		"Open",
		plot_index,
		upgrade_key
	)
	prompt.ObjectText = name

	local purpose = FACILITY_PURPOSE[station_id] or "OPEN FACILITY"
	local label_anchor = make_world_label(
		model,
		"StationLabel",
		(
			station_cf
				* CFrame.new(0, 27, -diameter * 0.08)
		).Position,
		("%s\n%s"):format(name, purpose),
		color
	)
	local billboard = label_anchor:FindFirstChild("Label")
	if billboard and billboard:IsA("BillboardGui") then
		billboard.Size = UDim2.fromOffset(360, 92)
	end
	return model
end

--[[
	Creates an owner sign at the front of a Sanctum plot.

	Args:
		parent (Instance): Plot model.
		plot_cf (CFrame): Plot surface transform.
		plot_index (number): Plot index.

	Returns:
		BasePart: Owner-sign anchor.
]]
local function make_plot_owner_sign(
	parent: Instance,
	plot_cf: CFrame,
	plot_index: number
): BasePart
	local anchor = make_part(
		parent,
		"PlotOwnerSign",
		Vector3.new(1, 1, 1),
		plot_cf * CFrame.new(0, 24, -112),
		COLORS.gold,
		Enum.Material.SmoothPlastic,
		false,
		1
	)
	anchor:SetAttribute("PlotIndex", plot_index)

	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerBillboard"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(290, 64)
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "OwnerText"
	label.BackgroundColor3 = Color3.fromRGB(17, 15, 20)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = ("PLOT %02d\nUNCLAIMED"):format(plot_index)
	label.TextColor3 = COLORS.gold
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
	return anchor
end

--[[
	Tags a cloning-machine visual for level-based visibility.

	Args:
		part (BasePart): Machine geometry to tag.
		machine_index (number): Foundry machine index.

	Returns:
		None.
]]
local function tag_machine_visual(
	part: BasePart,
	machine_index: number
)
	part:SetAttribute("MachineVisualIndex", machine_index)
	part:SetAttribute(
		"MachineBaseTransparency",
		part.Transparency
	)
	part:SetAttribute(
		"MachineBaseCanCollide",
		part.CanCollide
	)
end

--[[
	Creates one visible cloning tube and its hidden display anchor.

	Args:
		parent (Instance): Soul Foundry station.
		name (string): Tube name prefix.
		tube_cf (CFrame): Tube centre transform.
		label_text (string): World label above the tube.
		plot_index (number): Owning plot index.
		machine_index (number?): Clone tube index, or nil for Master Tube.

	Returns:
		BasePart: Hidden display anchor inside the tube.
]]
local function add_clone_tube(
	parent: Instance,
	name: string,
	tube_cf: CFrame,
	label_text: string,
	plot_index: number,
	machine_index: number?
): BasePart
	local anchor = make_part(
		parent,
		name .. "Anchor",
		Vector3.new(1, 1, 1),
		tube_cf,
		COLORS.soul,
		Enum.Material.SmoothPlastic,
		false,
		1
	)
	anchor.CanQuery = false
	anchor:SetAttribute("PlotIndex", plot_index)

	if machine_index then
		anchor:SetAttribute("MachineIndex", machine_index)
	else
		anchor:SetAttribute("MasterTubeAnchor", true)
	end

	local tube = make_part(
		parent,
		name,
		Vector3.new(8, 20, 8),
		tube_cf,
		COLORS.soul,
		Enum.Material.Glass,
		true,
		0.42
	)
	if machine_index then
		tag_machine_visual(tube, machine_index)
	end

	for _, y in ipairs({ -10.8, 10.8 }) do
		local cap = make_part(
			parent,
			name .. "Cap",
			Vector3.new(9.2, 1.6, 9.2),
			tube.CFrame * CFrame.new(0, y, 0),
			Color3.fromRGB(63, 55, 72),
			Enum.Material.Metal,
			true
		)
		if machine_index then
			tag_machine_visual(cap, machine_index)
		end
	end

	local light = Instance.new("PointLight")
	light.Color = COLORS.soul
	light.Brightness = 1.6
	light.Range = 13
	light.Parent = tube

	local label = make_world_label(
		parent,
		name .. "Label",
		(tube_cf * CFrame.new(0, 13.5, 0)).Position,
		label_text,
		COLORS.soul
	)
	local gui = label:FindFirstChild("Label")
	if gui and gui:IsA("BillboardGui") then
		gui.Size = UDim2.fromOffset(150, 52)
	end
	if machine_index then
		label:SetAttribute(
			"CloneTubeLabelIndex",
			machine_index
		)
	end
	return anchor
end

--[[
	Creates one shared Master Clone Tube plus three clone tubes.

	The Master unit is visible in one dedicated tube. Every unlocked clone
	tube beside it produces copies of that same unit.

	Args:
		parent (Instance): Soul Foundry station.
		station_cf (CFrame): Foundry transform.
		plot_index (number): Owning plot index.

	Returns:
		None.
]]
local function add_clone_chambers(
	parent: Instance,
	station_cf: CFrame,
	plot_index: number
)
	add_clone_tube(
		parent,
		"MasterCloneTube",
		station_cf * CFrame.new(-27, 11, -1),
		"MASTER TUBE",
		plot_index,
		nil
	)

	for index, x in ipairs({ -9, 9, 27 }) do
		add_clone_tube(
			parent,
			("CloneTube%d"):format(index),
			station_cf * CFrame.new(x, 11, -1),
			("CLONE TUBE %d"):format(index),
			plot_index,
			index
		)
	end
end

--[[
	Creates visible Reserve Crypt alcoves for stored units.

	These are presentation slots only. The Reserve Crypt does not cap how
	many units the player may deliberately store at the Sanctum.

	Args:
		parent (Instance): Reserve Crypt station.
		station_cf (CFrame): Crypt transform.
		plot_index (number): Owning plot index.

	Returns:
		None.
]]
local function add_reserve_plinths(
	parent: Instance,
	station_cf: CFrame,
	plot_index: number
)
	for index = 1, 14 do
		local column = ((index - 1) % 7) + 1
		local row = math.floor((index - 1) / 7) + 1
		local x = (column - 4) * 8
		local z = if row == 1 then -15 else 15
		local plinth = make_part(
			parent,
			("ReserveAlcove%d"):format(index),
			Vector3.new(6, 3, 6),
			station_cf * CFrame.new(x, 1.5, z),
			Color3.fromRGB(73, 66, 80),
			Enum.Material.Slate,
			true
		)
		plinth:SetAttribute("ReserveDisplaySlot", index)
		plinth:SetAttribute("PlotIndex", plot_index)
	end
end

--[[
	Creates deployable-unit plinths inside one plot gallery.

	Args:
		parent (Instance): Gallery station.
		station_cf (CFrame): Gallery transform.
		plot_index (number): Owning plot index.

	Returns:
		None.
]]
local function add_unit_plinths(
	parent: Instance,
	station_cf: CFrame,
	plot_index: number
)
	for index = 1, 8 do
		local column = ((index - 1) % 4) + 1
		local row = math.floor((index - 1) / 4) + 1
		local x = (column - 2.5) * 10
		local z = if row == 1 then -13 else 13
		local plinth = make_part(
			parent,
			("UnitPlinth%d"):format(index),
			Vector3.new(6, 3, 6),
			station_cf * CFrame.new(x, 1.5, z),
			Color3.fromRGB(66, 71, 79),
			Enum.Material.Slate,
			true
		)
		plinth:SetAttribute("UnitDisplaySlot", index)
		plinth:SetAttribute("PlotIndex", plot_index)
	end
end

--[[
	Creates boss trophy plinths inside one player plot.

	Args:
		parent (Instance): Trophy Hall station.
		station_cf (CFrame): Trophy Hall transform.
		plot_index (number): Owning plot index.

	Returns:
		None.
]]
local function add_trophy_plinths(
	parent: Instance,
	station_cf: CFrame,
	plot_index: number
)
	for index = 1, 8 do
		local column = ((index - 1) % 4) + 1
		local row = math.floor((index - 1) / 4) + 1
		local x = (column - 2.5) * 12
		local z = if row == 1 then -12 else 12
		local plinth = make_part(
			parent,
			("BossTrophyPlinth%d"):format(index),
			Vector3.new(9, 5, 9),
			station_cf * CFrame.new(x, 3.5, z),
			Color3.fromRGB(111, 87, 54),
			Enum.Material.Marble,
			true
		)
		plinth:SetAttribute("BossTrophySlot", index)
		plinth:SetAttribute("PlotIndex", plot_index)
	end
end

--[[
	Removes superseded interior props from the recovered base shell.

	The perimeter walls, gate, towers, banners, torches, and town path remain.
	Only the old house and fire pit are removed because they overlap the
	functional Sanctum facilities.

	Args:
		plot (Model): Plot containing the recovered Decor folder.

	Returns:
		None.
]]
local function clear_legacy_plot_clutter(plot: Model)
	local decor = plot:FindFirstChild("Decor")
	if not decor then
		return
	end

	for _, child in ipairs(decor:GetChildren()) do
		local is_house = string.sub(child.Name, 1, 6) == "House_"
		if child.Name == "FirePit" or is_house then
			child:Destroy()
		end
	end
end

--[[
	Adds a low-profile path grid that explains the plot's three rows.

	Args:
		parent (Instance): Facilities folder receiving path parts.
		surface_cf (CFrame): Plot surface transform.

	Returns:
		None.
]]
local function add_plot_walkways(
	parent: Instance,
	surface_cf: CFrame
)
	local path_color = Color3.fromRGB(72, 62, 83)
	local trim_color = Color3.fromRGB(119, 84, 153)

	make_part(
		parent,
		"MainSanctumAisle",
		Vector3.new(16, 0.35, 186),
		surface_cf * CFrame.new(0, 0.18, -2),
		path_color,
		Enum.Material.Cobblestone,
		false
	)
	for index, z in ipairs({ -58, 10, 76 }) do
		make_part(
			parent,
			("SanctumCrossAisle%d"):format(index),
			Vector3.new(205, 0.32, 12),
			surface_cf * CFrame.new(0, 0.16, z),
			path_color,
			Enum.Material.Cobblestone,
			false
		)
	end
	make_part(
		parent,
		"MainAisleSoulTrim",
		Vector3.new(2.5, 0.4, 186),
		surface_cf * CFrame.new(0, 0.39, -2),
		trim_color,
		Enum.Material.Neon,
		false,
		0.35
	)
end

--[[
	Adds a concise orientation board near the player's arrival point.

	Args:
		parent (Instance): Facilities folder receiving the guide.
		surface_cf (CFrame): Plot surface transform.

	Returns:
		None.
]]
local function add_plot_guide(
	parent: Instance,
	surface_cf: CFrame
)
	local anchor = make_world_label(
		parent,
		"SanctumGuide",
		(
			surface_cf
				* CFrame.new(0, 14, -96)
		).Position,
		(
			"SANCTUM\n"
			.. "FRONT • COMMAND & SKILLS\n"
			.. "MIDDLE • STUDY, SACRIFICE & UPGRADES\n"
			.. "REAR • RESERVES, CLONING & TROPHIES"
		),
		COLORS.soul
	)
	local gui = anchor:FindFirstChild("Label")
	if gui and gui:IsA("BillboardGui") then
		gui.Size = UDim2.fromOffset(420, 112)
	end
end

--[[
	Sets default physical upgrade metadata on one plot.

	Args:
		plot (Model): Plot receiving defaults.

	Returns:
		None.
]]
local function set_plot_upgrade_defaults(plot: Model)
	local defaults = {
		PlotLevel = 1,
		SoulFoundryLevel = 1,
		FormationLevel = 1,
		SkillReliquaryLevel = 1,
		CodexLevel = 1,
		SoulCrucibleLevel = 1,
		ReserveCryptLevel = 1,
		TrophyHallLevel = 1,
		UpgradeForgeLevel = 1,
	}
	for name, value in pairs(defaults) do
		if plot:GetAttribute(name) == nil then
			plot:SetAttribute(name, value)
		end
	end
end

--[[
	Builds all functional facilities inside one Sanctum plot.

	The grid is intentionally ordered from the gate inward:
	front = army command and skills; middle = knowledge, sacrifice, upgrades;
	rear = long-term collection, cloning, and trophies.

	Args:
		plot (Model): Player plot model.
		plot_index (number): Plot index.

	Returns:
		boolean: True when the plot facilities were built.
]]
local function build_plot_facilities(
	plot: Model,
	plot_index: number
): boolean
	local floor = plot:FindFirstChild("Plot")
	if not (floor and floor:IsA("BasePart")) then
		return false
	end

	plot:SetAttribute("PlotIndex", plot_index)
	plot:SetAttribute("PlotOwnerUserId", 0)
	plot:SetAttribute("PlotOwnerName", "")
	plot:SetAttribute("PlotOccupied", false)
	set_plot_upgrade_defaults(plot)
	clear_legacy_plot_clutter(plot)

	destroy_named_child(plot, FACILITIES_NAME)
	destroy_named_child(plot, "PlotOwnerSign")

	local facilities = Instance.new("Folder")
	facilities.Name = FACILITIES_NAME
	facilities:SetAttribute("PlotIndex", plot_index)
	facilities.Parent = plot

	local surface_cf = floor.CFrame * CFrame.new(
		0,
		floor.Size.Y * 0.5 + 1,
		0
	)
	make_plot_owner_sign(plot, surface_cf, plot_index)
	add_plot_walkways(facilities, surface_cf)
	add_plot_guide(facilities, surface_cf)

	local formation_cf = surface_cf * CFrame.new(-62, 0, -58)
	local skills_cf = surface_cf * CFrame.new(62, 0, -58)
	local codex_cf = surface_cf * CFrame.new(-80, 0, 10)
	local crucible_cf = surface_cf * CFrame.new(0, 0, 10)
	local forge_cf = surface_cf * CFrame.new(80, 0, 10)
	local reserve_cf = surface_cf * CFrame.new(-84, 0, 76)
	local soul_cf = surface_cf * CFrame.new(0, 0, 76)
	local trophy_cf = surface_cf * CFrame.new(84, 0, 76)

	local war_room = make_station(
		facilities,
		"Formation War Room",
		formation_cf,
		Color3.fromRGB(94, 160, 128),
		"FormationEditor",
		plot_index,
		46,
		"FormationLevel"
	)
	add_unit_plinths(
		war_room,
		formation_cf,
		plot_index
	)

	make_station(
		facilities,
		"Skill Reliquary",
		skills_cf,
		Color3.fromRGB(168, 106, 75),
		"SkillLoadout",
		plot_index,
		46,
		"SkillReliquaryLevel"
	)

	make_station(
		facilities,
		"Necromancer Codex",
		codex_cf,
		Color3.fromRGB(99, 139, 175),
		"Codex",
		plot_index,
		42,
		"CodexLevel"
	)

	make_station(
		facilities,
		"Sacrificial Soul Crucible",
		crucible_cf,
		Color3.fromRGB(126, 48, 58),
		"SoulCrucible",
		plot_index,
		42,
		"SoulCrucibleLevel"
	)

	make_station(
		facilities,
		"Foundry Upgrade Forge",
		forge_cf,
		Color3.fromRGB(205, 112, 56),
		"Upgrades",
		plot_index,
		42,
		"UpgradeForgeLevel"
	)

	local reserve_crypt = make_station(
		facilities,
		"Reserve Crypt",
		reserve_cf,
		Color3.fromRGB(116, 103, 134),
		"ReserveCrypt",
		plot_index,
		58,
		"ReserveCryptLevel"
	)
	add_reserve_plinths(
		reserve_crypt,
		reserve_cf,
		plot_index
	)

	local soul = make_station(
		facilities,
		"Soul Foundry & Cloning Hall",
		soul_cf,
		COLORS.soul,
		"SoulFoundry",
		plot_index,
		70,
		"SoulFoundryLevel"
	)
	add_clone_chambers(soul, soul_cf, plot_index)

	local trophy_hall = make_station(
		facilities,
		"Boss Trophy Hall",
		trophy_cf,
		COLORS.gold,
		"Trophies",
		plot_index,
		54,
		"TrophyHallLevel"
	)
	add_trophy_plinths(
		trophy_hall,
		trophy_cf,
		plot_index
	)
	return true
end

--[[
	Builds eight self-contained player plots in the Sanctum.

	Args:
		None.

	Returns:
		boolean: True when all eight plots were rebuilt.
]]
local function build_base(): boolean
	local zones = Workspace:FindFirstChild("Zones")
	local safe = zones and zones:FindFirstChild("SafeZoneWorld")
	if not (safe and safe:IsA("Model")) then
		return false
	end

	destroy_named_child(safe, FACILITIES_NAME)

	local plots = safe:FindFirstChild(PLOTS_FOLDER_NAME)
	if not (plots and plots:IsA("Folder")) then
		return false
	end

	local built = 0
	for plot_index = 1, PLOT_COUNT do
		local plot_name = ("Base%02d"):format(plot_index)
		local plot = plots:FindFirstChild(plot_name)
		if plot and plot:IsA("Model") then
			if build_plot_facilities(plot, plot_index) then
				built += 1
			end
		end
	end
	return built == PLOT_COUNT
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
