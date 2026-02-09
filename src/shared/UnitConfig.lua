--!strict
-- src/shared/UnitConfig.lua
-- Central place for unit stats. Add more unit types here.

local UnitConfig = {}

export type UnitStats = {
    display_name: string,
    max_health: number,
    damage: number,
    attack_range: number,
    attack_cooldown: number,
    move_speed: number,
}

UnitConfig.DEFAULT: UnitStats = {
    display_name = "Unit",
    max_health = 50,
    damage = 5,
    attack_range = 6,
    attack_cooldown = 1.1,
    move_speed = 16,
}

UnitConfig.BY_TYPE = {
    WeakSkeleton = {
        display_name = "Weak Skeleton",
        max_health = 35,
        damage = 4,
        attack_range = 6,
        attack_cooldown = 1.2,
        move_speed = 16,
    },
    Skeleton = {
        display_name = "Skeleton",
        max_health = 60,
        damage = 7,
        attack_range = 6,
        attack_cooldown = 1.1,
        move_speed = 16,
    },
    ZombieBrute = {
        display_name = "Zombie Brute",
        max_health = 140,
        damage = 14,
        attack_range = 7,
        attack_cooldown = 1.35,
        move_speed = 13,
    },
    GraveBaron = {
        display_name = "Grave Baron",
        max_health = 220,
        damage = 18,
        attack_range = 8,
        attack_cooldown = 1.4,
        move_speed = 14,
    },
}

function UnitConfig.get_stats(unit_type: string): UnitStats
    -- Returns a fully populated stats table for a unit type.
    local stats = UnitConfig.BY_TYPE[unit_type]
    if stats == nil then
        return UnitConfig.DEFAULT
    end
    return stats
end

return UnitConfig