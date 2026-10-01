--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")


local NPCService = {}

local model_library_service = nil :: any
local army_service = nil :: any
local running = false
local spawn_task: thread? = nil
local ai_task: thread? = nil
local cleanup_task: thread? = nil

local GROUP_FOLDER_NAME = "NPCGroups"
local NPC_FOLDER_NAME = "NPCs"

local UNIT_TTL_SECONDS = 360
-- Density / cap (scales with map size)
local MIN_UNIT_CAP = 140
local MAX_UNIT_CAP = 260

-- Rough density target: 1 NPC per X studs^2 (lower = denser)
local AREA_PER_NPC = 12000

local GROUP_SIZE_MIN = 2
local GROUP_SIZE_MAX = 6

-- Spawning cadence:
local SPAWN_INTERVAL_ACTIVE_SECONDS = 1.0
local SPAWN_INTERVAL_IDLE_SECONDS = 3.0

-- When under cap, spawn multiple groups per tick (up to this many).
local SPAWN_BURST_MAX_GROUPS = 3


local CLEANUP_INTERVAL_SECONDS = 2.0
local AI_TICK_SECONDS = 0.5

-- Biomes
local BIOMES_FOLDER_NAME = "Biomes"

-- Collision groups
local NPC_COLLISION_GROUP = "NPC"
local NPC_BOSS_COLLISION_GROUP = "NPCBoss"

-- Movement / awareness
local GROUP_SCAN_RANGE = 55
local FEAR_RANGE = 35
local WANDER_RADIUS = 28

-- Combat fallback (only used if a unit has no attributes)
local ATTACK_RANGE = 6
local DEFAULT_ATTACK_DAMAGE = 10
local DEFAULT_ATTACK_COOLDOWN = 0.9
local FLEE_COUNTERATTACK_RANGE = 10


-- Targeting
local TARGET_ACQUIRE_RANGE = 60
local TARGET_REEVAL_COOLDOWN = 2.0
local ARMY_TARGET_SEARCH_RADIUS = 60
local MELEE_STICK_RADIUS = 2.25


-- Option C: leash (group stays within this of its spawn anchor)
local GROUP_LEASH_RADIUS = 75

-- Flee logic (other groups + player army)
local THREAT_SCAN_RANGE = 45
local PLAYER_ARMY_THREAT_SCAN_RANGE = 55

-- Army only counts as a 'threat aura' when it is close enough to protect its owner.
-- This creates windows where NPCs will chase the player if the army drifts away.
local PLAYER_ARMY_PROTECT_RADIUS = 35

-- If a player is unguarded, groups may choose to hunt them even if no other NPC
-- prey exists.
local PLAYER_HUNT_RANGE = 120
local HUNT_UNGUARDED_CHANCE = 0.75
local HUNT_GUARDED_CHANCE = 0.10

local FLEE_START_RATIO = 1.25
local FLEE_STOP_RATIO = 1.10
local FLEE_MIN_DURATION = 4.0
local SAFE_DISTANCE_TO_STOP_FLEE = 60

-- Spawn spread (Terrain-wide)
local SPAWN_MIN_DISTANCE_FROM_PLAYERS = 90
local SPAWN_MIN_DISTANCE_BETWEEN_GROUPS = 80
local SPAWN_MAX_ATTEMPTS = 18

local SPAWN_BOUNDS_MARGIN = 12
local SPAWN_RAYCAST_START_HEIGHT = 600
local SPAWN_RAYCAST_DISTANCE = 2000
local SPAWN_SURFACE_OFFSET = 6

local FALLBACK_MIN_X = -512
local FALLBACK_MAX_X = 512
local FALLBACK_MIN_Z = -512
local FALLBACK_MAX_Z = 512


-- Spacing to prevent unit stacking (scaled by SizeScale)
local BASE_FORMATION_SPACING = 6
local BASE_ATTACK_RING_RADIUS = 5


-- Boss charge tuning
local BOSS_CHARGE_END_DISTANCE = 9
local BOSS_CHARGE_SHOVE_RADIUS = 7
local BOSS_CHARGE_SHOVE_IMPULSE = 220

local boss_phase_by_model: { [Model]: string } = {}

type NpcUnit = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	power: number,
	last_attack: number,
}

type GroupState = {
	id: string,
	folder: Folder,
	units: { NpcUnit },
	leader: NpcUnit,

	anchor_pos: Vector3,

	wander_goal: Vector3?,
	last_wander_pick: number,

	is_fleeing: boolean,
	flee_until_time: number,
	flee_from_pos: Vector3?,
}

type TargetState = {
	target_model: Model?,
	target_root: BasePart?,
	target_humanoid: Humanoid?,
	next_retarget_time: number,
}

local npc_folder: Folder? = nil
local group_folder: Folder? = nil

local groups: { [string]: GroupState } = {}
local target_state_by_unit: { [Model]: TargetState } = {}

local function now(): number
	return os.clock()
end

local function clamp(num: number, min_v: number, max_v: number): number
	if num < min_v then
		return min_v
	end
	if num > max_v then
		return max_v
	end
	return num
end

local function is_near_foliage(pos: Vector3, radius: number): boolean
	local biomes = Workspace:FindFirstChild("Biomes")
	if not biomes then
		return false
	end

	local foliage = biomes:FindFirstChild("Foliage")
	if not foliage then
		return false
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.FilterDescendantsInstances = {foliage}

	local parts = Workspace:GetPartBoundsInRadius(pos, radius, params)
	return #parts > 0
end


local function is_debug_enabled(): boolean
	local flag = ReplicatedStorage:FindFirstChild("DebugNPC")
	return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function debug_print(message: string)
	if is_debug_enabled() then
		print("[NPC DEBUG] " .. message)
	end
end

local function ensure_folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function ensure_group_folder(): Folder
	return ensure_folder(Workspace, GROUP_FOLDER_NAME)
end

local function ensure_npc_folder(): Folder
	return ensure_folder(Workspace, NPC_FOLDER_NAME)
end

local function get_humanoid(model: Model): Humanoid?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		return hum
	end
	return nil
end

local function register_collision_group(name: string)
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
	if not ok then
		-- Group may already exist; that's fine.
	end
end

local function setup_collision_groups()
	register_collision_group(NPC_COLLISION_GROUP)
	register_collision_group(NPC_BOSS_COLLISION_GROUP)

	-- Ensure player army groups exist so boss charge can ignore them.
	register_collision_group("Units")
	register_collision_group("Leaders")

	-- NPCs don't collide with each other (prevents climbing / pileups)
	PhysicsService:CollisionGroupSetCollidable(NPC_COLLISION_GROUP, NPC_COLLISION_GROUP, false)

	-- Bosses also don't collide with normal NPCs (keeps swarms stable)
	PhysicsService:CollisionGroupSetCollidable(NPC_BOSS_COLLISION_GROUP, NPC_COLLISION_GROUP, false)

	-- Bosses ignore player army during the initial charge.
	PhysicsService:CollisionGroupSetCollidable(NPC_BOSS_COLLISION_GROUP, "Units", false)
	PhysicsService:CollisionGroupSetCollidable(NPC_BOSS_COLLISION_GROUP, "Leaders", false)

	-- Optional: bosses collide with bosses? usually also false to avoid stacking
	PhysicsService:CollisionGroupSetCollidable(NPC_BOSS_COLLISION_GROUP, NPC_BOSS_COLLISION_GROUP, false)
end

local function set_model_collision_group(model: Model, group_name: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = group_name
		end
	end
end


local function get_root(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function is_alive_model(model: Model?): boolean
	if not model or model.Parent == nil then
		return false
	end
	return get_humanoid(model) ~= nil
end

local function get_number_attr(model: Model, key: string): number?
	local v = model:GetAttribute(key)
	if typeof(v) == "number" then
		return v
	end
	return nil
end

local function get_size_scale(model: Model): number
	local s = model:GetAttribute("SizeScale")
	if typeof(s) == "number" and s > 0 then
		return s
	end
	return 1
end

local function is_boss_model(model: Model): boolean
	local v = model:GetAttribute("IsBoss")
	return v == true
end


local function is_boss_group(g: GroupState): boolean
	for _, u in ipairs(g.units) do
		if u.model:GetAttribute("IsBoss") == true then
			return true
		end
	end
	return false
end

local function get_boss_phase(model: Model): string
	local phase = boss_phase_by_model[model]
	if phase then
		return phase
	end
	return "Combat"
end

local function set_boss_phase(model: Model, phase: string)
	boss_phase_by_model[model] = phase
	model:SetAttribute("BossPhase", phase)
end

local function set_boss_charge_enabled(model: Model, enabled: boolean)
	if enabled then
		set_model_collision_group(model, NPC_BOSS_COLLISION_GROUP)
		set_boss_phase(model, "Charge")
	else
		set_model_collision_group(model, NPC_COLLISION_GROUP)
		set_boss_phase(model, "Combat")
	end
end

local function apply_boss_shove(boss_root: BasePart)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Blacklist
	overlap.FilterDescendantsInstances = { boss_root.Parent }

	local parts = Workspace:GetPartBoundsInRadius(
		boss_root.Position,
		BOSS_CHARGE_SHOVE_RADIUS,
		overlap
	)

	for _, part in ipairs(parts) do
		local other_model = part:FindFirstAncestorOfClass("Model")
		if other_model and other_model ~= boss_root.Parent then
			if other_model:GetAttribute("IsPlayerArmy") == true then
				local other_root = other_model:FindFirstChild("HumanoidRootPart")
				if other_root and other_root:IsA("BasePart") then
					local dir = other_root.Position - boss_root.Position
					local flat = Vector3.new(dir.X, 0, dir.Z)
					if flat.Magnitude > 0.01 then
						local impulse = flat.Unit * BOSS_CHARGE_SHOVE_IMPULSE
						other_root:ApplyImpulse(impulse)
					end
				end
			end
		end
	end
end

local function get_attack_stats(attacker_model: Model): (number, number)
	-- Supports both naming schemes:
	-- New: Damage / AttackCooldown
	-- Old: AttackDamage / AttackCooldown
	local damage = get_number_attr(attacker_model, "Damage")
	if not damage then
		damage = get_number_attr(attacker_model, "AttackDamage")
	end
	if not damage or damage <= 0 then
		damage = DEFAULT_ATTACK_DAMAGE
	end

	local cooldown = get_number_attr(attacker_model, "AttackCooldown")
	if not cooldown or cooldown <= 0 then
		cooldown = DEFAULT_ATTACK_COOLDOWN
	end

	cooldown = clamp(cooldown, 0.2, 6.0)
	damage = math.max(1, math.floor(damage + 0.5))

	return damage, cooldown
end

local function compute_damage_after_defense(target_model: Model, raw_damage: number): number
	-- Defense is a fraction [0..0.9] meaning damage reduction.
	local defense = get_number_attr(target_model, "Defense")
	if not defense then
		defense = 0
	end
	defense = clamp(defense, 0, 0.9)

	local final = raw_damage * (1 - defense)
	return math.max(1, math.floor(final + 0.5))
end

local function set_unit_attributes(unit: NpcUnit, group_id: string, is_leader: boolean)
	unit.model:SetAttribute("NPCGroupId", group_id)
	unit.model:SetAttribute("IsNPCLeader", is_leader)

	-- Prevent player systems from treating this as an owned army unit.
	unit.model:SetAttribute("IsPlayerArmy", false)
end

local function get_model_dps_estimate(model: Model): number
	local hum = get_humanoid(model)
	if not hum then
		return 0
	end

	local hp = hum.MaxHealth
	local damage, cooldown = get_attack_stats(model)
	local dps = damage / math.max(0.2, cooldown)

	return (hp * 0.55) + (dps * 18)
end

local function compute_group_strength(g: GroupState): number
	local sum = 0
	for _, u in ipairs(g.units) do
		if u.humanoid.Health > 0 and u.model.Parent ~= nil then
			sum += u.power
		end
	end
	return sum
end

local function get_group_center(g: GroupState): Vector3
	local sum = Vector3.new(0, 0, 0)
	local count = 0

	for _, u in ipairs(g.units) do
		if u.humanoid.Health > 0 and u.model.Parent ~= nil then
			sum += u.root.Position
			count += 1
		end
	end

	if count == 0 then
		return g.leader.root.Position
	end

	return sum / count
end

local function move_unit_to(unit: NpcUnit, goal: Vector3)
	if unit.humanoid.Health <= 0 then
		return
	end
	unit.humanoid:MoveTo(goal)
end

local function clamp_goal_to_leash(anchor_pos: Vector3, goal: Vector3, leash_radius: number): Vector3
	local offset = goal - anchor_pos
	local flat = Vector3.new(offset.X, 0, offset.Z)

	if flat.Magnitude <= leash_radius then
		return goal
	end

	local dir = flat.Unit
	local clamped = anchor_pos + (dir * leash_radius)
	return Vector3.new(clamped.X, goal.Y, clamped.Z)
end

local function pick_wander_goal(g: GroupState): Vector3
	local center = get_group_center(g)
	local angle = math.random() * math.pi * 2
	local radius = math.random(10, WANDER_RADIUS)
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return Vector3.new(center.X, 6, center.Z) + offset
end

local function get_spawn_time_seed(model: Model): number
	local spawn_time = model:GetAttribute("SpawnTime")
	if typeof(spawn_time) == "number" then
		return spawn_time
	end
	return 0
end

local function compute_formation_spacing(leader_model: Model, follower_model: Model): number
	local leader_scale = get_size_scale(leader_model)
	local follower_scale = get_size_scale(follower_model)

	local scale = math.max(leader_scale, follower_scale)
	return BASE_FORMATION_SPACING * scale
end

local function apply_formation(g: GroupState, goal: Vector3)
	local leader_pos = g.leader.root.Position

	local forward = (goal - leader_pos)
	local flat = Vector3.new(forward.X, 0, forward.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	forward = flat.Unit

	local right = Vector3.new(-forward.Z, 0, forward.X)

	local followers: { NpcUnit } = {}
	for _, u in ipairs(g.units) do
		if u ~= g.leader then
			table.insert(followers, u)
		end
	end

	move_unit_to(g.leader, goal)

	for i, u in ipairs(followers) do
		local row = math.floor((i - 1) / 2) + 1
		local side = ((i - 1) % 2 == 0) and -1 or 1

		local spacing = compute_formation_spacing(g.leader.model, u.model)

		local seed = get_spawn_time_seed(u.model)
		local jitter = ((seed % 13) * 0.15)

		local offset = (forward * (-row * (spacing + jitter)))
			+ (right * (side * (spacing + jitter)))

		local follower_goal = leader_pos + offset
		move_unit_to(u, follower_goal)
	end
end

local function compute_attack_approach_goal(
	unit: NpcUnit,
	unit_index: number,
	unit_count: number,
	target_pos: Vector3
): Vector3
	-- Spread attackers around the target, but keep the approach point INSIDE
	-- ATTACK_RANGE so units actually hit instead of orbiting nearby.
	local count = math.max(1, unit_count)
	local scale = get_size_scale(unit.model)

	local seed = get_spawn_time_seed(unit.model)
	local extra = ((seed % 17) * 0.08)

	local angle = ((unit_index - 1) / count) * (math.pi * 2)
	-- Keep attackers close so they don't "orbit" just outside melee.
	-- Smaller base + smaller scale influence = more pressure.
	local raw_radius = (BASE_ATTACK_RING_RADIUS * 0.55 + extra) + (scale * 0.85)

	-- Always stay well inside attack range, and clamp to a tight melee stick radius.
	local max_radius = math.max(MELEE_STICK_RADIUS, ATTACK_RANGE - 2.0)
	local radius = math.min(raw_radius, max_radius)


	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return Vector3.new(target_pos.X, 6, target_pos.Z) + offset
end

local function get_or_create_target_state(npc_model: Model): TargetState
	local state = target_state_by_unit[npc_model]
	if state then
		return state
	end

	local created: TargetState = {
		target_model = nil,
		target_root = nil,
		target_humanoid = nil,
		next_retarget_time = 0,
	}

	target_state_by_unit[npc_model] = created
	return created
end

local function clear_target_state_for_group(g: GroupState)
	for _, u in ipairs(g.units) do
		target_state_by_unit[u.model] = nil
		boss_phase_by_model[u.model] = nil
	end
end

local function get_nearby_groups(g: GroupState, range: number): { GroupState }
	local nearby: { GroupState } = {}
	local center = get_group_center(g)

	for id, other in pairs(groups) do
		if id ~= g.id then
			local dist = (get_group_center(other) - center).Magnitude
			if dist <= range then
				table.insert(nearby, other)
			end
		end
	end

	return nearby
end

-- ===== Player army threat =====

local function compute_player_army_threat_near_pos(
	pos: Vector3,
	range: number
): (number, Vector3?)
	if not army_service or not army_service.get_army_units then
		return 0, nil
	end

	local total_strength = 0
	local sum_pos = Vector3.new(0, 0, 0)
	local count = 0

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local char_root = char and get_root(char) or nil

		local units: { Model } = army_service.get_army_units(plr)
		for _, unit_model in ipairs(units) do
			if unit_model and unit_model.Parent ~= nil then
				local root = get_root(unit_model)
				local hum = get_humanoid(unit_model)
				if root and hum then
					local dist_to_group = (root.Position - pos).Magnitude
					if dist_to_group <= range then
						-- Only treat this army as a "threat" if it is currently guarding
						-- its owner player (close enough to realistically intervene).
						local is_guarding_owner = true
						if char_root then
							local dist_to_owner = (root.Position - char_root.Position).Magnitude
							is_guarding_owner = dist_to_owner <= PLAYER_ARMY_PROTECT_RADIUS
						end

						if is_guarding_owner then
							total_strength += get_model_dps_estimate(unit_model)
							sum_pos += root.Position
							count += 1
						end
					end
				end
			end
		end
	end

	if count <= 0 then
		return 0, nil
	end

	return total_strength, (sum_pos / count)
end

-- ===== Flee logic =====

local function should_flee_ratio(self_strength: number, threat_strength: number): (boolean, number)
	if self_strength <= 0 then
		return true, math.huge
	end
	local ratio = threat_strength / self_strength
	return ratio >= FLEE_START_RATIO, ratio
end

local function find_most_threatening_source(g: GroupState): (Vector3?, number, number)
	local self_center = get_group_center(g)
	local self_strength = compute_group_strength(g)

	local best_pos: Vector3? = nil
	local best_ratio = 0
	local best_dist = math.huge

	-- Other NPC groups
	for _, other in ipairs(get_nearby_groups(g, THREAT_SCAN_RANGE)) do
		local threat_strength = compute_group_strength(other)
		local ok, ratio = should_flee_ratio(self_strength, threat_strength)
		local dist = (get_group_center(other) - self_center).Magnitude

		if ok then
			if ratio > best_ratio or (ratio == best_ratio and dist < best_dist) then
				best_ratio = ratio
				best_dist = dist
				best_pos = get_group_center(other)
			end
		end
	end

	-- Player army near this group (only counts if guarding its player)
	local army_strength, army_center = compute_player_army_threat_near_pos(
		self_center,
		PLAYER_ARMY_THREAT_SCAN_RANGE
	)
	if army_center and army_strength > 0 then
		local ok, ratio = should_flee_ratio(self_strength, army_strength)
		local dist = (army_center - self_center).Magnitude

		if ok then
			if ratio > best_ratio or (ratio == best_ratio and dist < best_dist) then
				best_ratio = ratio
				best_dist = dist
				best_pos = army_center
			end
		end
	end

	return best_pos, best_ratio, best_dist
end

local function update_flee_state(g: GroupState)

	-- Boss groups never flee.
	for _, u in ipairs(g.units) do
		if is_boss_model(u.model) then
			g.is_fleeing = false
			return
		end
	end

	local t = now()
	local threat_pos, ratio, dist = find_most_threatening_source(g)

	if g.is_fleeing then
		if t >= g.flee_until_time then
			local should_stop = false

			if not threat_pos then
				should_stop = true
			elseif dist >= SAFE_DISTANCE_TO_STOP_FLEE then
				should_stop = true
			else
				-- Hysteresis: stop fleeing only when worst nearby threat is weaker.
				local self_strength = compute_group_strength(g)

				local max_npc_threat = 0
				for _, other in ipairs(get_nearby_groups(g, THREAT_SCAN_RANGE)) do
					max_npc_threat = math.max(max_npc_threat, compute_group_strength(other))
				end

				local army_threat, _ = compute_player_army_threat_near_pos(
					get_group_center(g),
					PLAYER_ARMY_THREAT_SCAN_RANGE
				)

				local worst = math.max(max_npc_threat, army_threat)
				local current_ratio = math.huge
				if self_strength > 0 then
					current_ratio = worst / self_strength
				end

				if current_ratio <= FLEE_STOP_RATIO then
					should_stop = true
				end
			end

			if should_stop then
				g.is_fleeing = false
				g.flee_from_pos = nil
				debug_print(string.format("Group %s stop fleeing", g.id))
			end
		end

		if threat_pos then
			g.flee_from_pos = threat_pos
		end
		return
	end

	if threat_pos and dist <= THREAT_SCAN_RANGE then
		g.is_fleeing = true
		g.flee_from_pos = threat_pos
		g.flee_until_time = t + FLEE_MIN_DURATION

		-- Important: dump targets on flee so they don't join blobs.
		clear_target_state_for_group(g)

		debug_print(
			string.format(
				"Group %s start fleeing (ratio=%.2f dist=%.1f)",
				g.id,
				ratio,
				dist
			)
		)
	end
end

local function compute_flee_goal(g: GroupState): Vector3
	local center = get_group_center(g)
	local from_pos = g.flee_from_pos or (center + Vector3.new(1, 0, 0))

	local dir = center - from_pos
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(1, 0, 0)
	end

	local raw_goal = center + (flat.Unit * WANDER_RADIUS)
	local goal = Vector3.new(raw_goal.X, 6, raw_goal.Z)
	return clamp_goal_to_leash(g.anchor_pos, goal, GROUP_LEASH_RADIUS)
end

local function is_player_guarded(player: Player): boolean
	-- A player is considered "guarded" if they have at least one army unit
	-- close enough to realistically protect them.
	if not army_service or not army_service.get_army_units then
		return false
	end

	local char = player.Character
	local char_root = char and get_root(char) or nil
	if not char_root then
		return false
	end

	local units: { Model } = army_service.get_army_units(player)
	for _, unit_model in ipairs(units) do
		if unit_model and unit_model.Parent ~= nil then
			local root = get_root(unit_model)
			local hum = get_humanoid(unit_model)
			if root and hum then
				local dist = (root.Position - char_root.Position).Magnitude
				if dist <= PLAYER_ARMY_PROTECT_RADIUS then
					return true
				end
			end
		end
	end

	return false
end

local function find_nearest_player(center: Vector3, range: number): (Player?, BasePart?, Humanoid?, number)
	local best_player: Player? = nil
	local best_root: BasePart? = nil
	local best_hum: Humanoid? = nil
	local best_dist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local hrp = get_root(char)
			local hum = get_humanoid(char)
			if hrp and hum then
				local dist = (hrp.Position - center).Magnitude
				if dist <= range and dist < best_dist then
					best_player = plr
					best_root = hrp
					best_hum = hum
					best_dist = dist
				end
			end
		end
	end

	return best_player, best_root, best_hum, best_dist
end

local function decide_goal_for_group(g: GroupState): Vector3
	if g.is_fleeing then
		return compute_flee_goal(g)
	end

	local center = get_group_center(g)
	local nearby = get_nearby_groups(g, GROUP_SCAN_RANGE)
	local self_strength = compute_group_strength(g)

	local best_threat: GroupState? = nil
	local best_threat_dist = math.huge

	local best_prey: GroupState? = nil
	local best_prey_dist = math.huge

	for _, other in ipairs(nearby) do
		local other_strength = compute_group_strength(other)
		local dist = (get_group_center(other) - center).Magnitude

		if other_strength > self_strength and dist <= FEAR_RANGE then
			if dist < best_threat_dist then
				best_threat_dist = dist
				best_threat = other
			end
		elseif other_strength < self_strength then
			if dist < best_prey_dist then
				best_prey_dist = dist
				best_prey = other
			end
		end
	end

	if best_threat then
		local threat_pos = get_group_center(best_threat)
		local flee_dir = center - threat_pos
		local flat = Vector3.new(flee_dir.X, 0, flee_dir.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(1, 0, 0)
		end

		local raw_goal = center + (flat.Unit * WANDER_RADIUS)
		local goal = Vector3.new(raw_goal.X, 6, raw_goal.Z)
		return clamp_goal_to_leash(g.anchor_pos, goal, GROUP_LEASH_RADIUS)
	end

	if best_prey then
		local prey_center = get_group_center(best_prey)
		local goal = Vector3.new(prey_center.X, 6, prey_center.Z)
		return clamp_goal_to_leash(g.anchor_pos, goal, GROUP_LEASH_RADIUS)
	end

	-- If there is an unguarded player nearby, sometimes hunt them.
	-- This prevents the game from feeling like the player is always the chaser.
	local nearest_player, player_root, _, _ = find_nearest_player(center, PLAYER_HUNT_RANGE)
	if nearest_player and player_root then
		local guarded = is_player_guarded(nearest_player)
		local chance = guarded and HUNT_GUARDED_CHANCE or HUNT_UNGUARDED_CHANCE
		if math.random() < chance then
			local player_pos = player_root.Position
			local goal = Vector3.new(player_pos.X, 6, player_pos.Z)
			return clamp_goal_to_leash(g.anchor_pos, goal, GROUP_LEASH_RADIUS)
		end
	end

	if not g.wander_goal or (now() - g.last_wander_pick) > 3.5 then
		g.wander_goal = pick_wander_goal(g)
		g.last_wander_pick = now()
	end

	local wander_goal = g.wander_goal or Vector3.new(center.X, 6, center.Z)
	return clamp_goal_to_leash(g.anchor_pos, wander_goal, GROUP_LEASH_RADIUS)
end

-- ===== Target acquisition =====

local function choose_closest_player_or_army_target(
	npc_pos: Vector3,
	only_players: boolean
): (Model?, BasePart?, Humanoid?)
	local best_model: Model? = nil
	local best_root: BasePart? = nil
	local best_hum: Humanoid? = nil
	local best_dist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local hrp = get_root(char)
			local hum = get_humanoid(char)
			if hrp and hum then
				local dist = (hrp.Position - npc_pos).Magnitude
				if dist <= TARGET_ACQUIRE_RANGE and dist < best_dist then
					best_dist = dist
					best_model = char
					best_root = hrp
					best_hum = hum
				end
			end
		end

		if (not only_players) and army_service and army_service.get_army_units then
			local army_units: { Model } = army_service.get_army_units(plr)
			for _, unit_model in ipairs(army_units) do
				if unit_model and unit_model.Parent ~= nil then
					local u_root = get_root(unit_model)
					local u_hum = get_humanoid(unit_model)
					if u_root and u_hum then
						local dist = (u_root.Position - npc_pos).Magnitude
						if dist <= ARMY_TARGET_SEARCH_RADIUS and dist < best_dist then
							best_dist = dist
							best_model = unit_model
							best_root = u_root
							best_hum = u_hum
						end
					end
				end
			end
		end
	end

	return best_model, best_root, best_hum
end

local function find_closest_player_army_unit_in_range(
	npc_pos: Vector3,
	range: number
): (Model?, BasePart?, Humanoid?)

	if not army_service or not army_service.get_army_units then
		return nil, nil, nil
	end

	local best_model: Model? = nil
	local best_root: BasePart? = nil
	local best_hum: Humanoid? = nil
	local best_dist = math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		local units: { Model } = army_service.get_army_units(plr)

		for _, unit_model in ipairs(units) do
			if unit_model and unit_model.Parent ~= nil then
				if unit_model:GetAttribute("IsPlayerArmy") == true then
					local root = get_root(unit_model)
					local hum = get_humanoid(unit_model)

					if root and hum then
						local dist = (root.Position - npc_pos).Magnitude
						if dist <= range and dist < best_dist then
							best_dist = dist
							best_model = unit_model
							best_root = root
							best_hum = hum
						end
					end
				end
			end
		end
	end

	return best_model, best_root, best_hum
end


local function choose_closest_npc_target_outside_group(
	own_group_id: string,
	npc_pos: Vector3
): (Model?, BasePart?, Humanoid?)
	local best_model: Model? = nil
	local best_root: BasePart? = nil
	local best_hum: Humanoid? = nil
	local best_dist = math.huge

	for _, other in pairs(groups) do
		if other.id ~= own_group_id then
			for _, u in ipairs(other.units) do
				if u.model.Parent ~= nil and u.humanoid.Health > 0 then
					local dist = (u.root.Position - npc_pos).Magnitude
					if dist <= TARGET_ACQUIRE_RANGE and dist < best_dist then
						best_dist = dist
						best_model = u.model
						best_root = u.root
						best_hum = u.humanoid
					end
				end
			end
		end
	end

	return best_model, best_root, best_hum
end

local function reacquire_target_for_npc(
	own_group_id: string,
	npc_unit: NpcUnit
): (Model?, BasePart?, Humanoid?)
	local npc_pos = npc_unit.root.Position

	local only_players = false
	if is_boss_model(npc_unit.model) and get_boss_phase(npc_unit.model) == "Charge" then
		only_players = true
	end

	local p_model, p_root, p_hum = choose_closest_player_or_army_target(npc_pos, only_players)
	local n_model, n_root, n_hum = choose_closest_npc_target_outside_group(
		own_group_id,
		npc_pos
	)

	local best_model: Model? = nil
	local best_root: BasePart? = nil
	local best_hum: Humanoid? = nil
	local best_dist = math.huge

	if p_root and p_model and p_hum then
		local d = (p_root.Position - npc_pos).Magnitude
		best_model, best_root, best_hum, best_dist = p_model, p_root, p_hum, d
	end

	if n_root and n_model and n_hum then
		local d = (n_root.Position - npc_pos).Magnitude
		if d < best_dist then
			best_model, best_root, best_hum, best_dist = n_model, n_root, n_hum, d
		end
	end

	return best_model, best_root, best_hum
end

local function update_target_state(own_group: GroupState, npc_unit: NpcUnit)
	local state = get_or_create_target_state(npc_unit.model)
	local t = now()

	if own_group.is_fleeing then
		-- While fleeing, do not chase targets.
		-- But counterattack player army units that are very close.

		local npc_pos = npc_unit.root.Position

		local a_model, a_root, a_hum = find_closest_player_army_unit_in_range(
			npc_pos,
			FLEE_COUNTERATTACK_RANGE
		)

		if a_model and a_root and a_hum then
			state.target_model = a_model
			state.target_root = a_root
			state.target_humanoid = a_hum
		else
			state.target_model = nil
			state.target_root = nil
			state.target_humanoid = nil
		end

		state.next_retarget_time = t + TARGET_REEVAL_COOLDOWN
		return
	end

	local must_retarget = false

	if t >= state.next_retarget_time then
		must_retarget = true
	end

	if not is_alive_model(state.target_model) then
		must_retarget = true
	end

	if state.target_root then
		local d = (state.target_root.Position - npc_unit.root.Position).Magnitude
		if d > TARGET_ACQUIRE_RANGE then
			must_retarget = true
		end
	end

	if must_retarget then
		local new_model, new_root, new_hum = reacquire_target_for_npc(
			own_group.id,
			npc_unit
		)

		state.target_model = new_model
		state.target_root = new_root
		state.target_humanoid = new_hum
		state.next_retarget_time = t + TARGET_REEVAL_COOLDOWN
	end
end

-- ===== Spawn helpers =====

local function get_player_positions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local hrp = get_root(char)
			if hrp then
				table.insert(positions, hrp.Position)
			end
		end
	end
	return positions
end

local function get_group_anchor_positions(): { Vector3 }
	local positions: { Vector3 } = {}
	for _, g in pairs(groups) do
		table.insert(positions, g.anchor_pos)
	end
	return positions
end

local function is_spawn_pos_valid(pos: Vector3): boolean
	if is_near_foliage(pos, 10) then
	return false
end

	for _, p in ipairs(get_player_positions()) do
		if (p - pos).Magnitude < SPAWN_MIN_DISTANCE_FROM_PLAYERS then
			return false
		end
	end

	for _, a in ipairs(get_group_anchor_positions()) do
		if (a - pos).Magnitude < SPAWN_MIN_DISTANCE_BETWEEN_GROUPS then
			return false
		end
	end

	return true
end


local function get_terrain_bounds_xz(): (number, number, number, number)
	local bounds_part = Workspace:FindFirstChild("SpawnBounds", true)
	if bounds_part and bounds_part:IsA("BasePart") then
		local size = bounds_part.Size
		local pos = bounds_part.Position
		local half_x = size.X * 0.5
		local half_z = size.Z * 0.5

		return pos.X - half_x, pos.X + half_x, pos.Z - half_z, pos.Z + half_z
	end

	return FALLBACK_MIN_X, FALLBACK_MAX_X, FALLBACK_MIN_Z, FALLBACK_MAX_Z
end

local function compute_desired_unit_cap(): number
	local min_x, max_x, min_z, max_z = get_terrain_bounds_xz()
	local size_x = math.max(1, (max_x - min_x))
	local size_z = math.max(1, (max_z - min_z))
	local area = size_x * size_z

	local desired = math.floor(area / AREA_PER_NPC)
	desired = math.clamp(desired, MIN_UNIT_CAP, MAX_UNIT_CAP)

	return desired
end


local function snap_to_ground(pos: Vector3): Vector3
	local origin = Vector3.new(pos.X, pos.Y + SPAWN_RAYCAST_START_HEIGHT, pos.Z)
	local direction = Vector3.new(0, -SPAWN_RAYCAST_DISTANCE, 0)

	local biomes = Workspace:FindFirstChild("Biomes")

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = {
		ensure_npc_folder(),
		ensure_group_folder(),
		biomes,
	}
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, params)
	if result then
		if result.Instance:IsA("Terrain") then
			-- Optional: also reject water material if needed (extra safe)
			if result.Material == Enum.Material.Water then
				return pos
			end
		elseif result.Instance:IsA("BasePart") then
			-- The recovered build has a simple collidable ArenaFloor until the
			-- authored Terrain is restored.
			if not result.Instance.CanCollide then
				return pos
			end
		else
			return pos
		end

		return Vector3.new(pos.X, result.Position.Y + SPAWN_SURFACE_OFFSET, pos.Z)
	end

	return pos
end


local function sample_spawn_position(): Vector3
	local min_x, max_x, min_z, max_z = get_terrain_bounds_xz()

	min_x += SPAWN_BOUNDS_MARGIN
	max_x -= SPAWN_BOUNDS_MARGIN
	min_z += SPAWN_BOUNDS_MARGIN
	max_z -= SPAWN_BOUNDS_MARGIN

	local x = min_x + (math.random() * (max_x - min_x))
	local z = min_z + (math.random() * (max_z - min_z))

	local raw = Vector3.new(x, 0, z)
	return snap_to_ground(raw)
end


local function find_spawn_position(): Vector3
	for _ = 1, SPAWN_MAX_ATTEMPTS do
		local pos = sample_spawn_position()
		if is_spawn_pos_valid(pos) then
			return pos
		end
	end

	return sample_spawn_position()
end


-- ===== Lifecycle =====

local function prune_dead_and_expired()
	local t = now()
	for id, g in pairs(groups) do
		local alive_units: { NpcUnit } = {}

		for _, u in ipairs(g.units) do
			local spawn_time = u.model:GetAttribute("SpawnTime")
			local expired = (typeof(spawn_time) == "number")
				and (t - (spawn_time :: number) > UNIT_TTL_SECONDS)

			if u.humanoid.Health > 0 and not expired and u.model.Parent ~= nil then
				table.insert(alive_units, u)
			else
				local is_necro_corpse = u.model:GetAttribute("IsNecroCorpse") == true
				if u.model.Parent ~= nil and not is_necro_corpse then
					u.model:Destroy()
				end
				target_state_by_unit[u.model] = nil
				boss_phase_by_model[u.model] = nil
			end
		end

		g.units = alive_units
		if #g.units == 0 then
			if g.folder.Parent ~= nil then
				g.folder:Destroy()
			end
			groups[id] = nil
		else
			if g.leader.humanoid.Health <= 0 or g.leader.model.Parent == nil then
				g.leader = g.units[1]
				for _, u in ipairs(g.units) do
					set_unit_attributes(u, g.id, u == g.leader)
				end
			end
		end
	end
end

local function count_total_units(): number
	local total = 0
	for _, g in pairs(groups) do
		total += #g.units
	end
	return total
end

local function pick_spawn_template(templates: { string }): string
	-- use weighted template selection when available.
	if model_library_service and model_library_service.pick_spawn_template then
		local chosen = model_library_service.pick_spawn_template(templates)
		if chosen then
			return chosen
		end
	end

	return templates[math.random(1, #templates)]
end

local function spawn_group()
	if not model_library_service or not model_library_service.spawn_from_template then
		return
	end

	local unit_cap = compute_desired_unit_cap()
	if count_total_units() >= unit_cap then
		return
	end


	local templates: { string } = {}
	if model_library_service.list_template_names then
		templates = model_library_service.list_template_names()
	end

	if #templates == 0 then
		templates = { "Skeleton" }
	end

	local anchor_pos = find_spawn_position()
	local id = HttpService:GenerateGUID(false)

	local folder = Instance.new("Folder")
	folder.Name = id
	folder.Parent = group_folder

	local group_units: { NpcUnit } = {}

	local count = math.random(GROUP_SIZE_MIN, GROUP_SIZE_MAX)
	for _ = 1, count do
		local template_name = pick_spawn_template(templates)

		local jitter = Vector3.new(
			(math.random() * 2 - 1) * 8,
			0,
			(math.random() * 2 - 1) * 8
		)

		local model = model_library_service.spawn_from_template(
			template_name,
			CFrame.new(anchor_pos + jitter),
			folder
		)

		if model then
			local is_boss = model:GetAttribute("IsBoss") == true

			if is_boss then
				-- Bosses start in Charge phase (ignore player army for the opener).
				set_boss_charge_enabled(model, true)
			else
				set_model_collision_group(model, NPC_COLLISION_GROUP)
			end

			model:SetAttribute("SpawnTime", now())
			model:SetAttribute("NPCGroupId", id)


			local root = get_root(model)
			local hum = get_humanoid(model)
			if root and hum then
				local unit: NpcUnit = {
					model = model,
					root = root,
					humanoid = hum,
					power = get_model_dps_estimate(model),
					last_attack = 0,
				}
				table.insert(group_units, unit)
			else
				model:Destroy()
			end
		end
	end

	if #group_units == 0 then
		folder:Destroy()
		return
	end

	local leader = group_units[1]
	for _, u in ipairs(group_units) do
		set_unit_attributes(u, id, u == leader)
	end

	local g: GroupState = {
		id = id,
		folder = folder,
		units = group_units,
		leader = leader,

		anchor_pos = anchor_pos,

		wander_goal = nil,
		last_wander_pick = 0,

		is_fleeing = false,
		flee_until_time = 0,
		flee_from_pos = nil,
	}

	groups[id] = g
end

function NPCService.init(model_library: any, army: any)
	model_library_service = model_library
	army_service = army

	group_folder = ensure_group_folder()
	npc_folder = ensure_npc_folder()
	setup_collision_groups()

end

function NPCService.start()
	if running then
		return
	end
	running = true

	spawn_task = task.spawn(function()
		while running do
			local unit_cap = compute_desired_unit_cap()
			local total = count_total_units()
			local deficit = unit_cap - total

			if deficit > 0 then
				-- Spawn multiple groups when under target density.
				-- Estimate group size to decide how many groups we need.
				local avg_group_size = math.max(1, math.floor((GROUP_SIZE_MIN + GROUP_SIZE_MAX) * 0.5))
				local desired_groups = math.ceil(deficit / avg_group_size)
				local groups_to_spawn = math.clamp(desired_groups, 1, SPAWN_BURST_MAX_GROUPS)

				for _ = 1, groups_to_spawn do
					spawn_group()
				end

				task.wait(SPAWN_INTERVAL_ACTIVE_SECONDS)
			else
				-- At/over cap, back off.
				task.wait(SPAWN_INTERVAL_IDLE_SECONDS)
			end
		end
	end)


	cleanup_task = task.spawn(function()
		while running do
			prune_dead_and_expired()
			task.wait(CLEANUP_INTERVAL_SECONDS)
		end
	end)

	ai_task = task.spawn(function()
		while running do
			for _, g in pairs(groups) do
				update_flee_state(g)

				local goal = decide_goal_for_group(g)
				apply_formation(g, goal)

				for i, npc_unit in ipairs(g.units) do
					if npc_unit.humanoid.Health <= 0 then
						continue
					end

					update_target_state(g, npc_unit)

					local state = get_or_create_target_state(npc_unit.model)
					if state.target_model and state.target_root and state.target_humanoid then
						local target_pos = state.target_root.Position
						local leashed_target_pos = clamp_goal_to_leash(
							g.anchor_pos,
							target_pos,
							GROUP_LEASH_RADIUS
						)

						local dist = (npc_unit.root.Position - target_pos).Magnitude
						local is_boss = is_boss_model(npc_unit.model)

						-- 1) MOVEMENT
						-- If fleeing: do NOT override movement here (formation already handles flee).
						-- Bosses never flee (enforced in update_flee_state), so bosses can still move/charge.
						if not g.is_fleeing then
							local move_goal = leashed_target_pos

							if is_boss then
								-- Boss opener: charge through army toward player (ignore army in targeting).
								if get_boss_phase(npc_unit.model) == "Charge" then
									move_goal = leashed_target_pos
									apply_boss_shove(npc_unit.root)

									if dist <= BOSS_CHARGE_END_DISTANCE then
										set_boss_charge_enabled(npc_unit.model, false)
									end
								else
									-- After the charge, behave like normal melee.
									move_goal = compute_attack_approach_goal(
										npc_unit,
										i,
										#g.units,
										leashed_target_pos
									)
								end
							else
								-- Normal units: stick to melee ring
								move_goal = compute_attack_approach_goal(
									npc_unit,
									i,
									#g.units,
									leashed_target_pos
								)
							end

							npc_unit.humanoid:MoveTo(move_goal)
						end

						-- 2) ATTACKING
						-- Always allow attacks if in range (even while fleeing).
						if dist <= ATTACK_RANGE then
							local damage, cooldown = get_attack_stats(npc_unit.model)
							local t = now()

							if (t - npc_unit.last_attack) >= cooldown then
								npc_unit.last_attack = t

								local final_damage = compute_damage_after_defense(
									state.target_model,
									damage
								)

								state.target_model:SetAttribute("LastDamageSourceKind", "NPC")
								state.target_model:SetAttribute("LastHitOwnerUserId", 0)
								state.target_model:SetAttribute("LastHitTime", os.clock())
								state.target_humanoid:TakeDamage(final_damage)
							end
						end
					end
				end
			end

			task.wait(AI_TICK_SECONDS)
		end
	end)
end


function NPCService.stop()
	running = false

	if spawn_task then
		task.cancel(spawn_task)
		spawn_task = nil
	end
	if ai_task then
		task.cancel(ai_task)
		ai_task = nil
	end
	if cleanup_task then
		task.cancel(cleanup_task)
		cleanup_task = nil
	end
end

return NPCService