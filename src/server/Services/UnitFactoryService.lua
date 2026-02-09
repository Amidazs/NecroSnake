local UnitFactoryService = {}

local ModelLibraryService = require(script.Parent.ModelLibraryService)

local function weld_visual_to_core(core, visual_model)
    if not visual_model.PrimaryPart then
        local pp = visual_model:FindFirstChildWhichIsA("BasePart", true)
        if not pp then
            return false
        end
        visual_model.PrimaryPart = pp
    end

    visual_model:SetPrimaryPartCFrame(core.CFrame)

    for _, part in ipairs(visual_model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Massless = true

            local weld = Instance.new("WeldConstraint")
            weld.Part0 = core
            weld.Part1 = part
            weld.Parent = part
        end
    end

    return true
end

local function clear_existing_visual(core)
    local existing = core:FindFirstChild("Visual")
    if existing then
        existing:Destroy()
    end
end

function UnitFactoryService.ApplyVisual(core, model_key)
    if not core or not core:IsA("BasePart") then
        return
    end

    clear_existing_visual(core)

    local template = ModelLibraryService.GetTemplate(model_key)
    if not template then
        core.Transparency = 0
        return
    end

    local visual = template:Clone()
    visual.Name = "Visual"
    visual.Parent = core

    local ok = weld_visual_to_core(core, visual)
    if ok then
        core.Transparency = 1
    else
        visual:Destroy()
        core.Transparency = 0
    end
end

function UnitFactoryService.CreateCorePart(size, color, position, parent)
    local p = Instance.new("Part")
    p.Size = size
    p.Color = color
    p.Material = Enum.Material.Plastic
    p.CanCollide = true
    p.Anchored = false
    p.Position = position
    p.Parent = parent
    return p
end

function UnitFactoryService.AttachMover(part, max_force, responsiveness, max_velocity)
    local att = Instance.new("Attachment")
    att.Parent = part

    local ap = Instance.new("AlignPosition")
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = att
    ap.MaxForce = max_force
    ap.Responsiveness = responsiveness
    ap.MaxVelocity = max_velocity
    ap.Parent = part

    local ao = Instance.new("AlignOrientation")
    ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
    ao.Attachment0 = att
    ao.MaxTorque = max_force
    ao.Responsiveness = responsiveness
    ao.Parent = part

    return ap
end

return UnitFactoryService