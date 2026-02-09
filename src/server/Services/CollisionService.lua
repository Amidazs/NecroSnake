--!strict
-- src/server/Services/CollisionService.lua
-- Creates collision groups so units don't collide with players or named NPCs.

local PhysicsService = game:GetService("PhysicsService")

local CollisionService = {}
CollisionService.__index = CollisionService

local GROUP_UNITS = "Units"
local GROUP_PLAYERS = "Players"
local GROUP_NAMED_NPCS = "NamedNPCs"

local function ensure_group(name: string)
    local ok = pcall(function()
        PhysicsService:CreateCollisionGroup(name)
    end)
    return ok
end

local function set_collidable(a: string, b: string, can_collide: boolean)
    PhysicsService:CollisionGroupSetCollidable(a, b, can_collide)
end

function CollisionService.new()
    local self = setmetatable({}, CollisionService)
    return self
end

function CollisionService:init()
    ensure_group(GROUP_UNITS)
    ensure_group(GROUP_PLAYERS)
    ensure_group(GROUP_NAMED_NPCS)

    -- Units should NOT collide with players or named NPCs.
    set_collidable(GROUP_UNITS, GROUP_PLAYERS, false)
    set_collidable(GROUP_UNITS, GROUP_NAMED_NPCS, false)

    -- Allow units to collide with units (keeps swarms from fully stacking).
    set_collidable(GROUP_UNITS, GROUP_UNITS, true)

    -- Players collide with named NPCs by default (fine either way).
    set_collidable(GROUP_PLAYERS, GROUP_NAMED_NPCS, true)

    print("[CollisionService] Ready. Units do not collide with Players/NamedNPCs.")
end

function CollisionService:apply_to_model(model: Model, group_name: string)
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            PhysicsService:SetPartCollisionGroup(d, group_name)
        end
    end
end

function CollisionService:apply_unit(model: Model)
    self:apply_to_model(model, GROUP_UNITS)
end

function CollisionService:apply_player_character(character: Model)
    self:apply_to_model(character, GROUP_PLAYERS)
end

function CollisionService:apply_named_npc(model: Model)
    self:apply_to_model(model, GROUP_NAMED_NPCS)
end

return CollisionService