--!strict
-- src/server/Services/UnitFactory.lua
-- Responsible for stamping unit attributes + stats on a unit model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnitConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UnitConfig"))

local UnitFactory = {}
UnitFactory.__index = UnitFactory

export type CreateArgs = {
    unit_type: string,
    faction: string, -- "Player" | "Wander" | "Named"
    owner_user_id: number?,
    owner_display: string?,
    display_name_override: string?,
}

function UnitFactory.new(collision_service)
    local self = setmetatable({}, UnitFactory)
    self._collision = collision_service
    return self
end

local function set_if_nil(model: Model, name: string, value: any)
    if model:GetAttribute(name) == nil then
        model:SetAttribute(name, value)
    end
end

function UnitFactory:stamp_unit(model: Model, args: CreateArgs)
    local stats = UnitConfig.get_stats(args.unit_type)

    model.Name = args.unit_type

    model:SetAttribute("UnitType", args.unit_type)
    model:SetAttribute("Faction", args.faction)
    model:SetAttribute("OwnerUserId", args.owner_user_id or 0)

    local display_name = args.display_name_override or stats.display_name
    model:SetAttribute("DisplayName", display_name)

    set_if_nil(model, "MaxHealth", stats.max_health)
    set_if_nil(model, "Health", stats.max_health)
    set_if_nil(model, "Damage", stats.damage)
    set_if_nil(model, "AttackRange", stats.attack_range)
    set_if_nil(model, "AttackCooldown", stats.attack_cooldown)
    set_if_nil(model, "MoveSpeed", stats.move_speed)

    -- Visual hint via primary part tint (server-side so everyone sees something).
    local primary = model.PrimaryPart
    if primary ~= nil then
        if args.faction == "Player" then
            primary.Color = Color3.fromRGB(120, 255, 120)
        elseif args.faction == "Named" then
            primary.Color = Color3.fromRGB(210, 120, 255)
        else
            primary.Color = Color3.fromRGB(255, 150, 150)
        end
    end

    if self._collision ~= nil then
        self._collision:apply_unit(model)
    end
end

return UnitFactory