--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local request_summon = Remotes.get_or_create_event("RequestSummon")

-- Press Q to summon one extra Skeleton (for testing).
local UserInputService = game:GetService("UserInputService")

UserInputService.InputBegan:Connect(function(input, game_processed)
    if game_processed then
        return
    end

    if input.KeyCode == Enum.KeyCode.Q then
        request_summon:FireServer("Skeleton", 1)
    end
end)
