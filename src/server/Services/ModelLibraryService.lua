local ModelLibraryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LIB_FOLDER_NAME = "ModelLibrary"

local function get_library()
    local lib = ReplicatedStorage:FindFirstChild(LIB_FOLDER_NAME)
    if lib and lib:IsA("Folder") then
        return lib
    end
    lib = Instance.new("Folder")
    lib.Name = LIB_FOLDER_NAME
    lib.Parent = ReplicatedStorage
    return lib
end

local function ensure_primary_part(model)
    if model.PrimaryPart then
        return
    end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then
        model.PrimaryPart = part
    end
end

local function sanitize_model(model)
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.CanCollide = false
            inst.CanTouch = false
            inst.CanQuery = false
            inst.Massless = true
        end
    end
    ensure_primary_part(model)
end

function ModelLibraryService.Sanitize()
    local lib = get_library()
    local count = 0
    for _, child in ipairs(lib:GetChildren()) do
        if child:IsA("Model") then
            sanitize_model(child)
            count += 1
        end
    end
    print(string.format(
        "[ModelLibraryService] Ready. Models=%d. (Drop models into ReplicatedStorage/ModelLibrary named by unit type.)",
        count
    ))
end

function ModelLibraryService.GetTemplate(model_key)
    if typeof(model_key) ~= "string" or model_key == "" then
        return nil
    end
    local lib = get_library()
    local m = lib:FindFirstChild(model_key)
    if m and m:IsA("Model") then
        return m
    end
    return nil
end

return ModelLibraryService