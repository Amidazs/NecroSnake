--!strict
-- src/client/Services/UnitHighlightService.lua
-- Visually marks units that belong to the local player's army.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UnitHighlightService = {}
UnitHighlightService.__index = UnitHighlightService

local LOCAL_PLAYER = Players.LocalPlayer

local UPDATE_SECONDS = 0.4

function UnitHighlightService.new()
    local self = setmetatable({}, UnitHighlightService)
    self._accum = 0
    self._highlights = {} :: {[Model]: Highlight}
    return self
end

local function ensure_highlight(model: Model): Highlight
    local existing = model:FindFirstChild("UnitHighlight")
    if existing and existing:IsA("Highlight") then
        return existing
    end

    local h = Instance.new("Highlight")
    h.Name = "UnitHighlight"
    h.FillTransparency = 0.85
    h.OutlineTransparency = 0
    h.Parent = model
    return h
end

function UnitHighlightService:init()
    print("[UnitHighlightService] Ready.")
    RunService.Heartbeat:Connect(function(dt)
        self:_step(dt)
    end)
end

function UnitHighlightService:_step(dt: number)
    self._accum += dt
    if self._accum < UPDATE_SECONDS then
        return
    end
    self._accum = 0

    local active = 0

    for model, h in pairs(self._highlights) do
        if model.Parent == nil then
            self._highlights[model] = nil
        end
    end

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") and inst:GetAttribute("UnitType") ~= nil then
            local faction = inst:GetAttribute("Faction")
            local owner_id = inst:GetAttribute("OwnerUserId")

            if faction == "Player" and owner_id == LOCAL_PLAYER.UserId then
                local h = self._highlights[inst]
                if h == nil then
                    h = ensure_highlight(inst)
                    self._highlights[inst] = h
                end
                h.Enabled = true
                active += 1
            else
                local h = self._highlights[inst]
                if h ~= nil then
                    h.Enabled = false
                end
            end
        end
    end

    print(("[UnitHighlightService] Local highlights active: %d"):format(active))
end

return UnitHighlightService