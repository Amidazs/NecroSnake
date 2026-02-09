--!strict
-- src/client/Services/UnitBillboardService.lua
-- Shows name + health bar above units. Uses attributes replicated from server.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UnitBillboardService = {}
UnitBillboardService.__index = UnitBillboardService

local LOCAL_PLAYER = Players.LocalPlayer

local MAX_DISTANCE = 140
local UPDATE_SECONDS = 0.25

local function get_primary(model: Model): BasePart?
    return model.PrimaryPart
end

local function ensure_billboard(model: Model): BillboardGui
    local existing = model:FindFirstChild("UnitBillboard")
    if existing and existing:IsA("BillboardGui") then
        return existing
    end

    local bb = Instance.new("BillboardGui")
    bb.Name = "UnitBillboard"
    bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 180, 0, 48)
    bb.StudsOffset = Vector3.new(0, 4.6, 0)
    bb.Parent = model

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, 0, 0, 18)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.TextScaled = true
    title.Font = Enum.Font.GothamBold
    title.Text = "Unit"
    title.Parent = bb

    local bar_bg = Instance.new("Frame")
    bar_bg.Name = "BarBG"
    bar_bg.Size = UDim2.new(1, -14, 0, 10)
    bar_bg.Position = UDim2.new(0, 7, 0, 24)
    bar_bg.BorderSizePixel = 0
    bar_bg.BackgroundTransparency = 0.2
    bar_bg.Parent = bb

    local bar = Instance.new("Frame")
    bar.Name = "Bar"
    bar.Size = UDim2.new(1, 0, 1, 0)
    bar.Position = UDim2.new(0, 0, 0, 0)
    bar.BorderSizePixel = 0
    bar.Parent = bar_bg

    return bb
end

local function update_billboard(bb: BillboardGui, model: Model)
    local title = bb:FindFirstChild("Title") :: TextLabel?
    local bg = bb:FindFirstChild("BarBG") :: Frame?
    local bar = bg and bg:FindFirstChild("Bar") :: Frame?

    local display = model:GetAttribute("DisplayName")
    if typeof(display) ~= "string" then
        display = model.Name
    end

    local hp = model:GetAttribute("Health")
    local max_hp = model:GetAttribute("MaxHealth")

    if title then
        title.Text = tostring(display)
    end

    if typeof(hp) == "number" and typeof(max_hp) == "number" and bar then
        local pct = 0
        if max_hp > 0 then
            pct = math.clamp(hp / max_hp, 0, 1)
        end
        bar.Size = UDim2.new(pct, 0, 1, 0)
    end
end

function UnitBillboardService.new()
    local self = setmetatable({}, UnitBillboardService)
    self._accum = 0
    self._tracked = {} :: {[Model]: BillboardGui}
    return self
end

function UnitBillboardService:init()
    print("[UnitBillboardService] Ready.")
    RunService.Heartbeat:Connect(function(dt)
        self:_step(dt)
    end)
end

function UnitBillboardService:_step(dt: number)
    self._accum += dt
    if self._accum < UPDATE_SECONDS then
        return
    end
    self._accum = 0

    local char = LOCAL_PLAYER.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp == nil then
        return
    end

    local count_visible = 0
    local count_total = 0

    for model, bb in pairs(self._tracked) do
        if model.Parent == nil then
            self._tracked[model] = nil
        end
    end

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("Model") and inst:GetAttribute("UnitType") ~= nil then
            count_total += 1

            local primary = get_primary(inst)
            if primary ~= nil then
                local d = (primary.Position - hrp.Position).Magnitude
                local within = d <= MAX_DISTANCE

                local bb = self._tracked[inst]
                if bb == nil then
                    bb = ensure_billboard(inst)
                    self._tracked[inst] = bb
                end

                bb.Enabled = within
                if within then
                    count_visible += 1
                    update_billboard(bb, inst)
                end
            end
        end
    end

    print(("[UnitBillboardService] Visible UI: %d/%d within %dstuds"):format(
        count_visible, count_total, MAX_DISTANCE
    ))
end

return UnitBillboardService