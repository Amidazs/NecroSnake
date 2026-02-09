--!strict
-- src/server/Services/SpawnService.lua
-- Increases spawn counts to make the map feel populated.

local SpawnService = {}
SpawnService.__index = SpawnService

local TICK_SECONDS = 2.0

local NAMED_MAX = 5
local WANDER_MAX = 14

local NAMED_ROLL_CHANCE = 0.22
local WANDER_ROLL_CHANCE = 0.75

function SpawnService.new(army_service)
    local self = setmetatable({}, SpawnService)
    self._army_service = army_service
    self._accum = 0
    return self
end

function SpawnService:init()
    print("[SpawnService] Ready.")
end

function SpawnService:_try_spawn()
    local named_count = self._army_service:get_named_count()
    local wander_count = self._army_service:get_wander_count()

    print(("[SpawnService] Tick: named=%d/%d wander=%d/%d"):format(
        named_count, NAMED_MAX, wander_count, WANDER_MAX
    ))

    local roll_named = math.random()
    if named_count < NAMED_MAX and roll_named < NAMED_ROLL_CHANCE then
        print(("[SpawnService] Spawn attempt: NAMED (roll=%.2f < %.2f)"):format(
            roll_named, NAMED_ROLL_CHANCE
        ))
        self._army_service:spawn_named_army()
        return
    end

    local roll_wander = math.random()
    if wander_count < WANDER_MAX and roll_wander < WANDER_ROLL_CHANCE then
        print(("[SpawnService] Spawn attempt: WANDER (roll=%.2f < %.2f)"):format(
            roll_wander, WANDER_ROLL_CHANCE
        ))
        self._army_service:spawn_wandering_group()
    end
end

function SpawnService:step(dt: number)
    self._accum += dt
    if self._accum >= TICK_SECONDS then
        self._accum = 0
        self:_try_spawn()
    end
end

return SpawnService