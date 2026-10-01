--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NecroMVP_Swing") :: RemoteEvent
local connected: { [Tool]: boolean } = {}

local function connect_tool(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Bone Sword" then
		return
	end
	if connected[tool] then
		return
	end

	connected[tool] = true
	tool.Activated:Connect(function()
		remote:FireServer()
	end)
	tool.Destroying:Connect(function()
		connected[tool] = nil
	end)
end
local function watch_container(container: Instance)
	container.ChildAdded:Connect(connect_tool)
	for _, child in ipairs(container:GetChildren()) do
		connect_tool(child)
	end
end

local backpack = player:WaitForChild("Backpack")
watch_container(backpack)

local function on_character_added(character: Model)
	watch_container(character)
end

if player.Character then
	on_character_added(player.Character)
end

player.CharacterAdded:Connect(on_character_added)
