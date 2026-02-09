local ArmyService = {}

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)
local UnitFactoryService = require(script.Parent.UnitFactoryService)

local active_armies = {}
local roaming_groups = {}

local function now()
    return os.clock()
end

local function dbg(fmt, ...)
    if not GameConfig.Debug.Enabled then
        return
    end
    print(string.format("[ArmyService] " .. fmt, ...))
end

local function compute_formation_pos(leader_pos, formation_index)
    local golden = GameConfig.Formation.GoldenAngle
    local inner_cap = GameConfig.Formation.InnerCapacity
    local i = formation_index
    if typeof(i) ~= "number" or i < 1 then
        i = 1
    end

    local is_inner = (i <= inner_cap)
    local local_i = i
    local spacing = GameConfig.Formation.OuterSpacing
    local radius_boost = 0

    if is_inner then
        spacing = GameConfig.Formation.InnerSpacing
    else
        local_i = i - inner_cap
        spacing = GameConfig.Formation.OuterSpacing
        radius_boost = GameConfig.Formation.OuterRadiusBoost
    end

    local r = (spacing * math.sqrt(local_i)) + radius_boost
    local theta = local_i * golden

    return Vector3.new(
        leader_pos.X + r * math.cos(theta),
        leader_pos.Y,
        leader_pos.Z + r * math.sin(theta)
    )
end

local function power_of_part(part)
    local hp = part:GetAttribute("HP")
    local dmg = part:GetAttribute("Damage")
    if typeof(hp) ~= "number" then
        hp = 0
    end
    if typeof(dmg) ~= "number" then
        dmg = 0
    end
    return hp + (dmg * 12)
end

function ArmyService.Start(world_units, world_leaders)
    ArmyService._units = world_units
    ArmyService._leaders = world_leaders
    dbg("Ready.")

    RunService.Heartbeat:Connect(function()
        for _, army in pairs(active_armies) do
            ArmyService.UpdateArmyFormation(army)
        end
    end)
end

function ArmyService.GetArmy(owner_id)
    return active_armies[owner_id]
end

function ArmyService.GetAllArmies()
    return active_armies
end

function ArmyService.GetRoamingGroups()
    return roaming_groups
end

function ArmyService.CreatePlayerArmy(player, leader_part)
    local owner_id = player.UserId
    local army = active_armies[owner_id]
    if not army then
        army = { OwnerId = owner_id, Kind = "Player", Units = {}, NextIndex = 1 }
        active_armies[owner_id] = army
    end

    army.Leader = leader_part
    leader_part:SetAttribute("OwnerId", owner_id)
    leader_part:SetAttribute("Kind", "Leader")
    leader_part:SetAttribute("LeaderKind", "Player")
    leader_part:SetAttribute("DisplayName", player.Name)
    leader_part:SetAttribute("HP", GameConfig.Player.BaseHealth)
    leader_part:SetAttribute("MaxHP", GameConfig.Player.BaseHealth)
    leader_part:SetAttribute("Damage", GameConfig.Player.BaseDamage)

    dbg("Spawned player army: Player_%s (id=%s)", player.Name, tostring(owner_id))

    ArmyService.ClearUnits(owner_id)
    for _ = 1, GameConfig.Player.StartCount do
        ArmyService.AddUnit(owner_id, GameConfig.Player.StartType, "Player")
    end
end

function ArmyService.CreateNamedArmy(def, leader_pos)
    local owner_id = "NAMED_" .. tostring(math.floor(now() * 1000))

    local leader = UnitFactoryService.CreateCorePart(
        Vector3.new(6, 6, 6),
        GameConfig.Colors.NamedLeader,
        leader_pos,
        ArmyService._leaders
    )

    leader.Name = def.Name
    leader:SetAttribute("OwnerId", owner_id)
    leader:SetAttribute("Kind", "Leader")
    leader:SetAttribute("LeaderKind", "NamedNPC")
    leader:SetAttribute("IsNamedNPC", true)
    leader:SetAttribute("DisplayName", def.Name)
    leader:SetAttribute("HP", 900)
    leader:SetAttribute("MaxHP", 900)
    leader:SetAttribute("Damage", 30)

    UnitFactoryService.ApplyVisual(leader, def.Name)
    UnitFactoryService.AttachMover(
        leader,
        GameConfig.Movement.LeaderMaxForce,
        GameConfig.Movement.LeaderResponsiveness,
        GameConfig.Movement.LeaderMaxVelocity
    )

    local army = {
        OwnerId = owner_id,
        Kind = "Named",
        Name = def.Name,
        Leader = leader,
        Units = {},
        NextIndex = 1,
        ExpiresAt = now() + GameConfig.Spawn.NamedExpirySeconds,
    }
    active_armies[owner_id] = army

    for _, entry in ipairs(def.Army) do
        for _ = 1, entry.Count do
            ArmyService.AddUnit(owner_id, entry.Type, "Named")
        end
    end

    dbg("Spawned named NPC army: %s (id=%s) expires=%ds", def.Name, owner_id, GameConfig.Spawn.NamedExpirySeconds)
    return army
end

function ArmyService.CreateWanderingGroup(unit_types, center_pos)
    local group_id = "G" .. tostring(math.floor(now() * 1000))
    local owner_id = "WANDER_" .. group_id

    local group = {
        GroupId = group_id,
        OwnerId = owner_id,
        Kind = "Wander",
        Units = {},
        Target = center_pos,
        NextTargetAt = 0,
        ExpiresAt = now() + GameConfig.Spawn.GroupExpirySeconds,
    }
    roaming_groups[group_id] = group

    local radius = 7
    for i, unit_type in ipairs(unit_types) do
        local angle = (i / #unit_types) * math.pi * 2
        local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
        local spawn_pos = center_pos + offset

        local part = ArmyService._spawn_unit_core(owner_id, unit_type, spawn_pos, "Wander")
        local mover = UnitFactoryService.AttachMover(
            part,
            GameConfig.Movement.LeaderMaxForce,
            GameConfig.Movement.LeaderResponsiveness,
            GameConfig.Movement.LeaderMaxVelocity
        )

        table.insert(group.Units, { Part = part, Mover = mover, Offset = offset })
    end

    dbg("Spawned wandering group: id=%s size=%d expires=%ds", group_id, #unit_types, GameConfig.Spawn.GroupExpirySeconds)
    return group
end

function ArmyService.ClearUnits(owner_id)
    local army = active_armies[owner_id]
    if not army then
        return
    end
    for _, u in ipairs(army.Units) do
        if u.Part and u.Part.Parent then
            u.Part:Destroy()
        end
    end
    army.Units = {}
    army.NextIndex = 1
end

function ArmyService._spawn_unit_core(owner_id, unit_type, pos, faction)
    local stats = GameConfig.Units[unit_type] or GameConfig.Units.Skeleton
    local color = GameConfig.Colors.WanderUnit
    if faction == "Player" then
        color = GameConfig.Colors.PlayerUnit
    elseif faction == "Named" then
        color = GameConfig.Colors.NamedUnit
    end

    local unit = UnitFactoryService.CreateCorePart(
        Vector3.new(stats.Size, stats.Size, stats.Size),
        color,
        pos + Vector3.new(0, 6, 0),
        ArmyService._units
    )

    unit.Name = unit_type
    unit:SetAttribute("OwnerId", owner_id)
    unit:SetAttribute("Kind", "Unit")
    unit:SetAttribute("Type", unit_type)
    unit:SetAttribute("DisplayName", unit_type)
    unit:SetAttribute("HP", stats.Health)
    unit:SetAttribute("MaxHP", stats.Health)
    unit:SetAttribute("Damage", stats.Damage)

    UnitFactoryService.ApplyVisual(unit, unit_type)
    return unit
end

function ArmyService.AddUnit(owner_id, unit_type, faction)
    local army = active_armies[owner_id]
    if not army or not army.Leader or not army.Leader.Parent then
        return nil
    end

    local unit = ArmyService._spawn_unit_core(owner_id, unit_type, army.Leader.Position, faction)

    local stats = GameConfig.Units[unit_type] or GameConfig.Units.Skeleton
    local mover = UnitFactoryService.AttachMover(
        unit,
        GameConfig.Movement.UnitMaxForce * stats.Mass,
        GameConfig.Movement.UnitResponsiveness,
        GameConfig.Movement.UnitMaxVelocity
    )

    local idx = army.NextIndex or 1
    army.NextIndex = idx + 1
    unit:SetAttribute("FormationIndex", idx)

    table.insert(army.Units, { Part = unit, Mover = mover })
    return unit
end

function ArmyService.UpdateArmyFormation(army)
    if not army.Leader or not army.Leader.Parent then
        return
    end

    local center = army.Leader.Position
    for _, u in ipairs(army.Units) do
        if u.Part and u.Part.Parent then
            local idx = u.Part:GetAttribute("FormationIndex") or 1
            local target = compute_formation_pos(center, idx)
            u.Mover.Position = target
        end
    end
end

function ArmyService.RemoveExpired()
    local t = now()
    for owner_id, army in pairs(active_armies) do
        if army.Kind ~= "Player" and army.ExpiresAt and t >= army.ExpiresAt then
            if army.Leader and army.Leader.Parent then
                army.Leader:Destroy()
            end
            ArmyService.ClearUnits(owner_id)
            active_armies[owner_id] = nil
            dbg("Removed expired army: id=%s", tostring(owner_id))
        end
    end

    for group_id, group in pairs(roaming_groups) do
        if group.ExpiresAt and t >= group.ExpiresAt then
            for _, u in ipairs(group.Units) do
                if u.Part and u.Part.Parent then
                    u.Part:Destroy()
                end
            end
            roaming_groups[group_id] = nil
            dbg("Removed expired wandering group: id=%s", tostring(group_id))
        end
    end
end

function ArmyService.PowerOfArmy(owner_id)
    local army = active_armies[owner_id]
    if not army then
        return 0
    end
    local total = 0
    if army.Leader and army.Leader.Parent then
        total += power_of_part(army.Leader)
    end
    for _, u in ipairs(army.Units) do
        if u.Part and u.Part.Parent then
            total += power_of_part(u.Part)
        end
    end
    return total
end

function ArmyService.PowerOfWanderingGroup(group_id)
    local g = roaming_groups[group_id]
    if not g then
        return 0
    end
    local total = 0
    for _, u in ipairs(g.Units) do
        if u.Part and u.Part.Parent then
            total += power_of_part(u.Part)
        end
    end
    return total
end

-- Returns a flat list of all unit models (leaders and units) across all armies
-- and roaming groups. This is used by CombatService to find potential targets.
function ArmyService:get_all_units()
    local units = {}

    -- Include leader parts and unit parts for each active army
    for _, army in pairs(active_armies) do
        if army.Leader and army.Leader.Parent then
            table.insert(units, army.Leader)
        end
        for _, entry in ipairs(army.Units) do
            if entry.Part and entry.Part.Parent then
                table.insert(units, entry.Part)
            end
        end
    end

    -- Include unit parts from roaming groups
    for _, group in pairs(roaming_groups) do
        for _, entry in ipairs(group.Units) do
            if entry.Part and entry.Part.Parent then
                table.insert(units, entry.Part)
            end
        end
    end

    return units
end

-----------------------------------------------------------------------
-- Spawn and count helpers used by SpawnService
-----------------------------------------------------------------------

-- Returns the number of active named NPC armies (ignores expired ones).
function ArmyService:get_named_count()
    local count = 0
    for _, army in pairs(active_armies) do
        if army.Kind == "Named" then
            count += 1
        end
    end
    return count
end

-- Returns the number of currently roaming wandering groups.
function ArmyService:get_wander_count()
    local count = 0
    for _ in pairs(roaming_groups) do
        count += 1
    end
    return count
end

-- Spawns a random named NPC army at a random position inside the arena.
function ArmyService:spawn_named_army()
    local defs = GameConfig.NamedNPCs
    if not defs or #defs == 0 then
        return nil
    end
    -- pick a random named definition
    local def = defs[math.random(1, #defs)]

    -- pick a random point within the arena half‑size
    local half = GameConfig.Arena.HalfSize
    local pos = Vector3.new(
        math.random(-half.X, half.X),
        0,
        math.random(-half.Z, half.Z)
    )

    return ArmyService.CreateNamedArmy(def, pos)
end

-- Spawns a random wandering group (composition) at a random position in the arena.
function ArmyService:spawn_wandering_group()
    local comps = GameConfig.WanderingCompositions
    if not comps or #comps == 0 then
        return nil
    end
    -- choose a random unit composition (e.g. { "Skeleton", "Skeleton" })
    local comp = comps[math.random(1, #comps)]

    -- random spawn position
    local half = GameConfig.Arena.HalfSize
    local pos = Vector3.new(
        math.random(-half.X, half.X),
        0,
        math.random(-half.Z, half.Z)
    )

    return ArmyService.CreateWanderingGroup(comp, pos)
end



return ArmyService