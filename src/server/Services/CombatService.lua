--!strict
-- src/server/Services/CombatService.lua
-- Handles unit-vs-unit and unit-vs-player damage. Allows multiple attackers.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CombatService = {}
CombatService.__index = CombatService

local function get_primary(model: Model): BasePart?
    return model.PrimaryPart
end

local function is_alive(model: Model): boolean
    local hp = model:GetAttribute("Health")
    return typeof(hp) == "number" and hp > 0
end

local function distance(a: Vector3, b: Vector3): number
    return (a - b).Magnitude
end

local function safe_take_damage_humanoid(h: Humanoid, dmg: number)
    if dmg <= 0 then
        return
    end
    if h.Health <= 0 then
        return
    end
    h:TakeDamage(dmg)
end

function CombatService.new(army_service)
    local self = setmetatable({}, CombatService)
    self._army_service = army_service
    self._last_attack = {} :: {[Model]: number}
    return self
end

function CombatService:init()
    print("[CombatService] Ready.")
    RunService.Heartbeat:Connect(function(dt)
        self:_tick(dt)
    end)
end

function CombatService:_can_attack(attacker: Model, now: number): boolean
    local cooldown = attacker:GetAttribute("AttackCooldown")
    if typeof(cooldown) ~= "number" then
        cooldown = 1.1
    end

    local last = self._last_attack[attacker]
    if last == nil then
        return true
    end

    return (now - last) >= cooldown
end

function CombatService:_mark_attacked(attacker: Model, now: number)
    self._last_attack[attacker] = now
end

function CombatService:_damage_unit(attacker: Model, target: Model)
    local dmg = attacker:GetAttribute("Damage")
    if typeof(dmg) ~= "number" then
        dmg = 5
    end

    local hp = target:GetAttribute("Health")
    local max_hp = target:GetAttribute("MaxHealth")
    if typeof(hp) ~= "number" then
        return
    end
    if typeof(max_hp) ~= "number" then
        max_hp = hp
    end

    local new_hp = math.max(0, hp - dmg)
    target:SetAttribute("Health", new_hp)

    if new_hp <= 0 then
        self:_on_unit_died(attacker, target)
    end
end

function CombatService:_on_unit_died(attacker: Model, victim: Model)
    -- Keep your existing raising logic if you already have it in ArmyService.
    -- Here we just notify + destroy.
    victim:SetAttribute("Dead", true)
    task.defer(function()
        if victim.Parent ~= nil then
            victim:Destroy()
        end
    end)

    local killer_id = attacker:GetAttribute("OwnerUserId")
    if killer_id == nil then
        killer_id = "?"
    end

    local victim_type = victim:GetAttribute("UnitType") or victim.Name
    print(("[CombatService] Unit died: killer=%s type=%s"):format(tostring(killer_id), tostring(victim_type)))

    -- Optional: raise on kill if ArmyService exposes it.
    if self._army_service and self._army_service.try_raise_on_kill then
        self._army_service:try_raise_on_kill(attacker, victim)
    end
end

function CombatService:_nearest_enemy_unit(attacker: Model): Model?
    local a_primary = get_primary(attacker)
    if a_primary == nil then
        return nil
    end

    local faction = attacker:GetAttribute("Faction")
    local owner_id = attacker:GetAttribute("OwnerUserId")

    local range = attacker:GetAttribute("AttackRange")
    if typeof(range) ~= "number" then
        range = 6
    end

    local best: Model? = nil
    local best_dist = range

    for _, candidate in ipairs(self._army_service:get_all_units()) do
        if candidate ~= attacker and candidate.Parent ~= nil and is_alive(candidate) then
            local c_primary = get_primary(candidate)
            if c_primary ~= nil then
                local c_faction = candidate:GetAttribute("Faction")
                local c_owner = candidate:GetAttribute("OwnerUserId")

                local same_team = false
                if faction == "Player" and c_faction == "Player" then
                    same_team = (owner_id == c_owner)
                else
                    same_team = (faction == c_faction)
                end

                if not same_team then
                    local d = distance(a_primary.Position, c_primary.Position)
                    if d <= best_dist then
                        best = candidate
                        best_dist = d
                    end
                end
            end
        end
    end

    return best
end

function CombatService:_nearest_enemy_player(attacker: Model): Humanoid?
    local a_primary = get_primary(attacker)
    if a_primary == nil then
        return nil
    end

    local range = attacker:GetAttribute("AttackRange")
    if typeof(range) ~= "number" then
        range = 6
    end

    local owner_id = attacker:GetAttribute("OwnerUserId")
    local faction = attacker:GetAttribute("Faction")

    local best_h: Humanoid? = nil
    local best_dist = range

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character ~= nil then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hum ~= nil and hrp ~= nil and hum.Health > 0 then
                -- Player-owned units shouldn't hit their own owner.
                if not (faction == "Player" and plr.UserId == owner_id) then
                    local d = distance(a_primary.Position, hrp.Position)
                    if d <= best_dist then
                        best_h = hum
                        best_dist = d
                    end
                end
            end
        end
    end

    return best_h
end

function CombatService:_tick(_: number)
    local now = os.clock()

    for _, attacker in ipairs(self._army_service:get_all_units()) do
        if attacker.Parent ~= nil and is_alive(attacker) then
            if self:_can_attack(attacker, now) then
                -- 1) Prefer hitting units (keeps battles feeling "army vs army")
                local unit_target = self:_nearest_enemy_unit(attacker)
                if unit_target ~= nil then
                    self:_damage_unit(attacker, unit_target)
                    self:_mark_attacked(attacker, now)
                else
                    -- 2) If no unit in range, hit a player if in range
                    local player_target = self:_nearest_enemy_player(attacker)
                    if player_target ~= nil then
                        local dmg = attacker:GetAttribute("Damage")
                        if typeof(dmg) ~= "number" then
                            dmg = 5
                        end
                        safe_take_damage_humanoid(player_target, dmg)
                        self:_mark_attacked(attacker, now)
                    end
                end
            end
        end
    end
end

return CombatService