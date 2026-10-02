--!strict
-- WorldBootstrap.lua
-- Ensures:
-- - Arena spawn region covering 0..2000 x 0..2000
-- - Safe zone far away with a town centre
-- - 8 player plots arranged in a circle around the town centre
-- - Medieval-looking bases with walls, corner turrets, gate arch, a small
--   house shell, fire pit, banners, torches, and a path to town
--
-- Safe to re-run: it updates existing instances (moves/resizes them).
-- Tip: If you edit this module and require() doesn't reflect changes, use a
-- clone-require workaround or restart Studio to avoid require caching.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldBootstrap = {}

local VERSION = "WorldBootstrap v1.5 (eight player Sanctum plots)"
local DEBUG = true

local ZONES_FOLDER_NAME = "Zones"
local ARENA_MODEL_NAME = "ArenaWorld"
local SAFE_ZONE_MODEL_NAME = "SafeZoneWorld"

local ARENA_SPAWN_REGION_NAME = "ArenaSpawnRegion"
local SAFE_ZONE_REGION_NAME = "SafeZoneRegion"

local BASES_FOLDER_NAME = "Bases"
local DECOR_FOLDER_NAME = "Decor"
local BASE_COUNT = 8

-- Arena bounds: from (0,0,0) to (2000,0,2000).
local ARENA_CENTER = Vector3.new(1000, 60, 1000)
local ARENA_REGION_SIZE = Vector3.new(2000, 200, 2000)

-- Put the safe zone far away.
local SAFE_ZONE_CENTER = Vector3.new(3600, 40, 3600)
local SAFE_ZONE_REGION_SIZE = Vector3.new(1400, 240, 1400)

-- Ground
local SAFE_GROUND_SIZE = Vector3.new(1400, 18, 1400)
local SAFE_GROUND_Y = 0

-- Town centre
local TOWN_SQUARE_SIZE = Vector3.new(360, 6, 360)

-- Base ring around town centre
local BASE_RING_RADIUS = 520
local BASE_PLOT_SIZE = Vector3.new(260, 8, 260)
local SPAWN_PAD_SIZE = Vector3.new(16, 1, 16)

-- Plot walls / gate / path
local PLOT_WALL_HEIGHT = 18
local PLOT_WALL_THICKNESS = 6
local PLOT_GATE_WIDTH = 70
local GATE_ARCH_HEIGHT = 30
local GATE_ARCH_THICKNESS = 8

local PATH_WIDTH = 18
local PATH_THICKNESS = 2
local PATH_LENGTH = 260

-- Turrets
local TURRET_SIZE = Vector3.new(18, 30, 18)
local TURRET_CAP_SIZE = Vector3.new(22, 6, 22)

-- Tiny house shell (simple)
local HOUSE_FOOTPRINT = Vector3.new(95, 1, 75)
local HOUSE_WALL_HEIGHT = 22
local HOUSE_WALL_THICKNESS = 4
local HOUSE_ROOF_HEIGHT = 18

-- Fire pit
local FIRE_PIT_RADIUS = 10

local function debug_print(message: string)
	if DEBUG then
		print(message)
	end
end

local function debug_warn(message: string)
	if DEBUG then
		warn(message)
	end
end

-- Medieval vibe helpers
local function set_stone(part: BasePart)
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(110, 110, 120)
end

local function set_ground(part: BasePart)
	part.Material = Enum.Material.Cobblestone
	part.Color = Color3.fromRGB(125, 125, 125)
end

local function set_wood(part: BasePart)
	part.Material = Enum.Material.WoodPlanks
	part.Color = Color3.fromRGB(120, 90, 60)
end

local function set_dark_metal(part: BasePart)
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(55, 55, 60)
end

local function get_or_create_folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function get_or_create_model(parent: Instance, name: string): Model
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Model") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function ensure_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame
): Part
	local inst = parent:FindFirstChild(name)
	local part: Part

	if inst and inst:IsA("Part") then
		part = inst
	else
		if inst then
			inst:Destroy()
		end
		part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
	end

	part.Anchored = true
	part.Size = size
	part.CFrame = cframe

	return part
end

local function ensure_wedge_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame
): WedgePart
	local inst = parent:FindFirstChild(name)
	local wedge: WedgePart

	if inst and inst:IsA("WedgePart") then
		wedge = inst
	else
		if inst then
			inst:Destroy()
		end
		wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Parent = parent
	end

	wedge.Anchored = true
	wedge.Size = size
	wedge.CFrame = cframe

	return wedge
end

--[[
	Creates a non-Roblox-spawn marker for a player plot.

	The marker is used only as a controlled teleport destination. Using a
	real SpawnLocation here would allow Roblox to respawn a player inside
	another player's assigned plot.

	Args:
		parent (Instance): Plot model receiving the marker.
		name (string): Marker name.
		size (Vector3): Marker size.
		cframe (CFrame): Marker transform.

	Returns:
		Part: Plot arrival marker.
]]
local function ensure_spawn_marker(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame
): Part
	local inst = parent:FindFirstChild(name)
	local spawn: Part

	if inst and inst.ClassName == "Part" then
		spawn = inst :: Part
	else
		if inst then
			inst:Destroy()
		end

		spawn = Instance.new("Part")
		spawn.Name = name
		spawn.Parent = parent
	end

	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Size = size
	spawn.CFrame = cframe
	return spawn
end

local function ensure_region_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3
): Part
	local region = ensure_part(parent, name, size, cframe)
	region.CanCollide = false
	region.CanQuery = false
	region.CanTouch = false
	region.Transparency = 0.95
	region.Material = Enum.Material.ForceField
	region.Color = color
	return region
end

local function ensure_torch(parent: Instance, name: string, cframe: CFrame)
	local torch = get_or_create_model(parent, name)

	local post = ensure_part(torch, "Post", Vector3.new(2, 14, 2), cframe)
	post.CanCollide = true
	set_wood(post)

	local head = ensure_part(
		torch,
		"Head",
		Vector3.new(3, 3, 3),
		cframe * CFrame.new(0, 8, 0)
	)
	head.CanCollide = false
	set_dark_metal(head)

	local light = head:FindFirstChildOfClass("PointLight")
	if not light then
		light = Instance.new("PointLight")
		light.Parent = head
	end
	light.Brightness = 1.4
	light.Range = 22
	light.Color = Color3.fromRGB(255, 200, 120)

	torch:PivotTo(cframe)
end

local function ensure_banner(parent: Instance, name: string, cframe: CFrame)
	local banner = get_or_create_model(parent, name)

	local pole = ensure_part(banner, "Pole", Vector3.new(2, 26, 2), cframe)
	pole.CanCollide = true
	set_wood(pole)

	local cloth = ensure_part(
		banner,
		"Cloth",
		Vector3.new(1, 16, 10),
		cframe * CFrame.new(0, 2, -6)
	)
	cloth.CanCollide = false
	cloth.Material = Enum.Material.Fabric
	cloth.Color = Color3.fromRGB(120, 20, 30)

	banner:PivotTo(cframe)
end

local function ensure_path_to_town(parent: Instance, plot_cf: CFrame)
	-- Path extends "forward" toward the town (negative Z in plot local space)
	local path_cf = plot_cf * CFrame.new(
		0,
		SAFE_GROUND_Y + 0.2,
		-(BASE_PLOT_SIZE.Z * 0.5) - (PATH_LENGTH * 0.5)
	)

	local path = ensure_part(
		parent,
		"PathToTown",
		Vector3.new(PATH_WIDTH, PATH_THICKNESS, PATH_LENGTH),
		path_cf
	)
	path.CanCollide = false
	set_ground(path)
end

local function ensure_plot_walls_and_gate(
	parent: Instance,
	plot_cf: CFrame,
	plot_size: Vector3
)
	local half_x = plot_size.X * 0.5
	local half_z = plot_size.Z * 0.5
	local wall_y = SAFE_GROUND_Y + (PLOT_WALL_HEIGHT * 0.5)

	local _, yaw, _ = plot_cf:ToEulerAnglesYXZ()

	local gate_half = PLOT_GATE_WIDTH * 0.5
	local side_len = plot_size.X
	local depth_len = plot_size.Z

	local function wall_part(name: string, size: Vector3, local_pos: Vector3)
		local world_pos = (plot_cf * CFrame.new(local_pos)).Position
		local part = ensure_part(
			parent,
			name,
			size,
			CFrame.new(world_pos.X, wall_y, world_pos.Z) * CFrame.Angles(0, yaw, 0)
		)
		set_stone(part)
		part.CanCollide = true
	end

	-- Back wall
	wall_part(
		"Wall_Back",
		Vector3.new(side_len, PLOT_WALL_HEIGHT, PLOT_WALL_THICKNESS),
		Vector3.new(0, 0, half_z - (PLOT_WALL_THICKNESS * 0.5))
	)

	-- Left / Right walls
	wall_part(
		"Wall_Left",
		Vector3.new(PLOT_WALL_THICKNESS, PLOT_WALL_HEIGHT, depth_len),
		Vector3.new(-half_x + (PLOT_WALL_THICKNESS * 0.5), 0, 0)
	)

	wall_part(
		"Wall_Right",
		Vector3.new(PLOT_WALL_THICKNESS, PLOT_WALL_HEIGHT, depth_len),
		Vector3.new(half_x - (PLOT_WALL_THICKNESS * 0.5), 0, 0)
	)

	-- Front wall split for gate opening (front is -Z in plot local space)
	local segment_len = (side_len - PLOT_GATE_WIDTH) * 0.5
	if segment_len > 10 then
		wall_part(
			"Wall_Front_Left",
			Vector3.new(segment_len, PLOT_WALL_HEIGHT, PLOT_WALL_THICKNESS),
			Vector3.new(
				-(gate_half + (segment_len * 0.5)),
				0,
				-half_z + (PLOT_WALL_THICKNESS * 0.5)
			)
		)

		wall_part(
			"Wall_Front_Right",
			Vector3.new(segment_len, PLOT_WALL_HEIGHT, PLOT_WALL_THICKNESS),
			Vector3.new(
				(gate_half + (segment_len * 0.5)),
				0,
				-half_z + (PLOT_WALL_THICKNESS * 0.5)
			)
		)
	end

	-- Gate posts (wood)
	local post_height = 28
	local post_size = Vector3.new(7, post_height, 7)

	local post_left_cf = plot_cf
		* CFrame.new(-gate_half, SAFE_GROUND_Y + (post_height * 0.5), -half_z + 4)
	local post_right_cf = plot_cf
		* CFrame.new(gate_half, SAFE_GROUND_Y + (post_height * 0.5), -half_z + 4)

	local gate_left = ensure_part(
		parent,
		"GatePost_Left",
		post_size,
		post_left_cf
	)
	gate_left.CanCollide = true
	set_wood(gate_left)

	local gate_right = ensure_part(
		parent,
		"GatePost_Right",
		post_size,
		post_right_cf
	)
	gate_right.CanCollide = true
	set_wood(gate_right)

	-- Stone arch above the gate
	local arch_cf = plot_cf * CFrame.new(
		0,
		SAFE_GROUND_Y + (GATE_ARCH_HEIGHT),
		-half_z + 4
	)
	local arch = ensure_part(
		parent,
		"GateArch",
		Vector3.new(PLOT_GATE_WIDTH + 18, GATE_ARCH_THICKNESS, PLOT_WALL_THICKNESS),
		arch_cf
	)
	arch.CanCollide = true
	set_stone(arch)

	-- Simple "gate" slab (metal)
	local gate_cf = plot_cf * CFrame.new(
		0,
		SAFE_GROUND_Y + (post_height * 0.5) - 2,
		-half_z + 6
	)
	local gate = ensure_part(
		parent,
		"GateDoor",
		Vector3.new(PLOT_GATE_WIDTH - 10, post_height - 10, 2),
		gate_cf
	)
	gate.CanCollide = false
	set_dark_metal(gate)
	gate.Transparency = 0.15
end

local function ensure_corner_turrets(parent: Instance, plot_cf: CFrame)
	local half_x = BASE_PLOT_SIZE.X * 0.5
	local half_z = BASE_PLOT_SIZE.Z * 0.5

	local turret_y = SAFE_GROUND_Y + (TURRET_SIZE.Y * 0.5)

	local offsets = {
		{ name = "Turret_FL", pos = Vector3.new(-half_x, 0, -half_z) },
		{ name = "Turret_FR", pos = Vector3.new(half_x, 0, -half_z) },
		{ name = "Turret_BL", pos = Vector3.new(-half_x, 0, half_z) },
		{ name = "Turret_BR", pos = Vector3.new(half_x, 0, half_z) },
	}

	local _, yaw, _ = plot_cf:ToEulerAnglesYXZ()

	for _, t in ipairs(offsets) do
		local world_pos = (plot_cf * CFrame.new(t.pos)).Position
		local turret_cf = CFrame.new(world_pos.X, turret_y, world_pos.Z)
			* CFrame.Angles(0, yaw, 0)

		local turret = ensure_part(parent, t.name, TURRET_SIZE, turret_cf)
		turret.CanCollide = true
		set_stone(turret)

		local cap_cf = CFrame.new(world_pos.X, SAFE_GROUND_Y + TURRET_SIZE.Y + 3,
			world_pos.Z) * CFrame.Angles(0, yaw, 0)
		local cap = ensure_part(parent, t.name .. "_Cap", TURRET_CAP_SIZE, cap_cf)
		cap.CanCollide = true
		cap.Material = Enum.Material.SmoothPlastic
		cap.Color = Color3.fromRGB(70, 70, 75)
	end
end

local function ensure_small_house(parent: Instance, plot_cf: CFrame)
	-- Place the house behind the spawn (toward the back wall, +Z local),
	-- and keep the front facing the town (-Z local).
	local base_y = SAFE_GROUND_Y + 0.6
	local house_cf = plot_cf * CFrame.new(0, base_y, 55)

	local floor = ensure_part(parent, "House_Floor", HOUSE_FOOTPRINT, house_cf)
	floor.CanCollide = true
	set_wood(floor)

	local half_x = HOUSE_FOOTPRINT.X * 0.5
	local half_z = HOUSE_FOOTPRINT.Z * 0.5
	local wall_y = SAFE_GROUND_Y + (HOUSE_WALL_HEIGHT * 0.5) + 1.2

	local _, yaw, _ = plot_cf:ToEulerAnglesYXZ()

	local function wall(name: string, size: Vector3, local_pos: Vector3)
		local world_pos = (plot_cf * CFrame.new(local_pos)).Position
		local cf = CFrame.new(
			world_pos.X,
			wall_y,
			world_pos.Z
		) * CFrame.Angles(0, yaw, 0)
		local w = ensure_part(parent, name, size, cf)
		w.CanCollide = true
		set_wood(w)
		w.Color = Color3.fromRGB(105, 80, 55)
	end

	local wall_side = Vector3.new(HOUSE_WALL_THICKNESS, HOUSE_WALL_HEIGHT,
		HOUSE_FOOTPRINT.Z)
	local wall_front = Vector3.new(HOUSE_FOOTPRINT.X, HOUSE_WALL_HEIGHT,
		HOUSE_WALL_THICKNESS)

	-- Left/Right
	wall("House_Wall_L", wall_side, Vector3.new(-half_x, 0, 55))
	wall("House_Wall_R", wall_side, Vector3.new(half_x, 0, 55))

	-- Back wall
	wall("House_Wall_Back", wall_front, Vector3.new(0, 0, 55 + half_z))

	-- Front wall split (tiny doorway)
	local door_width = 20
	local seg_len = (HOUSE_FOOTPRINT.X - door_width) * 0.5
	if seg_len > 10 then
		wall("House_Wall_Front_L",
			Vector3.new(seg_len, HOUSE_WALL_HEIGHT, HOUSE_WALL_THICKNESS),
			Vector3.new(-(door_width * 0.5 + seg_len * 0.5), 0, 55 - half_z))
		wall("House_Wall_Front_R",
			Vector3.new(seg_len, HOUSE_WALL_HEIGHT, HOUSE_WALL_THICKNESS),
			Vector3.new((door_width * 0.5 + seg_len * 0.5), 0, 55 - half_z))
	end

	-- Roof wedge (simple)
	local roof_size = Vector3.new(HOUSE_FOOTPRINT.X + 18, HOUSE_ROOF_HEIGHT,
		HOUSE_FOOTPRINT.Z + 18)

	local roof_cf = plot_cf
		* CFrame.new(0, SAFE_GROUND_Y + HOUSE_WALL_HEIGHT + 12, 55)
		* CFrame.Angles(0, 0, math.rad(180))

	local roof = ensure_wedge_part(parent, "House_Roof", roof_size, roof_cf)
	roof.CanCollide = true
	roof.Material = Enum.Material.SmoothPlastic
	roof.Color = Color3.fromRGB(80, 80, 85)
end

local function ensure_fire_pit(parent: Instance, plot_cf: CFrame)
	local pit_cf = plot_cf * CFrame.new(0, SAFE_GROUND_Y + 1, 10)
	local pit = ensure_part(parent, "FirePit", Vector3.new(FIRE_PIT_RADIUS * 2, 2,
		FIRE_PIT_RADIUS * 2), pit_cf)
	pit.CanCollide = false
	pit.Material = Enum.Material.Rock
	pit.Color = Color3.fromRGB(95, 95, 100)

	local fire = pit:FindFirstChildOfClass("Fire")
	if not fire then
		fire = Instance.new("Fire")
		fire.Parent = pit
	end
	fire.Heat = 5
	fire.Size = 6

	local glow = pit:FindFirstChildOfClass("PointLight")
	if not glow then
		glow = Instance.new("PointLight")
		glow.Parent = pit
	end
	glow.Brightness = 1.2
	glow.Range = 18
	glow.Color = Color3.fromRGB(255, 190, 120)
end

local function create_arena(zones_folder: Folder)
	local arena_model = get_or_create_model(zones_folder, ARENA_MODEL_NAME)

	ensure_region_part(
		arena_model,
		ARENA_SPAWN_REGION_NAME,
		ARENA_REGION_SIZE,
		CFrame.new(ARENA_CENTER),
		Color3.fromRGB(120, 170, 255)
	)

	-- The later Rojo source intentionally did not include Workspace, while the
	-- older Studio place contained an ArenaFloor. Keep a simple fallback floor
	-- in the recovered project so the arena is playable until authored terrain
	-- is restored. Real terrain above this floor will naturally take priority.
	local floor = ensure_part(
		arena_model,
		"ArenaFloor",
		Vector3.new(2000, 2, 2000),
		CFrame.new(ARENA_CENTER.X, -1, ARENA_CENTER.Z)
	)
	floor.CanCollide = true
	floor.Material = Enum.Material.Grass
	floor.Color = Color3.fromRGB(88, 120, 72)

	-- Shared placement bounds used by NPC and biome spawning.
	local bounds = ensure_part(
		arena_model,
		"SpawnBounds",
		Vector3.new(1960, 20, 1960),
		CFrame.new(ARENA_CENTER.X, 10, ARENA_CENTER.Z)
	)
	bounds.CanCollide = false
	bounds.CanQuery = false
	bounds.CanTouch = false
	bounds.Transparency = 1
end

local function create_safe_zone(zones_folder: Folder)
	local safe_model = get_or_create_model(zones_folder, SAFE_ZONE_MODEL_NAME)

	ensure_region_part(
		safe_model,
		SAFE_ZONE_REGION_NAME,
		SAFE_ZONE_REGION_SIZE,
		CFrame.new(SAFE_ZONE_CENTER),
		Color3.fromRGB(70, 255, 160)
	)

	-- Ground baseplate
	local ground_cf = CFrame.new(
		SAFE_ZONE_CENTER.X,
		SAFE_GROUND_Y - (SAFE_GROUND_SIZE.Y * 0.5),
		SAFE_ZONE_CENTER.Z
	)
	local ground = ensure_part(
		safe_model,
		"SafeZoneGround",
		SAFE_GROUND_SIZE,
		ground_cf
	)
	ground.CanCollide = true
	set_ground(ground)

	-- Town centre square
	local square_cf = CFrame.new(
		SAFE_ZONE_CENTER.X,
		SAFE_GROUND_Y + 3,
		SAFE_ZONE_CENTER.Z
	)
	local square = ensure_part(
		safe_model,
		"TownSquare",
		TOWN_SQUARE_SIZE,
		square_cf
	)
	square.CanCollide = true
	set_ground(square)

	-- Town props
	ensure_torch(
		safe_model,
		"SquareTorch_NW",
		CFrame.new(
			SAFE_ZONE_CENTER.X - 150,
			SAFE_GROUND_Y + 1,
			SAFE_ZONE_CENTER.Z - 150
		)
	)
	ensure_torch(
		safe_model,
		"SquareTorch_NE",
		CFrame.new(
			SAFE_ZONE_CENTER.X + 150,
			SAFE_GROUND_Y + 1,
			SAFE_ZONE_CENTER.Z - 150
		)
	)
	ensure_torch(
		safe_model,
		"SquareTorch_SW",
		CFrame.new(
			SAFE_ZONE_CENTER.X - 150,
			SAFE_GROUND_Y + 1,
			SAFE_ZONE_CENTER.Z + 150
		)
	)
	ensure_torch(
		safe_model,
		"SquareTorch_SE",
		CFrame.new(
			SAFE_ZONE_CENTER.X + 150,
			SAFE_GROUND_Y + 1,
			SAFE_ZONE_CENTER.Z + 150
		)
	)

	ensure_banner(
		safe_model,
		"TownBanner",
		CFrame.new(SAFE_ZONE_CENTER.X, SAFE_GROUND_Y + 1, SAFE_ZONE_CENTER.Z - 190)
	)

	-- Bases around the town centre (circular)
	local bases_folder = get_or_create_folder(safe_model, BASES_FOLDER_NAME)

	for i = 1, BASE_COUNT do
		local base_name = ("Base%02d"):format(i)
		local base_model = get_or_create_model(bases_folder, base_name)
		base_model:SetAttribute("PlotIndex", i)
		base_model:SetAttribute("PlotOwnerUserId", 0)
		base_model:SetAttribute("PlotOwnerName", "")
		base_model:SetAttribute("PlotOccupied", false)

		local angle = (math.pi * 2) * ((i - 1) / BASE_COUNT)
		local x = SAFE_ZONE_CENTER.X + (math.cos(angle) * BASE_RING_RADIUS)
		local z = SAFE_ZONE_CENTER.Z + (math.sin(angle) * BASE_RING_RADIUS)

		-- Make the plot face the town centre *guaranteed*.
		-- In Roblox, the CFrame's LookVector points along -Z, so this makes the
		-- "front" (gate side) face toward the town.
		local plot_pos = Vector3.new(x, SAFE_GROUND_Y + (BASE_PLOT_SIZE.Y * 0.5), z)
		local look_pos = Vector3.new(
			SAFE_ZONE_CENTER.X,
			plot_pos.Y,
			SAFE_ZONE_CENTER.Z
		)
		local plot_cf = CFrame.lookAt(plot_pos, look_pos)

		local plot = ensure_part(base_model, "Plot", BASE_PLOT_SIZE, plot_cf)
		plot.CanCollide = true
		plot.Material = Enum.Material.Cobblestone
		plot.Color = Color3.fromRGB(135, 135, 140)

		-- Spawn pad slightly closer to town (front of plot is -Z local).
		-- Place it above the plot rather than inside the 8-stud-thick slab.
		local spawn_y =
			(BASE_PLOT_SIZE.Y * 0.5) + (SPAWN_PAD_SIZE.Y * 0.5) + 0.1
		local spawn_cf = plot_cf * CFrame.new(0, spawn_y, -80)
		local spawn = ensure_spawn_marker(
			base_model,
			"Spawn",
			SPAWN_PAD_SIZE,
			spawn_cf
		)
		spawn:SetAttribute("SanctumPlotSpawn", true)
		spawn:SetAttribute("PlotIndex", i)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.Color = Color3.fromRGB(45, 160, 90)

		-- Decor folder to keep things tidy and avoid collisions
		local decor = get_or_create_folder(base_model, DECOR_FOLDER_NAME)

		-- Walls, gate, turrets
		ensure_plot_walls_and_gate(decor, plot_cf, BASE_PLOT_SIZE)
		ensure_corner_turrets(decor, plot_cf)

		-- Path to town
		ensure_path_to_town(decor, plot_cf)

		-- Gate banners (anchored near the gate)
		ensure_banner(
			decor,
			"GateBanner_Left",
			plot_cf * CFrame.new(-(PLOT_GATE_WIDTH * 0.5), SAFE_GROUND_Y + 1,
				-(BASE_PLOT_SIZE.Z * 0.5) + 10)
		)
		ensure_banner(
			decor,
			"GateBanner_Right",
			plot_cf * CFrame.new((PLOT_GATE_WIDTH * 0.5), SAFE_GROUND_Y + 1,
				-(BASE_PLOT_SIZE.Z * 0.5) + 10)
		)

		-- Plot torches near spawn
		ensure_torch(decor, "TorchA", spawn_cf * CFrame.new(-30, 0, 18))
		ensure_torch(decor, "TorchB", spawn_cf * CFrame.new(30, 0, 18))

		-- A small house shell inside the base
		ensure_small_house(decor, plot_cf)

		-- Fire pit near the centre of the plot
		ensure_fire_pit(decor, plot_cf)

		if DEBUG then
			debug_print(
				("[WorldBootstrap] Updated %s"):format(
					base_model:GetFullName()
				)
			)
		end
	end
end

local function ensure_world_objects()
	local zones_folder = get_or_create_folder(Workspace, ZONES_FOLDER_NAME)

	create_arena(zones_folder)
	create_safe_zone(zones_folder)

	print(("[WorldBootstrap] Done. %s"):format(VERSION))
end

function WorldBootstrap.run()
	print(("[WorldBootstrap] Running. %s"):format(VERSION))

	if not RunService:IsStudio() then
		warn("[WorldBootstrap] Refusing to run outside Studio.")
		return
	end

	local zones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if zones then
		debug_print(
			("[WorldBootstrap] Zones folder: %s"):format(
				zones:GetFullName()
			)
		)
	end

	ensure_world_objects()
end

return WorldBootstrap
