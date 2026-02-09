local AIStrategyService = {}

local GameConfig = require(script.Parent.GameConfig)
local BoundaryService = require(script.Parent.BoundaryService)
local ArmyService = require(script.Parent.ArmyService)

local function now()
    return os.clock()
end

local last_dbg = 0
local function dbg(fmt, ...)
    if not GameConfig.Debug.Enabled then
        return
    end
    local t = now()
    if (t - last_dbg) < GameConfig.Debug.AiEverySeconds then
        return
    end
    last_dbg = t
    print(string.format("[AIStrategyService] " .. fmt, ...))
end

local function rand_range(a, b)
    return a + (b - a) * math.random()
end

local function pick_wander_target(pos)
    local j = GameConfig.AI.WanderJitterStuds
    local jitter = Vector3.new(rand_range(-j, j), 0, rand_range(-j, j))
    return BoundaryService.ClampToArena(GameConfig, pos + jitter)
end

local function compute_center_of_group(group)
    local sum = Vector3.new(0, 0, 0)
    local count = 0
    for _, u in ipairs(group.Units) do
        if u.Part and u.Part.Parent then
            sum += u.Part.Position
            count += 1
        end
    end
    if count <= 0 then
        return nil
    end
    local c = sum / count
    return Vector3.new(c.X, GameConfig.Arena.GroundY, c.Z)
end

local function group_power(group)
    return ArmyService.PowerOfWanderingGroup(group.GroupId)
end

local function army_center(army)
    if army.Leader and army.Leader.Parent then
        return Vector3.new(army.Leader.Position.X, GameConfig.Arena.GroundY, army.Leader.Position.Z)
    end
    return nil
end

local function find_nearest_enemy(self_owner, self_pos)
    local best = nil
    local best_dist = GameConfig.AI.SenseRange

    for owner_id, army in pairs(ArmyService.GetAllArmies()) do
        if owner_id ~= self_owner then
            local pos = army_center(army)
            if pos then
                local d = (pos - self_pos).Magnitude
                if d < best_dist then
                    best_dist = d
                    best = { Kind = "Army", OwnerId = owner_id, Pos = pos, Power = ArmyService.PowerOfArmy(owner_id) }
                end
            end
        end
    end

    for group_id, group in pairs(ArmyService.GetRoamingGroups()) do
        if group.OwnerId ~= self_owner then
            local pos = compute_center_of_group(group)
            if pos then
                local d = (pos - self_pos).Magnitude
                if d < best_dist then
                    best_dist = d
                    best = { Kind = "Group", OwnerId = group.OwnerId, Pos = pos, Power = group_power(group) }
                end
            end
        end
    end

    return best, best_dist
end

local function chase_or_flee(self_pos, self_power, enemy)
    local to_enemy = enemy.Pos - self_pos
    local dist = to_enemy.Magnitude
    if dist <= 0.01 then
        return pick_wander_target(self_pos), "Wander"
    end

    local stronger = self_power >= (enemy.Power * GameConfig.AI.Hysteresis)
    if stronger then
        if dist > GameConfig.AI.ChaseStopRange then
            return BoundaryService.ClampToArena(GameConfig, enemy.Pos), "Chase"
        end
        return BoundaryService.ClampToArena(GameConfig, self_pos), "Hold"
    end

    local away = (-to_enemy).Unit
    local flee_pos = self_pos + (away * GameConfig.AI.FleeDistance)
    return BoundaryService.ClampToArena(GameConfig, flee_pos), "Flee"
end

function AIStrategyService.Start()
    dbg("Ready.")
    task.spawn(function()
        while true do
            AIStrategyService.Tick()
            task.wait(0.18)
        end
    end)
end

function AIStrategyService.Tick()
    local t = now()

    -- Wandering groups
    for group_id, group in pairs(ArmyService.GetRoamingGroups()) do
        local center = compute_center_of_group(group)
        if not center then
            continue
        end

        if t >= (group.NextTargetAt or 0) then
            local enemy = find_nearest_enemy(group.OwnerId, center)
            local my_power = group_power(group)
            if enemy then
                local target, mode = chase_or_flee(center, my_power, enemy)
                group.Target = target
                dbg("%s: %s -> %s (my=%d enemy=%d dist=%.1f)",
                    mode,
                    "Wanderers",
                    enemy.Kind,
                    my_power,
                    enemy.Power,
                    (enemy.Pos - center).Magnitude
                )
            else
                group.Target = pick_wander_target(center)
                dbg("Wander: id=%s newTarget=(%d,%d)", group_id, group.Target.X, group.Target.Z)
            end

            group.NextTargetAt = t + rand_range(
                GameConfig.Movement.TargetUpdateMinSeconds,
                GameConfig.Movement.TargetUpdateMaxSeconds
            )
        end

        if group.Target then
            for _, u in ipairs(group.Units) do
                if u.Part and u.Part.Parent then
                    local desired = group.Target + (u.Offset or Vector3.new())
                    u.Mover.Position = BoundaryService.ClampToArena(GameConfig, desired)
                end
            end
        end
    end

    -- Named NPC leaders (leaders move; units are formation-driven by ArmyService)
    for owner_id, army in pairs(ArmyService.GetAllArmies()) do
        if army.Kind == "Named" and army.Leader and army.Leader.Parent then
            local leader = army.Leader
            local self_pos = Vector3.new(leader.Position.X, GameConfig.Arena.GroundY, leader.Position.Z)
            local enemy = find_nearest_enemy(owner_id, self_pos)
            local my_power = ArmyService.PowerOfArmy(owner_id)

            local mover = leader:FindFirstChildWhichIsA("AlignPosition")
            if mover then
                if enemy then
                    local target, mode = chase_or_flee(self_pos, my_power, enemy)
                    mover.Position = target
                    dbg("%s: %s -> %s (my=%d enemy=%d dist=%.1f)",
                        mode,
                        army.Name or "Named",
                        enemy.Kind,
                        my_power,
                        enemy.Power,
                        (enemy.Pos - self_pos).Magnitude
                    )
                else
                    mover.Position = pick_wander_target(self_pos)
                end
            end
        end
    end
end

return AIStrategyService