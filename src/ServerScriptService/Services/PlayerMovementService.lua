--!strict

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local PlayerMovementService = {}

local did_start = false

local function disable_jump_for_character(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	end
	if not humanoid then
		return
	end

	humanoid.AutoJumpEnabled = false
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid.Jump then
			humanoid.Jump = false
		end
	end)

	humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
		if humanoid.JumpPower ~= 0 then
			humanoid.JumpPower = 0
		end
	end)

	humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(function()
		if humanoid.JumpHeight ~= 0 then
			humanoid.JumpHeight = 0
		end
	end)
end

local function hook_player(player: Player)
	player.CharacterAdded:Connect(function(character)
		disable_jump_for_character(character)
	end)

	if player.Character then
		disable_jump_for_character(player.Character)
	end
end

function PlayerMovementService.start()
	if did_start then
		return
	end
	did_start = true

	StarterPlayer.AutoJumpEnabled = false
	Players.PlayerAdded:Connect(hook_player)
	for _, player in ipairs(Players:GetPlayers()) do
		hook_player(player)
	end
end

return PlayerMovementService
