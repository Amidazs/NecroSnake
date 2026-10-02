--!strict
-- YasusBiomeSpawner.server.lua
-- Spawns stylized trees + bushes from the Yasu's pack across Terrain.
-- - Uses SpawnBounds (if present) to define X/Z placement bounds.
-- - Raycasts down to Terrain and rejects steep slopes, high elevations,
--   and water.
-- - Applies random yaw and normalizes size to a target height range.
-- - Anchors all parts; only trunks collide (blocks movement without snagging).

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local PACK_FOLDER_NAME = "Yasu's_Stylized_Tree_Pack"

local BIOME_FOLDER_NAME = "Biomes"
local FOLIAGE_FOLDER_NAME = "Foliage"

local MAX_PLACEMENTS = 300
local MIN_SPACING = 18

local MIRE_MIN_X = 180
local MIRE_MAX_X = 820
local MIRE_MIN_Z = 1180
local MIRE_MAX_Z = 1820
local MIRE_ROUTE_SUM = 2000
local MIRE_ROUTE_CLEARANCE = 100

local RAY_START_HEIGHT = 800
local RAY_DISTANCE = 2200
local SURFACE_OFFSET = 0.5

local SLOPE_MAX_DEGREES = 28

-- Prevent spawns above a "natural" elevation (adjust to taste).
local MAX_SPAWN_Y = 120

-- Normalize each spawned model to a target height range.
local TARGET_HEIGHT_MIN = 18
local TARGET_HEIGHT_MAX = 38

-- If a template is taller than this before scaling, skip it entirely.
local MAX_ALLOWED_TEMPLATE_HEIGHT = 120

-- Strong water detection using Terrain voxels around the hit point.
local WATER_CHECK_HALF_SIZE = 2
local WATER_CHECK_RESOLUTION = 4

local FOLIAGE_PART_MATERIALS = {
	[Enum.Material.Grass] = true,
	[Enum.Material.LeafyGrass] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
}

-- Part-name heuristics for collisions.
local TRUNK_NAME_KEYWORDS = {"trunk", "stem", "root"}
local NON_TRUNK_KEYWORDS = {"canopy", "leaf", "leaves", "branch", "branches"}

local function get_or_create_folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function clear_children(folder: Folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

local function strip_scripts(root: Instance)
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Script")
			or inst:IsA("LocalScript")
			or inst:IsA("ModuleScript")
		then
			inst:Destroy()
		end
	end
end

local function ensure_primary_part(model: Model)
	if model.PrimaryPart then
		return
	end

	local part = model:FindFirstChildWhichIsA("BasePart", true)
	if part then
		model.PrimaryPart = part
	end
end

local function contains_any_keyword(
	name_lower: string,
	keywords: { string }
): boolean
	for _, kw in ipairs(keywords) do
		if string.find(name_lower, kw, 1, true) then
			return true
		end
	end
	return false
end

local function is_trunk_part(part: BasePart): boolean
	local name_lower = string.lower(part.Name)

	-- If a part is explicitly labeled canopy/leaves/branches, treat as non-trunk.
	if contains_any_keyword(name_lower, NON_TRUNK_KEYWORDS) then
		return false
	end

	-- Otherwise, treat as trunk if it matches trunk-ish keywords.
	if contains_any_keyword(name_lower, TRUNK_NAME_KEYWORDS) then
		return true
	end

	-- Default: non-trunk (prevents weird invisible collisions).
	return false
end

local function set_foliage_physics(model: Model)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanQuery = true
			inst.CanTouch = true
			inst.CanCollide = is_trunk_part(inst)
		end
	end
end

--[[
	Restricts the legacy tree pack to the living Mirebound biome.

	Args:
		x (number): Candidate world X coordinate.
		z (number): Candidate world Z coordinate.

	Returns:
		boolean: True when authored foliage is allowed here.
]]
local function is_foliage_position_allowed(
	x: number,
	z: number
): boolean
	local inside_mire = x >= MIRE_MIN_X
		and x <= MIRE_MAX_X
		and z >= MIRE_MIN_Z
		and z <= MIRE_MAX_Z
	if not inside_mire then
		return false
	end

	local route_distance = math.abs(
		(x + z) - MIRE_ROUTE_SUM
	)
	return route_distance >= MIRE_ROUTE_CLEARANCE
end

local function get_bounds_from_spawn_bounds(): (number, number, number, number)
	local bounds = Workspace:FindFirstChild("SpawnBounds", true)
	if bounds and bounds:IsA("BasePart") then
		local half_x = bounds.Size.X * 0.5
		local half_z = bounds.Size.Z * 0.5

		local min_x = bounds.Position.X - half_x
		local max_x = bounds.Position.X + half_x
		local min_z = bounds.Position.Z - half_z
		local max_z = bounds.Position.Z + half_z

		return min_x, max_x, min_z, max_z
	end

	-- Fallback bounds if SpawnBounds doesn't exist.
	return -512, 512, -512, 512
end

local function too_close(
	points: { Vector3 },
	candidate: Vector3,
	min_spacing: number
): boolean
	local min_sq = min_spacing * min_spacing
	for _, p in ipairs(points) do
		local dx = p.X - candidate.X
		local dz = p.Z - candidate.Z
		local d2 = (dx * dx) + (dz * dz)
		if d2 < min_sq then
			return true
		end
	end
	return false
end

local function slope_ok(normal: Vector3): boolean
	local up = Vector3.new(0, 1, 0)
	local dot = math.clamp(normal:Dot(up), -1, 1)
	local angle = math.deg(math.acos(dot))
	return angle <= SLOPE_MAX_DEGREES
end

local function is_water_at_position(pos: Vector3): boolean
	local terrain = Workspace.Terrain

	local r = WATER_CHECK_HALF_SIZE
	local min = pos - Vector3.new(r, r, r)
	local max = pos + Vector3.new(r, r, r)

	local region = Region3.new(min, max):ExpandToGrid(WATER_CHECK_RESOLUTION)
	local materials, _ = terrain:ReadVoxels(region, WATER_CHECK_RESOLUTION)

	for x = 1, materials.Size.X do
		for y = 1, materials.Size.Y do
			for z = 1, materials.Size.Z do
				if materials[x][y][z] == Enum.Material.Water then
					return true
				end
			end
		end
	end

	return false
end

local function raycast_to_terrain(
	x: number,
	z: number,
	blacklist: { Instance }
): RaycastResult?
	local origin = Vector3.new(x, RAY_START_HEIGHT, z)
	local direction = Vector3.new(0, -RAY_DISTANCE, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = blacklist
	params.IgnoreWater = true

	local hit = Workspace:Raycast(origin, direction, params)
	if not hit then
		return nil
	end

	local hit_terrain = hit.Instance:IsA("Terrain")
	local hit_floor = hit.Instance:IsA("BasePart") and hit.Instance.CanCollide
	if not hit_terrain and not hit_floor then
		return nil
	end

	if hit_floor
		and hit.Instance:IsA("BasePart")
		and not FOLIAGE_PART_MATERIALS[hit.Instance.Material]
	then
		return nil
	end

	if hit.Position.Y > MAX_SPAWN_Y then
		return nil
	end

	if not slope_ok(hit.Normal) then
		return nil
	end

	-- Terrain needs explicit water checks. A collidable fallback floor does not.
	if hit_terrain then
		if hit.Material == Enum.Material.Water then
			return nil
		end

		if is_water_at_position(hit.Position) then
			return nil
		end
	end

	return hit
end

local function get_pack_models_folder(
	pack: Instance,
	folder_name: string
): Folder?
	local container = pack:FindFirstChild(folder_name)
	if not (container and container:IsA("Folder")) then
		return nil
	end

	local models = container:FindFirstChild("Models")
	if models and models:IsA("Folder") then
		return models
	end

	return nil
end

local function collect_templates_from_folders(folders: {Folder}): {Model}
	local templates: {Model} = {}

	for _, folder in ipairs(folders) do
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") then
				if child:FindFirstChildWhichIsA("BasePart", true) then
					table.insert(templates, child)
				end
			end
		end
	end

	return templates
end

local function pick_random_template(templates: {Model}): Model?
	if #templates == 0 then
		return nil
	end
	return templates[math.random(1, #templates)]
end

local function get_model_height(model: Model): number
	return model:GetExtentsSize().Y
end

local function get_scale_for_target_height(model: Model): number?
	local current_h = get_model_height(model)
	if current_h <= 0 then
		return nil
	end

	if current_h > MAX_ALLOWED_TEMPLATE_HEIGHT then
		return nil
	end

	local target_h = TARGET_HEIGHT_MIN
		+ (math.random() * (TARGET_HEIGHT_MAX - TARGET_HEIGHT_MIN))

	return target_h / current_h
end

local function spawn_one(
	templates: {Model},
	parent: Folder,
	pos: Vector3,
	yaw_deg: number
)
	local template = pick_random_template(templates)
	if not template then
		return
	end

	local model = template:Clone()
	strip_scripts(model)
	ensure_primary_part(model)
	set_foliage_physics(model)

	local scale = get_scale_for_target_height(model)
	if not scale then
		model:Destroy()
		return
	end

	model.Parent = parent

	local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw_deg), 0)
	model:PivotTo(cf)

	pcall(function()
		model:ScaleTo(scale)
	end)
end

local function main()
	local pack = ServerStorage:FindFirstChild(PACK_FOLDER_NAME)
	if not pack then
		warn(
			("[YasusBiomeSpawner] Pack not found: ServerStorage.%s")
				:format(PACK_FOLDER_NAME)
		)
		return
	end

	strip_scripts(pack)

	local folders: {Folder} = {}

	local trees_models = get_pack_models_folder(pack, "Models_Trees")
	if trees_models then
		table.insert(folders, trees_models)
	end

	local bushes_models = get_pack_models_folder(pack, "Models_Bushes")
	if bushes_models then
		table.insert(folders, bushes_models)
	end

	if #folders == 0 then
		warn("[YasusBiomeSpawner] No Models folders found for trees or bushes.")
		return
	end

	local templates = collect_templates_from_folders(folders)
	if #templates == 0 then
		warn("[YasusBiomeSpawner] Found folders but no Model templates with parts.")
		return
	end

	local biome_root = get_or_create_folder(Workspace, BIOME_FOLDER_NAME)
	local foliage_folder = get_or_create_folder(biome_root, FOLIAGE_FOLDER_NAME)

	clear_children(foliage_folder)

	local min_x, max_x, min_z, max_z = get_bounds_from_spawn_bounds()
	local placed: {Vector3} = {}

	local blacklist = {biome_root}

	local attempts = 0
	local max_attempts = MAX_PLACEMENTS * 60

	while #placed < MAX_PLACEMENTS and attempts < max_attempts do
		attempts += 1

		local x = min_x + (math.random() * (max_x - min_x))
		local z = min_z + (math.random() * (max_z - min_z))

		if not is_foliage_position_allowed(x, z) then
			continue
		end

		local hit = raycast_to_terrain(x, z, blacklist)
		if hit then
			local candidate = Vector3.new(x, hit.Position.Y + SURFACE_OFFSET, z)
			if not too_close(placed, candidate, MIN_SPACING) then
				table.insert(placed, candidate)

				local yaw = math.random() * 360
				spawn_one(templates, foliage_folder, candidate, yaw)
			end
		end
	end

	local summary = (
		"[YasusBiomeSpawner] Templates=%d | Spawned=%d | "
			.. "Attempts=%d | MaxY=%d | TargetH=[%d,%d]"
	):format(
		#templates,
		#placed,
		attempts,
		MAX_SPAWN_Y,
		TARGET_HEIGHT_MIN,
		TARGET_HEIGHT_MAX
	)
	print(summary)
end

main()
