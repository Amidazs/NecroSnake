local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WorldBootstrapService = {}

local WORLD_NAME = "NecromancerMVP_World"
local UNITS_NAME = "Units"
local LEADERS_NAME = "Leaders"

local function get_or_create_folder(parent, name)
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

local function ensure_world()
    local world = Workspace:FindFirstChild(WORLD_NAME)
    if not world then
        world = Instance.new("Folder")
        world.Name = WORLD_NAME
        world.Parent = Workspace
    end

    local units = get_or_create_folder(world, UNITS_NAME)
    local leaders = get_or_create_folder(world, LEADERS_NAME)

    return world, units, leaders
end

local function create_unit_model(name, owner_id, position)
    local model = Instance.new("Model")
    model.Name = name

    local hrp = Instance.new("Part")
    hrp.Name = "HumanoidRootPart"
    hrp.Size = Vector3.new(2, 2, 2)
    hrp.Anchored = false
    hrp.CanCollide = true
    hrp.Position = position
    hrp.Parent = model

    hrp:SetAttribute("OwnerId", owner_id)

    local humanoid = Instance.new("Humanoid")
    humanoid.WalkSpeed = 16
    humanoid.Parent = model

    model.PrimaryPart = hrp

    return model
end

local function spawn_debug_units_for_player(player, units_folder)
    local base_pos = Vector3.new(0, 5, 0)

    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        base_pos = player.Character.HumanoidRootPart.Position + Vector3.new(6, 0, 0)
        base_pos = Vector3.new(base_pos.X, base_pos.Y + 2, base_pos.Z)
    end

    for i = 1, 3 do
        local unit = create_unit_model(
            ("Unit_%s_%d"):format(player.Name, i),
            player.UserId,
            base_pos + Vector3.new(i * 3, 0, 0)
        )

        unit.Parent = units_folder
    end
end

function WorldBootstrapService.start()
    local _, units_folder = ensure_world()

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.wait(0.25)
            spawn_debug_units_for_player(player, units_folder)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            spawn_debug_units_for_player(player, units_folder)
        else
            player.CharacterAdded:Connect(function()
                task.wait(0.25)
                spawn_debug_units_for_player(player, units_folder)
            end)
        end
    end

    print("[WorldBootstrap] World folders ensured + debug units enabled")
end

return WorldBootstrapService