local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(ServerScriptService.Server.Services.WorldService)
local UnitFactory = require(ServerScriptService.Server.Services.UnitFactory)

local PlayerArmyService = {}

local army_by_user_id = {}
local follow_connection = nil

local function get_character_hrp(player)
    if not player.Character then
        return nil
    end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end
    return nil
end

local function spawn_army_for_player(player)
    local units_folder = WorldService.get_units_folder()
    if not units_folder then
        return
    end

    local hrp = get_character_hrp(player)
    if not hrp then
        return
    end

    if army_by_user_id[player.UserId] then
        return
    end

    local units = {}
    local base_pos = hrp.Position + Vector3.new(6, 2, 0)

    for i = 1, 3 do
        local unit = UnitFactory.create_unit(
            player.UserId,
            ("PlayerUnit_%s_%d"):format(player.Name, i),
            base_pos + Vector3.new(i * 3, 0, 0),
            Color3.fromRGB(80, 200, 120)
        )
        unit:SetAttribute("Faction", "Player")
        unit:SetAttribute("ArmyName", ("Player_%s"):format(player.Name))
        unit.Parent = units_folder

        table.insert(units, unit)
    end

    army_by_user_id[player.UserId] = units
    print(("[PlayerArmyService] Spawned player army for %s."):format(player.Name))
end

local function ensure_follow_loop()
    if follow_connection then
        return
    end

    follow_connection = RunService.Heartbeat:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            local units = army_by_user_id[player.UserId]
            if units then
                local target_hrp = get_character_hrp(player)
                if target_hrp then
                    for i, model in ipairs(units) do
                        if model and model.Parent then
                            local hum = model:FindFirstChildOfClass("Humanoid")
                            local root = model.PrimaryPart
                            if hum and root and root:IsA("BasePart") then
                                local offset = Vector3.new(3 + (i * 2), 0, 3)
                                local goal = target_hrp.Position + offset
                                hum:MoveTo(goal)
                            end
                        end
                    end
                end
            end
        end
    end)
end

function PlayerArmyService.start()
    ensure_follow_loop()

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function()
            task.wait(0.25)
            spawn_army_for_player(player)
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            spawn_army_for_player(player)
        else
            player.CharacterAdded:Connect(function()
                task.wait(0.25)
                spawn_army_for_player(player)
            end)
        end
    end

    print("[PlayerArmyService] Ready.")
end

return PlayerArmyService