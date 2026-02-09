--!strict

-- UnitStats.lua
-- Per-unit stats: HP + damage. Intended to be called when spawning units.

local UnitStats = {}

local DEFAULTS = {
    max_health = 50,
    damage = 8,
}

local STATS_BY_UNIT_TYPE = {
    Skeleton = { max_health = 45, damage = 7 },
    Zombie = { max_health = 70, damage = 10 },
    UndeadGiant = { max_health = 220, damage = 22 },
    Dragon = { max_health = 450, damage = 40 },

    ZombieMiner = { max_health = 120, damage = 12 },
}

function UnitStats.get(unit_type: string): { max_health: number, damage: number }
    local stats = STATS_BY_UNIT_TYPE[unit_type]
    if stats then
        return stats
    end

    return {
        max_health = DEFAULTS.max_health,
        damage = DEFAULTS.damage,
    }
end

function UnitStats.apply_to_model(model: Model, unit_type: string)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    local stats = UnitStats.get(unit_type)

    humanoid.MaxHealth = stats.max_health
    humanoid.Health = stats.max_health

    model:SetAttribute("UnitType", unit_type)
    model:SetAttribute("Damage", stats.damage)
    model:SetAttribute("MaxHealth", stats.max_health)
end

return UnitStats
