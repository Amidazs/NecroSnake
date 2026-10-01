--!strict

local RunService = game:GetService("RunService")

local NpcAnimationDriver = {}

local WALK_SPEED_THRESHOLD = 0.1

local function get_humanoid(model: Model): Humanoid?
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid:IsA("Humanoid") then
        return humanoid
    end
    return nil
end

local function ensure_animator(humanoid: Humanoid): Animator
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator and animator:IsA("Animator") then
        return animator
    end

    animator = Instance.new("Animator")
    animator.Parent = humanoid
    return animator
end

local function get_animation_folder(model: Model): Folder?
    local folder = model:FindFirstChild("Animations")
    if folder and folder:IsA("Folder") then
        return folder
    end
    return nil
end

local function load_track(animator: Animator, anim: Animation?): AnimationTrack?
    if not anim then
        return nil
    end
    if not anim:IsA("Animation") then
        return nil
    end
    if anim.AnimationId == "" then
        return nil
    end

    local track = animator:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Movement
    return track
end

function NpcAnimationDriver.attach(model: Model)
    local humanoid = get_humanoid(model)
    if not humanoid then
        return
    end

    local animator = ensure_animator(humanoid)
    local anim_folder = get_animation_folder(model)
    if not anim_folder then
        return
    end

    local idle_anim = anim_folder:FindFirstChild("Idle") :: Animation?
    local walk_anim = anim_folder:FindFirstChild("Walk") :: Animation?

    local idle_track = load_track(animator, idle_anim)
    local walk_track = load_track(animator, walk_anim)

    if not idle_track and not walk_track then
        return
    end

    local function play_idle()
        if walk_track and walk_track.IsPlaying then
            walk_track:Stop(0.15)
        end
        if idle_track and not idle_track.IsPlaying then
            idle_track:Play(0.15)
        end
    end

    local function play_walk()
        if idle_track and idle_track.IsPlaying then
            idle_track:Stop(0.15)
        end
        if walk_track and not walk_track.IsPlaying then
            walk_track:Play(0.15)
        end
    end

    play_idle()

    -- Switch based on current movement.
    local heartbeat_conn
    heartbeat_conn = RunService.Heartbeat:Connect(function()
        if not model.Parent then
            heartbeat_conn:Disconnect()
            return
        end

        if humanoid.Health <= 0 then
            play_idle()
            return
        end

        local speed = humanoid.MoveDirection.Magnitude
        if speed > WALK_SPEED_THRESHOLD then
            play_walk()
        else
            play_idle()
        end
    end)
end

return NpcAnimationDriver
