local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

print("[Server] Booting NecroSnake")

local GameConfig = require(script.Parent.Services.GameConfig)
local WorldService = require(script.Parent.Services.WorldService)
local BoundaryService = require(script.Parent.Services.BoundaryService)
local ModelLibraryService = require(script.Parent.Services.ModelLibraryService)
local ArmyService = require(script.Parent.Services.ArmyService)
local SpawnService = require(script.Parent.Services.SpawnService)
local AIStrategyService = require(script.Parent.Services.AIStrategyService)
local CombatService = require(script.Parent.Services.CombatService)

local world = WorldService.EnsureWorld(GameConfig)

-- Build arena boundaries using our new module.
local boundary_service = BoundaryService.new()
boundary_service:build()

-- Sanitize models in ReplicatedStorage/ModelLibrary.
ModelLibraryService.Sanitize()

-- Start the army service with world folders.
ArmyService.Start(world.Units, world.Leaders)

-- Initialise spawn service and schedule its step on each heartbeat.
local spawn_service = SpawnService.new(ArmyService)
spawn_service:init()
RunService.Heartbeat:Connect(function(dt)
    spawn_service:step(dt)
end)

-- Start AI service which manages strategies.
AIStrategyService.Start()

-- Initialise combat service and begin its heartbeat loop.
local combat_service = CombatService.new(ArmyService)
combat_service:init()

local function setup_player(player)
    player.CharacterAdded:Connect(function(char)
        local hrp = char:WaitForChild("HumanoidRootPart")
        hrp:SetAttribute("OwnerId", player.UserId)
        hrp:SetAttribute("Kind", "Leader")
        hrp:SetAttribute("LeaderKind", "Player")
        hrp:SetAttribute("DisplayName", player.Name)
        hrp:SetAttribute("HP", GameConfig.Player.BaseHealth)
        hrp:SetAttribute("MaxHP", GameConfig.Player.BaseHealth)
        hrp:SetAttribute("Damage", GameConfig.Player.BaseDamage)

        ArmyService.CreatePlayerArmy(player, hrp)
    end)
end

Players.PlayerAdded:Connect(setup_player)

for _, p in ipairs(Players:GetPlayers()) do
    setup_player(p)
end

print("[Server] NecroSnake boot complete")
