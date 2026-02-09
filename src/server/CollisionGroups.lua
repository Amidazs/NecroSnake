--!strict

-- CollisionGroups.lua
-- "No collision with player + named NPCs" (implemented as player <-> units no-collide).
-- Safe to call multiple times.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local CollisionGroups = {}

local GROUP_PLAYERS = "Players"
local GROUP_UNITS = "Units"

local function ensure_group(name: string)
    local ok = pcall(function()
        PhysicsService:CreateCollisionGroup(name)
    end)

    -- If it already exists, CreateCollisionGroup errors; that's fine.
    if not ok then
        -- no-op
    end
end

local function set_model_group(model: Model, group: string)
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            PhysicsService:SetPartCollisionGroup(desc, group)
        end
    end
end

function CollisionGroups.init()
    ensure_group(GROUP_PLAYERS)
    ensure_group(GROUP_UNITS)

    PhysicsService:CollisionGroupSetCollidable(GROUP_PLAYERS, GROUP_UNITS, false)
end

function CollisionGroups.apply_to_player(character: Model)
    set_model_group(character, GROUP_PLAYERS)
end

function CollisionGroups.apply_to_unit(unit_model: Model)
    set_model_group(unit_model, GROUP_UNITS)
end

function CollisionGroups.hook_players()
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            CollisionGroups.apply_to_player(character)
        end)

        if player.Character then
            CollisionGroups.apply_to_player(player.Character)
        end
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            CollisionGroups.apply_to_player(player.Character)
        end
        player.CharacterAdded:Connect(function(character)
            CollisionGroups.apply_to_player(character)
        end)
    end
end

return CollisionGroups
