local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Hotfix = {}

local WORLD_NAME = "NecromancerMVP_World"
local UNITS_NAME = "Units"
local LEADERS_NAME = "Leaders"

-- IMPORTANT: widen range so we definitely trigger while debugging
local ATTACK_RANGE = 30
local POSE_COOLDOWN = 0.55
local POSE_HOLD_SECONDS = 0.18
local POSE_UP_DEG = 55

local AXIS = "Z"
local SIGN = 1

local SPEED_SYNC_INTERVAL = 0.50
local COMBAT_SCAN_INTERVAL = 0.20

local DEBUG_EVERY_SECONDS = 2.5
local last_debug_t = 0
local last_pose_t = {}

local function now()
    return os.clock()
end

local function dbg(msg, ...)
    local text = msg
    if select("#", ...) > 0 then
        text = string.format(msg, ...)
    end
    print(("ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Âª [HOTFIX] %s"):format(text))
end

local function dbg_throttled(msg, ...)
    local t = now()
    if (t - last_debug_t) < DEBUG_EVERY_SECONDS then
        return
    end
    last_debug_t = t
    dbg(msg, ...)
end

local function get_world()
    return Workspace:FindFirstChild(WORLD_NAME)
end

local function get_folder(world, name)
    if not world then
        return nil
    end

    local f = world:FindFirstChild(name)
    if f and f:IsA("Folder") then
        return f
    end

    return nil
end

local function get_units_folder()
    return get_folder(get_world(), UNITS_NAME)
end

local function get_leaders_folder()
    return get_folder(get_world(), LEADERS_NAME)
end

local function get_model_hrp(model)
    if not model or not model:IsA("Model") then
        return nil
    end

    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end

    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end

    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function get_humanoid(model)
    if not model then
        return nil
    end
    return model:FindFirstChildOfClass("Humanoid")
end

local function get_owner_id(model)
    local hrp = get_model_hrp(model)
    if not hrp then
        return nil
    end
    return hrp:GetAttribute("OwnerId")
end

local function build_transform(angle_rad)
    if AXIS == "X" then
        return CFrame.Angles(angle_rad, 0, 0)
    end
    return CFrame.Angles(0, 0, angle_rad)
end

local function find_shoulders(model)
    local motors = {}
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Motor6D") then
            if inst.Name == "RightShoulder" or inst.Name == "LeftShoulder" then
                table.insert(motors, inst)
            end
        end
    end
    return motors
end

local function play_pose_once(model, reason)
    local t = now()
    local last = last_pose_t[model]
    if last and (t - last) < POSE_COOLDOWN then
        return false
    end
    last_pose_t[model] = t

    local shoulders = find_shoulders(model)
    if #shoulders == 0 then
        dbg_throttled("PoseSkip: rig=%s no shoulders (%s)", model.Name, reason)
        return false
    end

    local angle = math.rad(POSE_UP_DEG) * SIGN
    local up = build_transform(angle)
    local down = CFrame.new()

    dbg("POSE: rig=%s reason=%s shoulders=%d axis=%s sign=%d",
        model:GetFullName(), reason, #shoulders, AXIS, SIGN)

    for _, m in ipairs(shoulders) do
        m.Transform = up
    end

    task.delay(POSE_HOLD_SECONDS, function()
        if not model.Parent then
            return
        end
        for _, m in ipairs(shoulders) do
            if m.Parent then
                m.Transform = down
            end
        end
    end)

    return true
end

local function iter_unit_models()
    local units = get_units_folder()
    if not units then
        return {}
    end

    local models = {}
    for _, child in ipairs(units:GetChildren()) do
        if child:IsA("Model") then
            table.insert(models, child)
        end
    end
    return models
end

local function iter_npc_leader_parts()
    local leaders = get_leaders_folder()
    if not leaders then
        return {}
    end

    local parts = {}
    for _, inst in ipairs(leaders:GetDescendants()) do
        if inst:IsA("BasePart") then
            local owner_id = inst:GetAttribute("OwnerId")
            if owner_id ~= nil then
                table.insert(parts, inst)
            end
        end
    end
    return parts
end

local function get_target_points()
    local points = {}

    for _, p in ipairs(Players:GetPlayers()) do
        local char = p.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then
                table.insert(points, {
                    OwnerId = p.UserId,
                    Pos = hrp.Position,
                    Tag = "Player",
                })
            end
        end
    end

    for _, part in ipairs(iter_npc_leader_parts()) do
        table.insert(points, {
            OwnerId = part:GetAttribute("OwnerId"),
            Pos = part.Position,
            Tag = "LeaderPart:" .. part.Name,
        })
    end

    for _, model in ipairs(iter_unit_models()) do
        local hrp = get_model_hrp(model)
        if hrp then
            local owner_id = hrp:GetAttribute("OwnerId")
            if owner_id ~= nil then
                table.insert(points, {
                    OwnerId = owner_id,
                    Pos = hrp.Position,
                    Tag = "Unit:" .. model.Name,
                })
            end
        end
    end

    return points
end

local function scan_for_combat_and_pose()
    local models = iter_unit_models()
    local targets = get_target_points()

    if #models == 0 then
        dbg_throttled("CombatScan: models=0")
        return
    end

    if #targets == 0 then
        dbg_throttled("CombatScan: targets=0")
        return
    end

    local posed = 0
    local checked = 0

    for _, model in ipairs(models) do
        local hrp = get_model_hrp(model)
        if hrp then
            local my_owner = hrp:GetAttribute("OwnerId")
            if my_owner ~= nil then
                local best_dist = ATTACK_RANGE
                local best_tag = nil
                local best_owner = nil

                for _, t in ipairs(targets) do
                    if t.OwnerId ~= my_owner then
                        local d = (hrp.Position - t.Pos).Magnitude
                        if d < best_dist then
                            best_dist = d
                            best_tag = t.Tag
                            best_owner = t.OwnerId
                        end
                    end
                end

                checked += 1

                if best_tag then
                    posed += 1
                    play_pose_once(model,
                        ("near enemy owner=%s tag=%s dist=%.1f")
                            :format(tostring(best_owner), tostring(best_tag),
                                best_dist)
                    )
                end
            end
        end
    end

    dbg_throttled("CombatScan: models=%d targets=%d checked=%d posedCandidates=%d",
        #models, #targets, checked, posed)
end

local function sync_player_army_speed()
    local models = iter_unit_models()
    if #models == 0 then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not char then
            continue
        end

        local ph = char:FindFirstChildOfClass("Humanoid")
        if not ph then
            continue
        end

        local desired = ph.WalkSpeed
        local changed = 0
        local seen = 0

        for _, model in ipairs(models) do
            local owner_id = get_owner_id(model)
            if owner_id == player.UserId then
                seen += 1
                local hum = get_humanoid(model)
                if hum and hum.WalkSpeed ~= desired then
                    hum.WalkSpeed = desired
                    changed += 1
                end
            end
        end

        dbg_throttled("SpeedSync: player=%s desired=%d armyUnits=%d changed=%d",
            player.Name, desired, seen, changed)
    end
end

function Hotfix.start()
    if not RunService:IsServer() then
        warn("ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â°ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¸ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Âª [HOTFIX] Must run on SERVER.")
        return
    end

    dbg("Hotfix starting (deep debug). ATTACK_RANGE=%d", ATTACK_RANGE)

    task.spawn(function()
        while true do
            sync_player_army_speed()
            task.wait(SPEED_SYNC_INTERVAL)
        end
    end)

    task.spawn(function()
        while true do
            scan_for_combat_and_pose()
            task.wait(COMBAT_SCAN_INTERVAL)
        end
    end)
end

return Hotfix