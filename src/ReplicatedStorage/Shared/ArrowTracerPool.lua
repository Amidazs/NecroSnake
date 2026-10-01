--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ArrowTracerPool = {}

local FOLDER_NAME = "ProjectileEffects"
local MAX_POOL_SIZE = 192
local ARROW_SIZE = Vector3.new(0.12, 0.12, 1.7)
local ARROW_COLOR = Color3.fromRGB(117, 79, 44)

local pooled_arrows: { BasePart } = {}
local active_count = 0

local function ensure_folder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace
	return folder
end
local function create_arrow(): Part
	local arrow = Instance.new("Part")
	arrow.Name = "NecroArrowTracer"
	arrow.Size = ARROW_SIZE
	arrow.Color = ARROW_COLOR
	arrow.Material = Enum.Material.Wood
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanTouch = false
	arrow.CanQuery = false
	arrow.CastShadow = false
	arrow.Transparency = 1
	arrow.CFrame = CFrame.new(0, -10000, 0)
	return arrow
end

local function acquire_arrow(): Part
	local arrow = table.remove(pooled_arrows)
	if not arrow then
		arrow = create_arrow()
	end

	local generation = arrow:GetAttribute("TracerGeneration")
	if typeof(generation) ~= "number" then
		generation = 0
	end
	arrow:SetAttribute("TracerGeneration", generation + 1)
	arrow.Transparency = 0
	arrow.Parent = ensure_folder()
	active_count += 1
	return arrow
end

local function release_arrow(arrow: Part, generation: number)
	if arrow.Parent == nil then
		active_count = math.max(0, active_count - 1)
		return
	end
	if arrow:GetAttribute("TracerGeneration") ~= generation then
		return
	end

	active_count = math.max(0, active_count - 1)
	arrow.Transparency = 1
	arrow.CFrame = CFrame.new(0, -10000, 0)

	if #pooled_arrows >= MAX_POOL_SIZE then
		arrow:Destroy()
		return
	end
	table.insert(pooled_arrows, arrow)
end
function ArrowTracerPool.emit(from_root: BasePart, target_root: BasePart)
	local start_pos = from_root.Position + Vector3.new(0, 1.5, 0)
	local end_pos = target_root.Position + Vector3.new(0, 1.2, 0)
	local delta = end_pos - start_pos
	if delta.Magnitude < 0.1 then
		return
	end

	local arrow = acquire_arrow()
	local generation = arrow:GetAttribute("TracerGeneration") :: number
	arrow.CFrame = CFrame.lookAt(start_pos, end_pos)

	local travel_time = math.clamp(delta.Magnitude / 85, 0.12, 0.42)
	local tween = TweenService:Create(
		arrow,
		TweenInfo.new(travel_time, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(end_pos, end_pos + delta.Unit) }
	)
	tween:Play()

	task.delay(travel_time + 0.08, function()
		release_arrow(arrow, generation)
	end)
end
function ArrowTracerPool.get_stats(): (number, number)
	return active_count, #pooled_arrows
end

return ArrowTracerPool
