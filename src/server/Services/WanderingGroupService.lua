local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(ServerScriptService.Server.Services.WorldService)
local UnitFactory = require(ServerScriptService.Server.Services.UnitFactory)

local WanderingGroupService = {}

local next_group_owner_id = -2000

local GROUP_SPAWN_INTERVAL = 12
local GROUP_MOVE_INTERVAL = 4
local GROUP_LIFETIME_SECONDS = 60
local GROUP_UNIT_COUNT = 4

local WANDER_MIN = Vector3.new(-70, 5, -70)
local WANDER_MAX = Vector3.new(70, 5, 70)

local active_groups = {}

local function allocate_group_owner_id()
    next_group_owner_id -= 1
    return next_group_owner_id
end

local function random_point()
    local x = math.random(WANDER_MIN.X, WANDER_MAX.X)
    local z = math.random(WANDER_MIN.Z, WANDER_MAX.Z)
    return Vector3.new(x, WANDER_MIN.Y, z)
end

local function create_group()
    local units_folder = WorldService.get_units_folder()
    local leaders_folder = WorldService.get_leaders_folder()

    if not units_folder or not leaders_folder then
        return
    end

    local owner_id = allocate_group_owner_id()
    local spawn_pos = random_point()

    local leader = UnitFactory.create_leader_part(
        owner_id,
        ("WanderLeader_%d"):format(math.abs(owner_id)),
        spawn_pos,
        Color3.fromRGB(220, 80, 80)
    )
    leader.Parent = leaders_folder

    local units = {}
    for i = 1, GROUP_UNIT_COUNT do
        local unit = UnitFactory.create_unit(
            owner_id,
            ("WanderUnit_%d_%d"):format(math.abs(owner_id), i),
            spawn_pos + Vector3.new(i * 3, 2, 0),
            Color3.fromRGB(220, 80, 80)
        )
        unit:SetAttribute("Faction", "NPC")
        unit:SetAttribute("ArmyName", "Wanderers")
        unit.Parent = units_folder
        table.insert(units, unit)
    end

    active_groups[owner_id] = {
        owner_id = owner_id,
        leader = leader,
        units = units,
        born_t = os.clock(),
        next_move_t = os.clock(),
    }

    print(("[WanderingGroupService] Spawned wandering group (owner_id=%d).")
        :format(owner_id))
end

local function cleanup_group(owner_id, group)
    if group.leader and group.leader.Parent then
        group.leader:Destroy()
    end

    for _, unit in ipairs(group.units) do
        if unit and unit.Parent then
            unit:Destroy()
        end
    end

    active_groups[owner_id] = nil
end

local function tick_groups()
    local t = os.clock()

    for owner_id, group in pairs(active_groups) do
        if (t - group.born_t) > GROUP_LIFETIME_SECONDS then
            cleanup_group(owner_id, group)
        else
            if t >= group.next_move_t then
                group.next_move_t = t + GROUP_MOVE_INTERVAL

                if group.leader and group.leader.Parent then
                    group.leader.Position = random_point()
                end
            end

            if group.leader and group.leader.Parent then
                local leader_pos = group.leader.Position
                for i, model in ipairs(group.units) do
                    if model and model.Parent then
                        local hum = model:FindFirstChildOfClass("Humanoid")
                        local root = model.PrimaryPart
                        if hum and root and root:IsA("BasePart") then
                            local offset = Vector3.new(3 + (i * 2), 0, 3)
                            hum:MoveTo(leader_pos + offset)
                        end
                    end
                end
            end
        end
    end
end

function WanderingGroupService.start()
    if not RunService:IsServer() then
        return
    end

    task.spawn(function()
        while true do
            create_group()
            task.wait(GROUP_SPAWN_INTERVAL)
        end
    end)

    RunService.Heartbeat:Connect(function()
        tick_groups()
    end)

    print("[WanderingGroupService] Ready.")
end

return WanderingGroupService