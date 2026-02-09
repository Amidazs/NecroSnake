local Players = game:GetService("Players")

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
BoundaryService.BuildWalls(GameConfig, world.Arena)
ModelLibraryService.Sanitize()

ArmyService.Start(world.Units, world.Leaders)
SpawnService.Start()
AIStrategyService.Start()
CombatService.Start()

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