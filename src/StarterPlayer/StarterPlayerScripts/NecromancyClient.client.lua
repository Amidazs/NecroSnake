--!strict

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local result_remote = Remotes.necromancy_result()
local banish_remote = Remotes.banish_request()

local gui = Instance.new("ScreenGui")
gui.Name = "NecroNecromancyGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local capacity_label = Instance.new("TextLabel")
capacity_label.Name = "CommandCapacity"
capacity_label.AnchorPoint = Vector2.new(1, 0)
capacity_label.Position = UDim2.new(1, -18, 0, 18)
capacity_label.Size = UDim2.fromOffset(220, 36)
capacity_label.BackgroundColor3 = Color3.fromRGB(15, 17, 20)
capacity_label.BackgroundTransparency = 0.18
capacity_label.BorderSizePixel = 0
capacity_label.TextColor3 = Color3.fromRGB(230, 230, 230)
capacity_label.TextStrokeTransparency = 0.55
capacity_label.Font = Enum.Font.GothamBold
capacity_label.TextSize = 17
capacity_label.Parent = gui

local capacity_corner = Instance.new("UICorner")
capacity_corner.CornerRadius = UDim.new(0, 7)
capacity_corner.Parent = capacity_label

local feedback = Instance.new("TextLabel")
feedback.Name = "NecromancyFeedback"
feedback.AnchorPoint = Vector2.new(0.5, 0)
feedback.Position = UDim2.new(0.5, 0, 0, 70)
feedback.Size = UDim2.fromOffset(560, 48)
feedback.BackgroundColor3 = Color3.fromRGB(12, 14, 17)
feedback.BackgroundTransparency = 0.15
feedback.BorderSizePixel = 0
feedback.TextColor3 = Color3.fromRGB(235, 235, 235)
feedback.TextStrokeTransparency = 0.55
feedback.Font = Enum.Font.GothamBold
feedback.TextSize = 18
feedback.TextWrapped = true
feedback.Visible = false
feedback.Parent = gui

local feedback_corner = Instance.new("UICorner")
feedback_corner.CornerRadius = UDim.new(0, 8)
feedback_corner.Parent = feedback

local message_token = 0
local channel_prompt: ProximityPrompt? = nil
local channel_started_at = 0
local channel_orb: Part? = nil
local channel_track: AnimationTrack? = nil

local function play_sound(sound_id: string, volume: number, playback_speed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = sound_id
	sound.Volume = volume
	sound.PlaybackSpeed = playback_speed
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function update_capacity()
	local used = player:GetAttribute("UsedCommandCapacity")
	local maximum = player:GetAttribute("CommandCapacity")
	if typeof(used) ~= "number" then
		used = 0
	end
	if typeof(maximum) ~= "number" then
		maximum = 5
	end
	capacity_label.Text = ("Command: %d / %d"):format(used, maximum)
end

local function show_message(message: string, status: string?)
	message_token += 1
	local token = message_token
	feedback.Text = message

	if status == "SUCCESS" then
		feedback.TextColor3 = Color3.fromRGB(125, 255, 165)
	elseif status == "FAILED" or status == "DESTROYED" then
		feedback.TextColor3 = Color3.fromRGB(255, 145, 125)
	elseif status == "FULL" or status == "CLAIMED" or status == "OWN_CORPSE" then
		feedback.TextColor3 = Color3.fromRGB(255, 215, 105)
	else
		feedback.TextColor3 = Color3.fromRGB(235, 235, 235)
	end

	feedback.Visible = true
	task.delay(3.5, function()
		if message_token == token then
			feedback.Visible = false
		end
	end)
end

local function find_model_ancestor(instance: Instance?): Model?
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function find_animation(character: Model, name: string): Animation?
	local candidate = character:FindFirstChild(name, true)
	if candidate and candidate:IsA("Animation") then
		return candidate
	end
	return nil
end

local function play_named_animation(
	character: Model,
	name: string,
	speed: number
): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animation = find_animation(character, name)
	if not animator or not animation then
		return nil
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	track:Play(0.08, 1, speed)
	return track
end

local function get_aimed_model(): Model?
	local camera = Workspace.CurrentCamera
	local character = player.Character
	if not camera then
		return nil
	end

	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 120, params)
	if not result then
		return nil
	end
	return find_model_ancestor(result.Instance)
end

local function get_prompt_root(prompt: ProximityPrompt): BasePart?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent
	end
	return nil
end

local function destroy_channel_orb()
	if channel_orb then
		channel_orb:Destroy()
		channel_orb = nil
	end
end

local function create_channel_orb(prompt: ProximityPrompt)
	destroy_channel_orb()

	local root = get_prompt_root(prompt)
	if not root then
		return
	end

	local orb = Instance.new("Part")
	orb.Name = "LocalNecroSoulFocus"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(0.7, 0.7, 0.7)
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(75, 235, 150)
	orb.Transparency = 0.12
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanTouch = false
	orb.CanQuery = false
	orb.CastShadow = false
	orb.CFrame = CFrame.new(root.Position + Vector3.new(0, 3.2, 0))
	orb.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Brightness = 1.7
	light.Range = 9
	light.Parent = orb

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "SoulParticles"
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(
		Color3.fromRGB(105, 255, 180),
		Color3.fromRGB(35, 125, 95)
	)
	particles.LightEmission = 0.8
	particles.Lifetime = NumberRange.new(0.45, 0.9)
	particles.Rate = 18
	particles.Speed = NumberRange.new(0.7, 1.8)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = orb

	channel_orb = orb
end

local function start_channel(prompt: ProximityPrompt)
	if prompt.Name ~= "NecroRaisePrompt" then
		return
	end

	channel_prompt = prompt
	channel_started_at = os.clock()
	create_channel_orb(prompt)

	local character = player.Character
	if character then
		if channel_track then
			channel_track:Stop(0.04)
		end
		channel_track = play_named_animation(character, "CheerAnim", 0.55)
	end
end

local function stop_channel(prompt: ProximityPrompt?)
	if prompt and channel_prompt ~= prompt then
		return
	end
	channel_prompt = nil
	destroy_channel_orb()
	if channel_track then
		channel_track:Stop(0.10)
		channel_track = nil
	end
end

local function create_burst(position: Vector3, color: Color3, count: number)
	for index = 1, count do
		local angle = (math.pi * 2 / count) * index
		local vertical = ((index % 3) - 1) * 0.45

		local shard = Instance.new("Part")
		shard.Name = "LocalNecroBurst"
		shard.Shape = Enum.PartType.Ball
		shard.Size = Vector3.new(0.22, 0.22, 0.22)
		shard.Material = Enum.Material.Neon
		shard.Color = color
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanTouch = false
		shard.CanQuery = false
		shard.CastShadow = false
		shard.Position = position + Vector3.new(0, 2.2, 0)
		shard.Parent = Workspace

		local destination = shard.Position + Vector3.new(
			math.cos(angle) * 4,
			1.8 + vertical,
			math.sin(angle) * 4
		)
		local tween = TweenService:Create(
			shard,
			TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{
				Position = destination,
				Transparency = 1,
				Size = Vector3.new(0.05, 0.05, 0.05),
			}
		)
		tween:Play()
		Debris:AddItem(shard, 0.55)
	end
end

local function play_raise_result_fx(payload)
	local position = payload.worldPosition
	if typeof(position) ~= "Vector3" then
		return
	end

	local status = payload.status
	if status == "SUCCESS" then
		create_burst(position, Color3.fromRGB(85, 255, 165), 10)
		play_sound("rbxasset://sounds/electronicpingshort.wav", 0.6, 0.72)
	elseif status == "FAILED" then
		create_burst(position, Color3.fromRGB(235, 155, 65), 6)
		play_sound("rbxasset://sounds/impact_water.mp3", 0.3, 0.82)
	elseif status == "DESTROYED" then
		create_burst(position, Color3.fromRGB(205, 60, 100), 12)
		play_sound("rbxasset://sounds/uuhhh.mp3", 0.4, 0.9)
	end
end

local function on_banish(
	_action_name: string,
	input_state: Enum.UserInputState,
	_input_object: InputObject
): Enum.ContextActionResult
	if input_state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	local target = get_aimed_model()
	if not target then
		show_message("Aim at one of your undead to Banish it.", "FAILED")
		return Enum.ContextActionResult.Sink
	end

	banish_remote:FireServer(target)
	return Enum.ContextActionResult.Sink
end

result_remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	stop_channel(nil)
	play_raise_result_fx(payload)

	local message = payload.message
	if typeof(message) ~= "string" or message == "" then
		return
	end
	show_message(message, payload.status)
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
	if prompt:IsA("ProximityPrompt") then
		start_channel(prompt)
	end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
	if prompt:IsA("ProximityPrompt") then
		stop_channel(prompt)
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if prompt:IsA("ProximityPrompt") then
		stop_channel(prompt)
	end
end)

RunService.RenderStepped:Connect(function()
	local prompt = channel_prompt
	if not prompt then
		return
	end

	local root = get_prompt_root(prompt)
	if not root or prompt.Parent == nil then
		stop_channel(prompt)
		return
	end

	local elapsed = os.clock() - channel_started_at
	local pulse = (math.sin(elapsed * 10) + 1) * 0.5
	local raise_alpha = math.clamp(
		elapsed / math.max(0.1, prompt.HoldDuration),
		0,
		1
	)

	if channel_orb then
		channel_orb.CFrame = CFrame.new(
			root.Position
				+ Vector3.new(0, 2.6 + (raise_alpha * 1.25) + (pulse * 0.15), 0)
		)
		local scale = 0.65 + (raise_alpha * 0.75) + (pulse * 0.08)
		channel_orb.Size = Vector3.new(scale, scale, scale)
	end
end)

player:GetAttributeChangedSignal("UsedCommandCapacity"):Connect(update_capacity)
player:GetAttributeChangedSignal("CommandCapacity"):Connect(update_capacity)
update_capacity()

ContextActionService:BindAction(
	"NecroBanish",
	on_banish,
	true,
	Enum.KeyCode.B,
	Enum.KeyCode.ButtonY
)
ContextActionService:SetTitle("NecroBanish", "Banish")
ContextActionService:SetPosition(
	"NecroBanish",
	UDim2.new(1, -130, 1, -210)
)
