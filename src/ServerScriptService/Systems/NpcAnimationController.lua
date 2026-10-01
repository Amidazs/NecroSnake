--!strict

-- Server-side animation controller for NPC humanoids.
-- Uses an "Animations" folder on the model with Animation instances:
--   - Idle
--   - Walk
--
-- If missing, callers may create them before starting the controller.

local RunService = game:GetService("RunService")

export type NpcAnimationController = {
	start: (self: NpcAnimationController) -> (),
	stop: (self: NpcAnimationController) -> (),
}

type Humanoid = Humanoid

local NpcAnimationController = {}
NpcAnimationController.__index = NpcAnimationController

local UPDATE_DT = 0.15
local WALK_SPEED_SCALE = 16.0
local MOVE_THRESHOLD = 0.6

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function get_humanoid(model: Model): Humanoid?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		return hum
	end
	return nil
end

local function get_animation(model: Model, name: string): Animation?
	local folder = model:FindFirstChild("Animations")
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	local anim = folder:FindFirstChild(name)
	if anim and anim:IsA("Animation") then
		return anim
	end

	return nil
end

local function stop_all_tracks(animator: Animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
		track:Destroy()
	end
end

function NpcAnimationController.new(model: Model): NpcAnimationController
	local self = setmetatable({}, NpcAnimationController)

	self._model = model
	self._humanoid = get_humanoid(model)
	self._root = get_root(model)
	self._animator = nil :: Animator?
	self._idle_track = nil :: AnimationTrack?
	self._walk_track = nil :: AnimationTrack?
	self._conn = nil :: RBXScriptConnection?
	self._accum = 0
	self._running = false

	return self
end

function NpcAnimationController:_ensure_animator()
	if not self._humanoid then
		return
	end

	local animator = self._humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = self._humanoid
	end

	self._animator = animator
	stop_all_tracks(animator)
end

function NpcAnimationController:_load_tracks()
	if not self._humanoid then
		return
	end

	local idle_anim = get_animation(self._model, "Idle")
	local walk_anim = get_animation(self._model, "Walk")

	if not idle_anim or not walk_anim then
		return
	end

	self._idle_track = self._humanoid:LoadAnimation(idle_anim)
	self._idle_track.Priority = Enum.AnimationPriority.Core

	self._walk_track = self._humanoid:LoadAnimation(walk_anim)
	self._walk_track.Priority = Enum.AnimationPriority.Core
end

function NpcAnimationController:_set_idle()
	if self._walk_track then
		self._walk_track:Stop(0.15)
	end
	if self._idle_track and not self._idle_track.IsPlaying then
		self._idle_track:Play(0.15)
	end
end

function NpcAnimationController:_set_walk(planar_speed: number)
	if self._idle_track then
		self._idle_track:Stop(0.15)
	end
	if self._walk_track and not self._walk_track.IsPlaying then
		self._walk_track:Play(0.15)
	end
	if self._walk_track then
		self._walk_track:AdjustSpeed(math.clamp(planar_speed / WALK_SPEED_SCALE, 0.3, 2.0))
	end
end

function NpcAnimationController:_step(dt: number)
	if not self._root or not self._humanoid then
		return
	end

	if self._humanoid.Health <= 0 then
		return
	end

	self._accum += dt
	if self._accum < UPDATE_DT then
		return
	end
	self._accum = 0

	local v = self._root.AssemblyLinearVelocity
	local planar_speed = Vector3.new(v.X, 0, v.Z).Magnitude

	if planar_speed > MOVE_THRESHOLD then
		self:_set_walk(planar_speed)
	else
		self:_set_idle()
	end
end

function NpcAnimationController:start()
	if self._running then
		return
	end
	self._running = true

	self:_ensure_animator()
	self:_load_tracks()

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_step(dt)
	end)

	-- Default to idle.
	self:_set_idle()
end

function NpcAnimationController:stop()
	self._running = false

	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	if self._idle_track then
		self._idle_track:Stop(0)
		self._idle_track:Destroy()
		self._idle_track = nil
	end

	if self._walk_track then
		self._walk_track:Stop(0)
		self._walk_track:Destroy()
		self._walk_track = nil
	end
end

return NpcAnimationController
