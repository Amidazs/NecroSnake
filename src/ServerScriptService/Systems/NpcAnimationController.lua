--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type NpcAnimationController = {
	start: (self: NpcAnimationController) -> (),
	stop: (self: NpcAnimationController) -> (),
}

local NpcAnimationController = {}
NpcAnimationController.__index = NpcAnimationController

local SCHEDULER_STEP = 0.1
local NEAR_DISTANCE = 100
local MID_DISTANCE = 220
local ANIMATION_CULL_DISTANCE = 350
local DENSE_ARMY_FULL_ANIMATION_DISTANCE = 35
local DENSE_ARMY_HALF_ANIMATION_DISTANCE = 60
local NEAR_UPDATE_SECONDS = 0.15
local MID_UPDATE_SECONDS = 0.35
local FAR_UPDATE_SECONDS = 0.8
local WALK_SPEED_SCALE = 16
local MOVE_THRESHOLD = 0.6

local active_controllers: { [any]: boolean } = {}
local scheduler_connection: RBXScriptConnection? = nil
local scheduler_accumulator = 0

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end
local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function get_animation(model: Model, name: string): Animation?
	local folder = model:FindFirstChild("Animations")
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	local animation = folder:FindFirstChild(name)
	if animation and animation:IsA("Animation") then
		return animation
	end
	return nil
end

local function get_player_positions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and get_root(character) or nil
		if root then
			table.insert(positions, root.Position)
		end
	end
	return positions
end
local function get_update_interval(
	position: Vector3,
	player_positions: { Vector3 }
): number
	local nearest = math.huge
	for _, player_position in ipairs(player_positions) do
		nearest = math.min(nearest, (position - player_position).Magnitude)
	end

	if nearest <= NEAR_DISTANCE then
		return NEAR_UPDATE_SECONDS
	end
	if nearest <= MID_DISTANCE then
		return MID_UPDATE_SECONDS
	end
	return FAR_UPDATE_SECONDS
end

local function stop_all_tracks(animator: Animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
		track:Destroy()
	end
end

local function ensure_scheduler()
	if scheduler_connection then
		return
	end
	scheduler_connection = RunService.Heartbeat:Connect(function(delta_time)
		scheduler_accumulator += delta_time
		if scheduler_accumulator < SCHEDULER_STEP then
			return
		end
		scheduler_accumulator = 0

		local current_time = os.clock()
		local player_positions = get_player_positions()
		local has_active = false

		for controller in pairs(active_controllers) do
			has_active = true
			if controller._model.Parent == nil then
				controller:stop()
			else
				controller:_step(current_time, player_positions)
			end
		end

		if not has_active and scheduler_connection then
			scheduler_connection:Disconnect()
			scheduler_connection = nil
		end
	end)
end
function NpcAnimationController.new(model: Model): NpcAnimationController
	local self = setmetatable({}, NpcAnimationController)

	self._model = model
	self._humanoid = get_humanoid(model)
	self._root = get_root(model)
	self._animator = nil :: Animator?
	self._idle_track = nil :: AnimationTrack?
	self._walk_track = nil :: AnimationTrack?
	self._running = false
	self._next_update_time = 0

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

	local idle_animation = get_animation(self._model, "Idle")
	local walk_animation = get_animation(self._model, "Walk")
	if not idle_animation or not walk_animation then
		return
	end

	self._idle_track = self._humanoid:LoadAnimation(idle_animation)
	self._idle_track.Priority = Enum.AnimationPriority.Core

	self._walk_track = self._humanoid:LoadAnimation(walk_animation)
	self._walk_track.Priority = Enum.AnimationPriority.Core
end

function NpcAnimationController:_set_idle()
	if self._walk_track and self._walk_track.IsPlaying then
		self._walk_track:Stop(0.15)
	end
	if self._idle_track and not self._idle_track.IsPlaying then
		self._idle_track:Play(0.15)
	end
end

function NpcAnimationController:_set_walk(planar_speed: number)
	if self._idle_track and self._idle_track.IsPlaying then
		self._idle_track:Stop(0.15)
	end
	if self._walk_track and not self._walk_track.IsPlaying then
		self._walk_track:Play(0.15)
	end
	if self._walk_track then
		self._walk_track:AdjustSpeed(
			math.clamp(planar_speed / WALK_SPEED_SCALE, 0.3, 2)
		)
	end
end

function NpcAnimationController:_stop_motion_tracks()
	if self._idle_track and self._idle_track.IsPlaying then
		self._idle_track:Stop(0.1)
	end
	if self._walk_track and self._walk_track.IsPlaying then
		self._walk_track:Stop(0.1)
	end
end
function NpcAnimationController:_step(
	current_time: number,
	player_positions: { Vector3 }
)
	if not self._root or not self._humanoid then
		return
	end
	if current_time < self._next_update_time then
		return
	end

	local nearest_distance = math.huge
	for _, player_position in ipairs(player_positions) do
		nearest_distance = math.min(
			nearest_distance,
			(self._root.Position - player_position).Magnitude
		)
	end

	local interval = get_update_interval(
		self._root.Position,
		player_positions
	)
	self._next_update_time = current_time + interval

	if nearest_distance > ANIMATION_CULL_DISTANCE then
		self:_stop_motion_tracks()
		return
	end

	if self._model:GetAttribute("IsPlayerArmy") == true then
		local unit_id = self._model:GetAttribute("ArmyUnitId")
		local stable_id = typeof(unit_id) == "number"
			and math.floor(unit_id)
			or 0
		local should_animate = true
		if nearest_distance > DENSE_ARMY_HALF_ANIMATION_DISTANCE then
			should_animate = stable_id % 3 == 0
		elseif nearest_distance > DENSE_ARMY_FULL_ANIMATION_DISTANCE then
			should_animate = stable_id % 2 == 0
		end
		if not should_animate then
			self:_stop_motion_tracks()
			return
		end
	end

	if self._humanoid.Health <= 0 then
		self:_stop_motion_tracks()
		return
	end

	local velocity = self._root.AssemblyLinearVelocity
	local planar_speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
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
	self:_set_idle()

	active_controllers[self] = true
	ensure_scheduler()
end

function NpcAnimationController:stop()
	if not self._running then
		return
	end
	self._running = false
	active_controllers[self] = nil

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
