--!strict

-- UnitVisuals.lua
-- Adds:
--   - Unit name + health bar overhead
--   - "Belongs to player" visuals (Highlight + optional tint)
-- Intended to be called when a unit spawns.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local UnitVisuals = {}

local function get_primary_part(model: Model): BasePart?
    if model.PrimaryPart then
        return model.PrimaryPart
    end

    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        return head
    end

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            return desc
        end
    end

    return nil
end

local function create_billboard(): BillboardGui
    local gui = Instance.new("BillboardGui")
    gui.Name = "UnitOverhead"
    gui.Size = UDim2.new(0, 160, 0, 46)
    gui.StudsOffset = Vector3.new(0, 3.2, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 200

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(1, 0, 0, 18)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = "Unit"
    nameLabel.TextStrokeTransparency = 0.4
    nameLabel.Parent = gui

    local bg = Instance.new("Frame")
    bg.Name = "HealthBG"
    bg.BorderSizePixel = 0
    bg.BackgroundTransparency = 0.2
    bg.Size = UDim2.new(1, 0, 0, 10)
    bg.Position = UDim2.new(0, 0, 0, 24)
    bg.Parent = gui

    local bar = Instance.new("Frame")
    bar.Name = "Health"
    bar.BorderSizePixel = 0
    bar.Size = UDim2.new(1, 0, 1, 0)
    bar.Position = UDim2.new(0, 0, 0, 0)
    bar.Parent = bg

    return gui
end

local function set_owner_highlight(model: Model, owner_user_id: number?)
    local highlight = model:FindFirstChildOfClass("Highlight")
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "OwnerHighlight"
        highlight.DepthMode = Enum.HighlightDepthMode.Occluded
        highlight.FillTransparency = 0.65
        highlight.OutlineTransparency = 0.1
        highlight.Parent = model
    end

    if owner_user_id then
        local owner = Players:GetPlayerByUserId(owner_user_id)
        if owner then
            highlight.OutlineColor = owner.TeamColor.Color
            highlight.FillColor = owner.TeamColor.Color
            return
        end
    end

    -- Enemy / neutral
    highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
    highlight.FillColor = Color3.fromRGB(255, 80, 80)
end

function UnitVisuals.apply(unit_model: Model, display_name: string, owner_user_id: number?)
    local primary = get_primary_part(unit_model)
    if not primary then
        return
    end

    local humanoid = unit_model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    local gui = unit_model:FindFirstChild("UnitOverhead")
    if gui and gui:IsA("BillboardGui") then
        -- Reuse existing
    else
        gui = create_billboard()
        gui.Adornee = primary
        gui.Parent = unit_model
    end

    local nameLabel = gui:FindFirstChild("Name")
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Text = display_name
    end

    local healthBg = gui:FindFirstChild("HealthBG")
    local healthBar = nil
    if healthBg and healthBg:IsA("Frame") then
        healthBar = healthBg:FindFirstChild("Health")
    end

    local function update_bar()
        if not healthBar or not healthBar:IsA("Frame") then
            return
        end

        local max = math.max(1, humanoid.MaxHealth)
        local pct = math.clamp(humanoid.Health / max, 0, 1)
        healthBar.Size = UDim2.new(pct, 0, 1, 0)
    end

    update_bar()
    humanoid.HealthChanged:Connect(update_bar)

    set_owner_highlight(unit_model, owner_user_id)
end

return UnitVisuals
