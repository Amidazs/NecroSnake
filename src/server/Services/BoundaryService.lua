--!strict
-- src/server/Services/BoundaryService.lua

local Workspace = game:GetService("Workspace")

local BoundaryService = {}
BoundaryService.__index = BoundaryService

-- Make the arena feel bigger.
local HALF_SIZE = 260
local WALL_HEIGHT = 120
local WALL_THICKNESS = 8

function BoundaryService.new()
    local self = setmetatable({}, BoundaryService)
    return self
end

local function make_wall(name: string, size: Vector3, cframe: CFrame)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.CanCollide = true
    p.Transparency = 1
    p.Size = size
    p.CFrame = cframe
    p.Parent = Workspace
    return p
end

function BoundaryService:build()
    local folder = Workspace:FindFirstChild("Boundaries")
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = "Boundaries"
        folder.Parent = Workspace
    end

    folder:ClearAllChildren()

    local x = HALF_SIZE
    local z = HALF_SIZE
    local y = WALL_HEIGHT / 2

    make_wall("Wall_N", Vector3.new(x * 2, WALL_HEIGHT, WALL_THICKNESS),
        CFrame.new(0, y, -z), folder)

    make_wall("Wall_S", Vector3.new(x * 2, WALL_HEIGHT, WALL_THICKNESS),
        CFrame.new(0, y, z), folder)

    make_wall("Wall_W", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, z * 2),
        CFrame.new(-x, y, 0), folder)

    make_wall("Wall_E", Vector3.new(WALL_THICKNESS, WALL_HEIGHT, z * 2),
        CFrame.new(x, y, 0), folder)

    print(("[BoundaryService] Built invisible walls. HALF_SIZE=%d"):format(HALF_SIZE))
end

-- at the end of BoundaryService.lua, before `return BoundaryService`
function BoundaryService.ClampToArena(config, pos: Vector3)
    -- determine arena bounds from either our own constant or the passed config
    local half
    if config and config.Arena and config.Arena.HalfSize then
        half = config.Arena.HalfSize
    else
        -- fallback to HALF_SIZE used for wall building
        half = Vector3.new(HALF_SIZE, 0, HALF_SIZE)
    end

    return Vector3.new(
        math.clamp(pos.X, -half.X, half.X),
        pos.Y,
        math.clamp(pos.Z, -half.Z, half.Z)
    )
end

return BoundaryService