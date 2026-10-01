--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local PLAYER_ARMIES_FOLDER_NAME = "PlayerArmies"

local UPDATE_SECONDS = 0.35
local NEAR_DISTANCE = 110
local MID_DISTANCE = 240
local MID_PARTICLE_RATE_SCALE = 0.35

type EffectState = {
	enabled: boolean,
	rate: number?,
}

local tracked: { [Model]: { [Instance]: EffectState } } = {}
local update_accumulator = 0

local function is_supported_effect(instance: Instance): boolean
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Trail")
		or instance:IsA("Beam")
		or instance:IsA("PointLight")
		or instance:IsA("SpotLight")
		or instance:IsA("SurfaceLight")
end
local function capture_effect(instance: Instance): EffectState?
	if not is_supported_effect(instance) then
		return nil
	end

	if instance:IsA("ParticleEmitter") then
		return {
			enabled = instance.Enabled,
			rate = instance.Rate,
		}
	end

	local enabled = (instance :: any).Enabled
	return {
		enabled = enabled == true,
		rate = nil,
	}
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end
local function apply_effect_level(
	instance: Instance,
	state: EffectState,
	level: number
)
	if instance.Parent == nil then
		return
	end

	if instance:IsA("ParticleEmitter") then
		if level == 0 then
			instance.Enabled = state.enabled
			instance.Rate = state.rate or instance.Rate
		elseif level == 1 then
			instance.Enabled = state.enabled
			instance.Rate = (state.rate or instance.Rate)
				* MID_PARTICLE_RATE_SCALE
		else
			instance.Enabled = false
		end
		return
	end

	local effect = instance :: any
	if level == 0 then
		effect.Enabled = state.enabled
	elseif level == 1 and (instance:IsA("Trail") or instance:IsA("Beam")) then
		effect.Enabled = state.enabled
	else
		effect.Enabled = false
	end
end
local function track_effect(model: Model, instance: Instance)
	local states = tracked[model]
	if not states or states[instance] then
		return
	end

	local state = capture_effect(instance)
	if state then
		states[instance] = state
	end
end

local function hook_model(model: Model)
	if tracked[model] then
		return
	end
	if model:GetAttribute("IsPlayerArmy") ~= true then
		return
	end

	tracked[model] = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		track_effect(model, descendant)
	end

	model.DescendantAdded:Connect(function(descendant)
		track_effect(model, descendant)
	end)
	model.DescendantRemoving:Connect(function(descendant)
		local states = tracked[model]
		if states then
			states[descendant] = nil
		end
	end)
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			tracked[model] = nil
		end
	end)
end

local function get_lod_level(distance: number): number
	if distance <= NEAR_DISTANCE then
		return 0
	end
	if distance <= MID_DISTANCE then
		return 1
	end
	return 2
end

local function update_visual_lod()
	local character = LOCAL_PLAYER.Character
	local player_root = character and character:FindFirstChild("HumanoidRootPart")
	if not (player_root and player_root:IsA("BasePart")) then
		return
	end

	for model, effects in pairs(tracked) do
		local root = get_root(model)
		if model.Parent == nil or not root then
			tracked[model] = nil
			continue
		end
		local distance = (root.Position - player_root.Position).Magnitude
		local level = get_lod_level(distance)
		for instance, state in pairs(effects) do
			if instance.Parent == nil then
				effects[instance] = nil
			else
				apply_effect_level(instance, state, level)
			end
		end
	end
end

local connected_armies: Folder? = nil

local function hook_armies_folder(armies: Folder)
	if connected_armies == armies then
		return
	end
	connected_armies = armies

	for _, instance in ipairs(armies:GetDescendants()) do
		if instance:IsA("Model") then
			hook_model(instance)
		end
	end

	armies.DescendantAdded:Connect(function(instance)
		if instance:IsA("Model") then
			task.defer(function()
				hook_model(instance)
			end)
		end
	end)
end

local function main()
	local existing = Workspace:FindFirstChild(
		PLAYER_ARMIES_FOLDER_NAME
	)
	if existing and existing:IsA("Folder") then
		hook_armies_folder(existing)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == PLAYER_ARMIES_FOLDER_NAME
			and child:IsA("Folder")
		then
			hook_armies_folder(child)
		end
	end)

	RunService.Heartbeat:Connect(function(delta_time)
		update_accumulator += delta_time
		if update_accumulator < UPDATE_SECONDS then
			return
		end
		update_accumulator = 0
		update_visual_lod()
	end)
end

main()
