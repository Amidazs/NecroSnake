local GameConfig = {}

GameConfig.Debug = {
    Enabled = true,
    AiEverySeconds = 1.25,
    CombatEverySeconds = 0.35,
    SpawnEverySeconds = 2.0,
}

GameConfig.World = {
    WorldName = "NecromancerMVP_World",
    ArenaName = "Arena",
    UnitsName = "Units",
    LeadersName = "Leaders",
}

GameConfig.Arena = {
    Center = Vector3.new(0, 0, 0),
    HalfSize = Vector3.new(140, 0, 140),
    GroundY = 1,
}

GameConfig.Visibility = {
    BillboardMaxDistance = 90,
}

GameConfig.Formation = {
    GoldenAngle = 137.5 * (math.pi / 180),
    InnerCapacity = 10,
    InnerSpacing = 3.2,
    OuterSpacing = 5.0,
    OuterRadiusBoost = 16,
}

GameConfig.Units = {
    WeakSkeleton = { Health = 20, Damage = 3, Size = 2.0, Mass = 0.8 },
    Skeleton = { Health = 35, Damage = 5, Size = 2.2, Mass = 1.0 },
    ZombieBrute = { Health = 150, Damage = 15, Size = 3.4, Mass = 5.0 },
    DarkKnight = { Health = 500, Damage = 40, Size = 4.6, Mass = 15.0 },
}

GameConfig.Colors = {
    PlayerUnit = Color3.fromRGB(80, 170, 255),
    WanderUnit = Color3.fromRGB(120, 220, 120),
    NamedUnit = Color3.fromRGB(210, 80, 255),
    NamedLeader = Color3.fromRGB(230, 60, 60),
    PlayerLeader = Color3.fromRGB(245, 245, 245),
}

GameConfig.Player = {
    BaseHealth = 120,
    BaseDamage = 12,
    StartCount = 8,
    StartType = "ZombieBrute",
}

GameConfig.Movement = {
    UnitMaxVelocity = 28,
    UnitResponsiveness = 10,
    UnitMaxForce = 35000,
    LeaderMaxVelocity = 13,
    LeaderResponsiveness = 4.2,
    LeaderMaxForce = 30000,
    TargetUpdateMinSeconds = 0.9,
    TargetUpdateMaxSeconds = 2.0,
}

GameConfig.AI = {
    SenseRange = 120,
    ChaseStopRange = 14,
    FleeDistance = 80,
    Hysteresis = 1.10,
    WanderJitterStuds = 22,
}

GameConfig.Combat = {
    AttackRange = 12,
    AttackCooldownSeconds = 0.5,
}

GameConfig.Raising = {
    BaseChance = 0.35,
    NamedLeaderKillGuaranteedBossRaise = true,
    BossRaiseType = "DarkKnight",
}

GameConfig.Spawn = {
    MaxWanderingGroups = 6,
    MaxNamedArmies = 3,
    WanderingGroupMaxSize = 10,
    NamedSpawnChance = 0.18,
    WanderingSpawnChance = 0.60,
    GroupExpirySeconds = 120,
    NamedExpirySeconds = 180,
}

GameConfig.WanderingCompositions = {
    { "WeakSkeleton", "WeakSkeleton" },
    { "Skeleton" },
    { "Skeleton", "WeakSkeleton", "WeakSkeleton" },
    { "Skeleton", "Skeleton" },
    { "ZombieBrute" },
    { "ZombieBrute", "WeakSkeleton", "WeakSkeleton" },
    { "ZombieBrute", "Skeleton", "WeakSkeleton" },
    { "ZombieBrute", "Skeleton", "Skeleton" },
    { "Skeleton", "Skeleton", "Skeleton" },
}

GameConfig.NamedNPCs = {
    { Name = "Grave Baron", Army = { { Type = "ZombieBrute", Count = 3 }, { Type = "Skeleton", Count = 6 } } },
    { Name = "Bone Patrol", Army = { { Type = "Skeleton", Count = 8 } } },
    { Name = "Rot Walkers", Army = { { Type = "ZombieBrute", Count = 2 }, { Type = "WeakSkeleton", Count = 8 } } },
}

return GameConfig