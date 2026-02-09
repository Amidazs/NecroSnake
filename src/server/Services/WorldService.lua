local WorldService = {}

local Workspace = game:GetService("Workspace")

local function ensure_folder(parent, name)
    local existing = parent:FindFirstChild(name)
    if existing and existing:IsA("Folder") then
        return existing
    end
    if existing then
        existing:Destroy()
    end
    local f = Instance.new("Folder")
    f.Name = name
    f.Parent = parent
    return f
end

function WorldService.EnsureWorld(game_config)
    local world = ensure_folder(Workspace, game_config.World.WorldName)
    world:SetAttribute("NecroSnake", true)

    local arena = ensure_folder(world, game_config.World.ArenaName)
    local units = ensure_folder(world, game_config.World.UnitsName)
    local leaders = ensure_folder(world, game_config.World.LeadersName)

    arena:SetAttribute("NecroSnake", true)
    units:SetAttribute("NecroSnake", true)
    leaders:SetAttribute("NecroSnake", true)

    return { World = world, Arena = arena, Units = units, Leaders = leaders }
end

return WorldService