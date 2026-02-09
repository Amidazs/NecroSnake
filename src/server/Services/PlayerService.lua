local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)

local PlayerService = {}

function PlayerService.start()
    local hello_remote = Remotes.get_remote_event("Hello")

    Players.PlayerAdded:Connect(function(player)
        print(("[PlayerService] Player joined: %s"):format(player.Name))
        hello_remote:FireClient(
            player,
            ("Welcome to NecroSnake, %s!"):format(player.Name)
        )
    end)
end

return PlayerService