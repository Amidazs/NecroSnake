--!strict

local Players = game:GetService("Players")

local UnitController = {}
UnitController.__index = UnitController

local DEFAULT_DAMAGE = 10
local DEFAULT_ATTACK_COOLDOWN = 0.8

-- Formation tuning (kept as constants for now; can be promoted to config later)
local BASE_DISTANCE = 7
local RING_SPACING = 2.5
local SLOTS_PER_RING = 24

local function get_humanoid(model: Model): Humanoid?
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum
    end
    return nil
end

local function get_root(model: Model): BasePart?
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end

    local primary = model.PrimaryPart
    if primary and primary:IsA("BasePart") then
        return primary
    end

    return nil
end

local function compute_formation_offset(slot_index: number): Vector3
    -- Fill inner ring first, then expand.
    local ring = math.floor(slot_index / SLOTS_PER_RING)
    local slot = slot_index % SLOTS_PER_RING

    local radius = BASE_DISTANCE + (ring * RING_SPACING)
    local angle = (slot / SLOTS_PER_RING) * (math.pi * 2)

    return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function UnitController.new(unit_model: Model, owner: Player, formation_index: number)
    local self = setmetatable({}, UnitController)

    self.model = unit_model
    self.owner = owner
    self.formation_index = formation_index

    self._running = false
    self._task = nil :: thread?
    self._last_attack = 0

    return self
end

function UnitController:start()
    if self._running then
        return
    end
    self._running = true

    self._task = task.spawn(function()
        while self._running do
            self:_tick()
            task.wait(0.25)
        end
    end)
end

function UnitController:stop()
    self._running = false
end

function UnitController:_tick()
    local owner_character = self.owner.Character
    if not owner_character then
        return
    end

    local owner_root = get_root(owner_character)
    if not owner_root then
        return
    end

    local unit_root = get_root(self.model)
    local unit_humanoid = get_humanoid(self.model)
    if not unit_root or not unit_humanoid then
        return
    end

    local target = owner_root.Position + compute_formation_offset(self.formation_index)
    unit_humanoid:MoveTo(target)

    local closest_target_model = nil :: Model?
    local closest_root = nil :: BasePart?
    local closest_humanoid = nil :: Humanoid?
    local closest_dist = math.huge

    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= self.model and m ~= owner_character then
            local hum = get_humanoid(m)
            local root = get_root(m)
            if hum and root and hum.Health > 0 then
                local owner_tag = m:FindFirstChild("Owner")
                if owner_tag == nil then
                    local dist = (unit_root.Position - root.Position).Magnitude
                    if dist < closest_dist and dist < 20 then
                        closest_dist = dist
                        closest_target_model = m
                        closest_root = root
                        closest_humanoid = hum
                    end
                end
            end
        end
    end

    if not closest_root or not closest_humanoid or closest_humanoid.Health <= 0 then
        return
    end

    unit_humanoid:MoveTo(closest_root.Position)

    local now_time = os.clock()
    if (now_time - self._last_attack) < DEFAULT_ATTACK_COOLDOWN then
        return
    end

    local dist = (unit_root.Position - closest_root.Position).Magnitude
    if dist <= 4 then
        self._last_attack = now_time
        closest_humanoid:TakeDamage(DEFAULT_DAMAGE)
    end
end

return UnitController
