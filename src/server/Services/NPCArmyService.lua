local ServerScriptService = game:GetService("ServerScriptService")

local WorldService = require(ServerScriptService.Server.Services.WorldService)
local UnitFactory = require(ServerScriptService.Server.Services.UnitFactory)

local NPCArmyService = {}

local next_npc_owner_id = -1000

local NPC_ARMIES = {
    {
        army_name = "Grave Baron",
        unit_count = 6,
        spawn = Vector3.new(40, 5, 0),
        color = Color3.fromRGB(160, 80, 200),
    },
    {
        army_name = "Bone Patrol",
        unit_count = 4,
        spawn = Vector3.new(-40, 5, 10),
        color = Color3.fromRGB(200, 200, 200),
    },
    {
        army_name = "Rot Walkers",
        unit_count = 5,
        spawn = Vector3.new(0, 5, 40),
        color = Color3.fromRGB(200, 140, 80),
    },
}

local function allocate_npc_owner_id()
    next_npc_owner_id -= 1
    return next_npc_owner_id
end

local function spawn_named_army(def)
    local units_folder = WorldService.get_units_folder()
    local leaders_folder = WorldService.get_leaders_folder()

    if not units_folder or not leaders_folder then
        return
    end

    local owner_id = allocate_npc_owner_id()

    local leader = UnitFactory.create_leader_part(
        owner_id,
        ("Leader_%s"):format(def.army_name),
        def.spawn,
        def.color
    )
    leader.Parent = leaders_folder

    for i = 1, def.unit_count do
        local unit = UnitFactory.create_unit(
            owner_id,
            ("%s_Unit_%d"):format(def.army_name, i),
            def.spawn + Vector3.new(i * 3, 2, 0),
            def.color
        )
        unit:SetAttribute("Faction", "NPC")
        unit:SetAttribute("ArmyName", def.army_name)
        unit.Parent = units_folder
    end

    print(("[NPCArmyService] Spawned named NPC army '%s' (owner_id=%d).")
        :format(def.army_name, owner_id))
end

function NPCArmyService.start()
    for _, def in ipairs(NPC_ARMIES) do
        spawn_named_army(def)
    end

    print("[NPCArmyService] Ready.")
end

return NPCArmyService