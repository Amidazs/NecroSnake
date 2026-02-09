-- ModelReplacementService.lua
--
-- This service automatically replaces placeholder cube NPC parts with
-- fully featured models from ReplicatedStorage.ModelLibrary.
-- It clones a random model, positions it at the part's location, hides
-- the original part, and plays any animations found in an "Animations" folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Wait for ModelLibrary folder to exist in ReplicatedStorage
local ModelLibrary = ReplicatedStorage:WaitForChild("ModelLibrary", 10)
if not ModelLibrary then
    warn("ModelReplacementService: ModelLibrary folder not found in ReplicatedStorage")
    return
end

math.randomseed(tick())

local ModelReplacementService = {}

-- Configurable placeholder name
local PLACEHOLDER_NAME = "Cube"

local function getRandomModel()
    local models = ModelLibrary:GetChildren()
    if #models == 0 then
        warn("ModelReplacementService: No models found in ModelLibrary")
        return nil
    end
    return models[math.random(1, #models)]
end

function ModelReplacementService.replacePart(part)
    if not part or not part:IsA("BasePart") then
        return
    end
    -- Make sure we only replace placeholder cubes
    if part.Name ~= PLACEHOLDER_NAME then
        return
    end
    local template = getRandomModel()
    if not template then
        return
    end
    local model = template:Clone()
    -- Parent first to avoid physics issues
    model.Parent = part.Parent
    -- Align model at the same position/orientation
    if model.PrimaryPart then
        model:SetPrimaryPartCFrame(part.CFrame)
    else
        model:MoveTo(part.Position)
    end
    -- Hide placeholder part
    part.Transparency = 1
    part.CanCollide = false
    part.CastShadow = false
    -- Play all animations in "Animations" folder, if present
    local animationsFolder = model:FindFirstChild("Animations")
    if animationsFolder then
        -- Find an AnimationController or Humanoid in the model
        local controller = model:FindFirstChildWhichIsA("AnimationController", true)
                        or model:FindFirstChildWhichIsA("Humanoid", true)
        if controller then
            for _, anim in ipairs(animationsFolder:GetChildren()) do
                if anim:IsA("Animation") then
                    local track = controller:LoadAnimation(anim)
                    track.Looped = true
                    track:Play()
                end
            end
        end
    end
end

function ModelReplacementService.replaceAll()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name == PLACEHOLDER_NAME then
            ModelReplacementService.replacePart(obj)
        end
    end
end

-- Replace existing placeholders
ModelReplacementService.replaceAll()

-- Listen for new parts added to the workspace
Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("BasePart") and desc.Name == PLACEHOLDER_NAME then
        ModelReplacementService.replacePart(desc)
    end
end)

return ModelReplacementService
