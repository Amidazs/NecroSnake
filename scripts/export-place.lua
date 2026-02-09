local args = {...}

local function get_arg(flag)
    for i = 1, #args do
        if args[i] == flag then
            return args[i + 1]
        end
    end
    return nil
end

local place_path = get_arg("--place")
assert(place_path, "Missing --place <path to .rbxl>")

local game = remodel.readPlaceFile(place_path)

local function export_service(service_name, out_path)
    local service = game:GetService(service_name)
    if service == nil then
        print(("Skipping %s (not found)"):format(service_name))
        return
    end

    remodel.writeModelFile(out_path, service)
    print(("Exported %s -> %s"):format(service_name, out_path))
end

export_service("ReplicatedStorage", "src/ReplicatedStorage.rbxmx")
export_service("ServerScriptService", "src/ServerScriptService.rbxmx")
export_service("StarterPlayer", "src/StarterPlayer.rbxmx")