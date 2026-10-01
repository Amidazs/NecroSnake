--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local player = Players.LocalPlayer
local swing_remote = ReplicatedStorage:WaitForChild("NecroMVP_Swing") :: RemoteEvent
local feedback_remote = Remotes.combat_feedback()
local connected: { [Tool]: boolean } = {}

local LOCAL_SWING_COOLDOWN = 0.43
local TRAIL_LIFETIME = 0.18
local TRAIL_ACTIVE_SECONDS = 0.30

local last_swing_at = -math.huge
local active_swing_track: AnimationTrack? = nil

local function play_sound(sound_id: string, volume: number, playback_speed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = sound_id
	sound.Volume = volume
	sound.PlaybackSpeed = playback_speed
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 3)
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
	track:Play(0.04, 1, speed)
	return track
end

local function ensure_trail(tool: Tool): Trail?
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end

	local existing = handle:FindFirstChild("NecroSwordTrail")
	if existing and existing:IsA("Trail") then
		return existing
	end

	local top = Instance.new("Attachment")
	top.Name = "NecroTrailTop"
	top.Position = Vector3.new(0, handle.Size.Y * 0.48, 0)
	top.Parent = handle

	local bottom = Instance.new("Attachment")
	bottom.Name = "NecroTrailBottom"
	bottom.Position = Vector3.new(0, -handle.Size.Y * 0.48, 0)
	bottom.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "NecroSwordTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = TRAIL_LIFETIME
	trail.MinLength = 0.08
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(
		Color3.fromRGB(220, 255, 245),
		Color3.fromRGB(65, 190, 150)
	)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = handle
	return trail
end

local function start_swing(tool: Tool)
	local now = os.clock()
	if now - last_swing_at < LOCAL_SWING_COOLDOWN then
		return
	end

	local character = player.Character
	if not character or tool.Parent ~= character then
		return
	end
	last_swing_at = now

	if active_swing_track then
		active_swing_track:Stop(0.02)
	end
	active_swing_track = play_named_animation(character, "ToolSlashAnim", 0.82)

	local trail = ensure_trail(tool)
	if trail then
		trail.Enabled = true
		task.delay(TRAIL_ACTIVE_SECONDS, function()
			if trail.Parent then
				trail.Enabled = false
			end
		end)
	end

	play_sound("rbxasset://sounds/swordslash.wav", 0.34, 0.95)
	swing_remote:FireServer()
end

local function connect_tool(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Bone Sword" then
		return
	end
	if connected[tool] then
		return
	end

	connected[tool] = true
	ensure_trail(tool)

	tool.Activated:Connect(function()
		start_swing(tool)
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
	active_swing_track = nil
end

if player.Character then
	on_character_added(player.Character)
end
player.CharacterAdded:Connect(on_character_added)

local function flash_target(target: Instance)
	if not target:IsA("Model") or target.Parent == nil then
		return
	end

	local old = target:FindFirstChild("LocalNecroHitFlash")
	if old and old:IsA("Highlight") then
		old:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "LocalNecroHitFlash"
	highlight.Adornee = target
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = Color3.fromRGB(245, 255, 250)
	highlight.OutlineColor = Color3.fromRGB(115, 255, 190)
	highlight.FillTransparency = 0.18
	highlight.OutlineTransparency = 0.05
	highlight.Parent = target

	TweenService:Create(
		highlight,
		TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			FillTransparency = 1,
			OutlineTransparency = 1,
		}
	):Play()
	Debris:AddItem(highlight, 0.22)
end

local hit_gui = Instance.new("ScreenGui")
hit_gui.Name = "NecroHitFeedback"
hit_gui.ResetOnSpawn = false
hit_gui.IgnoreGuiInset = true
hit_gui.Parent = player:WaitForChild("PlayerGui")

local hit_marker = Instance.new("TextLabel")
hit_marker.Name = "HitMarker"
hit_marker.AnchorPoint = Vector2.new(0.5, 0.5)
hit_marker.Position = UDim2.fromScale(0.5, 0.5)
hit_marker.Size = UDim2.fromOffset(80, 80)
hit_marker.BackgroundTransparency = 1
hit_marker.Font = Enum.Font.GothamBlack
hit_marker.Text = "+"
hit_marker.TextSize = 34
hit_marker.TextColor3 = Color3.fromRGB(245, 255, 250)
hit_marker.TextTransparency = 1
hit_marker.TextStrokeTransparency = 1
hit_marker.Parent = hit_gui

feedback_remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local targets = payload.targets
	if typeof(targets) == "table" then
		for _, target in ipairs(targets) do
			if typeof(target) == "Instance" then
				flash_target(target)
			end
		end
	end

	local killed = payload.killed == true
	hit_marker.Text = killed and "X" or "+"
	hit_marker.TextColor3 = killed
		and Color3.fromRGB(120, 255, 175)
		or Color3.fromRGB(245, 255, 250)
	hit_marker.TextTransparency = 0.02
	hit_marker.TextStrokeTransparency = 0.45
	hit_marker.TextSize = killed and 46 or 34

	play_sound(
		"rbxasset://sounds/electronicpingshort.wav",
		killed and 0.55 or 0.28,
		killed and 0.78 or 1.25
	)

	TweenService:Create(
		hit_marker,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			TextSize = killed and 58 or 43,
		}
	):Play()
end)
