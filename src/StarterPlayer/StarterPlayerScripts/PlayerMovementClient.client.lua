--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local active_humanoid: Humanoid? = nil

local function disable_jump(humanoid: Humanoid)
	active_humanoid = humanoid
	humanoid.AutoJumpEnabled = false
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if humanoid == active_humanoid and humanoid.Jump then
			humanoid.Jump = false
		end
	end)

	humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
		if humanoid == active_humanoid and humanoid.JumpPower ~= 0 then
			humanoid.JumpPower = 0
		end
	end)

	humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(function()
		if humanoid == active_humanoid and humanoid.JumpHeight ~= 0 then
			humanoid.JumpHeight = 0
		end
	end)
end

local function on_character_added(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") then
		disable_jump(humanoid)
	end
end

UserInputService.JumpRequest:Connect(function()
	local humanoid = active_humanoid
	if humanoid and humanoid.Parent then
		humanoid.Jump = false
		if humanoid:GetState() == Enum.HumanoidStateType.Jumping then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end
end)

if player.Character then
	task.spawn(on_character_added, player.Character)
end
player.CharacterAdded:Connect(on_character_added)
