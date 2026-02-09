local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local FOLDER_NAME = "Remotes"

local function get_or_create_folder()
    local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
    if folder and folder:IsA("Folder") then
        return folder
    end

    folder = Instance.new("Folder")
    folder.Name = FOLDER_NAME
    folder.Parent = ReplicatedStorage
    return folder
end

function Remotes.get_remote_event(name)
    local folder = get_or_create_folder()
    local existing = folder:FindFirstChild(name)

    if existing and existing:IsA("RemoteEvent") then
        return existing
    end

    if existing then
        existing:Destroy()
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = folder
    return remote
end

return Remotes