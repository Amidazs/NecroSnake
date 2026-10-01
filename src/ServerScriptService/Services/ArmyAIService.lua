--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)

local ArmyAIService = {}

local army_service = nil :: any
local running = false
local ai_task: thread? = nil

local NPC_FOLDER_NAME = "NPCs"
local NPC_GROUPS_FOLDER_NAME = "NPCGroups"

-- Only consider enemies within this range of the player.
local AGGRO_RANGE = 40

-- If the unit is too far from the player, it returns (walks back).
local LEASH_RANGE = 70

-- If the unit is WAY too far from the player, teleport it back.
-- Keep this higher than AGGRO_RANGE so normal chasing still happens.
local TELEPORT_BACK_RANGE = 120

-- Prevent rapid teleport spam.
local TELEPORT_COOLDOWN_SECONDS = 1.25

-- Teleport landing snap:
local TELEPORT_RAYCAST_START_HEIGHT = 250
local TELEPORT_RAYCAST_DISTANCE = 900
local TELEPORT_SURFACE_OFFSET = 4


-- If the target is too far from the player, stop chasing and return.
local TARGET_LEASH_RANGE = 45

local ATTACK_RANGE = 6

local AI_TICK_SECONDS = 0.35
local TARGET_ACQUISITION_BUCKETS = 3
local METRIC_REPORT_SECONDS = 2

-- Formation:
local RING_SPACING = 7
local MIN_RING_RADIUS = 8
local MAX_UNITS_PER_RING = 10
local COHORT_SPACING = 5
local COHORT_ROW_SPACING = 4

local COHORT_ORDER = {
	"Frontline",
	"SecondLine",
	"Ranged",
	"Flanks",
	"RearGuard",
	"PersonalGuard",
}

local VALID_COHORTS: { [string]: boolean } = {
	Frontline = true,
	SecondLine = true,
	Ranged = true,
	Flanks = true,
	RearGuard = true,
	PersonalGuard = true,
}

local VALID_FORMATION_PRESETS: { [string]: boolean } = {
	Standard = true,
	Defensive = true,
	Aggressive = true,
	Compact = true,
}

local FORMATION_PRESETS = {
	Standard = {
		spacing = 5,
		rowSpacing = 4,
		frontline = -14,
		secondLine = -7,
		ranged = 7,
		rearGuard = 14,
		personalGuard = 1.5,
		flankX = 11,
		flankStep = 3.5,
		flankZ = -3,
	},
	Defensive = {
		spacing = 5.5,
		rowSpacing = 4.5,
		frontline = -11,
		secondLine = -5,
		ranged = 8.5,
		rearGuard = 15,
		personalGuard = 0.5,
		flankX = 9.5,
		flankStep = 3,
		flankZ = 0,
	},
	Aggressive = {
		spacing = 5,
		rowSpacing = 4,
		frontline = -18,
		secondLine = -11,
		ranged = 4.5,
		rearGuard = 10,
		personalGuard = 1,
		flankX = 14,
		flankStep = 4,
		flankZ = -6,
	},
	Compact = {
		spacing = 3.8,
		rowSpacing = 3.2,
		frontline = -9,
		secondLine = -4.5,
		ranged = 4.5,
		rearGuard = 9,
		personalGuard = 0,
		flankX = 7,
		flankStep = 2.5,
		flankZ = -1,
	},
}

-- Movement smoothing:
local MOVE_REISSUE_SECONDS = 0.45
local MOVE_MIN_DELTA = 3.0

-- Speed: slightly slower than player once in army.
local UNIT_SPEED_MULTIPLIER = 0.95
local UNIT_SPEED_MIN = 10
local UNIT_SPEED_MAX = 22

-- Retargeting:
local RETARGET_COOLDOWN_SECONDS = 0.6
local RETARGET_HYSTERESIS = 2.0

-- Cohort combat behaviour.
local PERSONAL_GUARD_ENGAGE_RANGE = 20
local REAR_GUARD_ENGAGE_RANGE = 30
local RANGED_MIN_STANDOFF = 8
local RANGED_MAX_STANDOFF = 28

-- Lightweight local separation. A spatial bucket pass keeps this close to
-- linear for normal army densities instead of doing an all-pairs scan.
local SEPARATION_CELL_SIZE = 6
local SEPARATION_RADIUS = 4.5
local SEPARATION_STRENGTH = 2.2
local SEPARATION_MAX_OFFSET = 3.2

-- Stuck recovery. Only activates while a unit has an active movement goal and
-- is making effectively no positional progress.
local STUCK_CHECK_SECONDS = 2.5
local STUCK_MIN_PROGRESS = 0.9
local STUCK_GOAL_DISTANCE = 6
local STUCK_NUDGE_DISTANCE = 2.25
local STUCK_HARD_RECOVERY_COUNT = 2

-- Whole-army command foundation.
local COMMAND_MAX_DISTANCE = 120
local COMMAND_ARRIVAL_DISTANCE = 2.5
local RETREAT_COMPLETE_DISTANCE = 18
local RETREAT_SPEED_MULTIPLIER = 1.15

-- Attack approach:
local APPROACH_RADIUS_MIN = 2.5
local APPROACH_RADIUS_MARGIN = 0.6

type UnitState = {
	target: Model?,
	last_attack: number,

	last_move_goal: Vector3?,
	last_move_time: number,

	next_retarget_time: number,

	last_progress_position: Vector3?,
	last_progress_time: number,
	stuck_recoveries: number,
	last_teleport_time: number,
}

type ArmyCommandState = {
	mode: string,
	position: Vector3?,
	target: Model?,
	facing: Vector3?,
}

type AiMetricState = {
	total_ms: number,
	samples: number,
	max_ms: number,
}

local state_by_unit: { [Model]: UnitState } = {}
local command_by_user_id: { [number]: ArmyCommandState } = {}
local metrics_by_user_id: { [number]: AiMetricState } = {}
local command_remote: RemoteEvent? = nil
local ai_cycle = 0
local next_metric_publish = 0

local function now_seconds(): number
	-- Server-safe monotonic-ish timer for cooldown checks.
	return os.clock()
end

local function get_model_root(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end

	local found = model:FindFirstChildWhichIsA("BasePart", true)
	if found and found:IsA("BasePart") then
		return found
	end

	return nil
end


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

local function snap_model_to_ground(model: Model, pos: Vector3): Vector3
	-- Raycast down to find terrain height, then lift by half model height
	-- so the model sits on top of the ground instead of sinking into it.
	local origin = Vector3.new(pos.X, pos.Y + TELEPORT_RAYCAST_START_HEIGHT, pos.Z)
	local direction = Vector3.new(0, -TELEPORT_RAYCAST_DISTANCE, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true

	-- Avoid hitting the unit itself
	params.FilterDescendantsInstances = { model }

	local result = Workspace:Raycast(origin, direction, params)
	if not result then
		-- Fallback: keep original Y if we fail to find ground
		return pos
	end

	local _, size = model:GetBoundingBox()
	local half_height = math.max(2, size.Y * 0.5)

	local target_y = result.Position.Y + half_height + TELEPORT_SURFACE_OFFSET
	return Vector3.new(pos.X, target_y, pos.Z)
end


local function teleport_unit_to_player(unit_model: Model, player_pos: Vector3, slot_pos: Vector3?)
	local u_root = get_model_root(unit_model)
	if not u_root then
		return
	end

	local desired = slot_pos
		or (player_pos
			+ Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
	desired = snap_model_to_ground(unit_model, desired)

	-- Keep facing stable-ish
	local from = u_root.Position
	local look = Vector3.new(from.X, desired.Y, from.Z) - desired
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end

	unit_model:PivotTo(CFrame.new(desired, desired + look.Unit))
end


local function get_root(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function get_effective_attack_range(unit_model: Model): number
	local attack_range = unit_model:GetAttribute("AttackRange")
	if typeof(attack_range) ~= "number" then
		attack_range = ATTACK_RANGE
	end
	return clamp(attack_range, ATTACK_RANGE, 80)
end

local function get_preferred_range_attribute(unit_model: Model): number
	local preferred = unit_model:GetAttribute("PreferredRange")
	if typeof(preferred) == "number" then
		return clamp(preferred, ATTACK_RANGE - 0.5, 60)
	end

	local attack_range = get_effective_attack_range(unit_model)
	if attack_range <= ATTACK_RANGE + 0.5 then
		return ATTACK_RANGE - 1
	end

	return clamp(
		attack_range * 0.78,
		RANGED_MIN_STANDOFF,
		math.min(RANGED_MAX_STANDOFF, attack_range - 1)
	)
end

local function is_alive(model: Model?): boolean
	if not model then
		return false
	end
	local hum = get_humanoid(model)
	return hum ~= nil and hum.Health > 0 and model.Parent ~= nil
end

local function get_or_create_state(unit_model: Model): UnitState
	local s = state_by_unit[unit_model]
	if s then
		return s
	end

	local created: UnitState = {
		target = nil,
		last_attack = 0,

		last_move_goal = nil,
		last_move_time = 0,

		next_retarget_time = 0,

		last_progress_position = nil,
		last_progress_time = now(),
		stuck_recoveries = 0,
		last_teleport_time = 0,
	}

	state_by_unit[unit_model] = created
	return created
end

local function reset_movement_progress(state: UnitState)
	state.last_move_goal = nil
	state.last_move_time = 0
	state.last_progress_position = nil
	state.last_progress_time = now()
	state.stuck_recoveries = 0
end

local function clear_dead_unit_state()
	for model, _ in pairs(state_by_unit) do
		if not is_alive(model) then
			state_by_unit[model] = nil
		end
	end
end

local function get_npc_folder(): Folder?
	local f = Workspace:FindFirstChild(NPC_FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function get_npc_groups_folder(): Folder?
	local f = Workspace:FindFirstChild(NPC_GROUPS_FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function iter_all_npc_models(): { Model }
	local result: { Model } = {}

	local npc_folder = get_npc_folder()
	if npc_folder then
		for _, inst in ipairs(npc_folder:GetChildren()) do
			if inst:IsA("Model") then
				table.insert(result, inst)
			end
		end
	end

	local npc_groups = get_npc_groups_folder()
	if npc_groups then
		for _, inst in ipairs(npc_groups:GetDescendants()) do
			if inst:IsA("Model") then
				table.insert(result, inst)
			end
		end
	end

	return result
end

local function get_enemy_candidates_near_player(
	player: Player,
	player_pos: Vector3
): { Model }
	local candidates: { Model } = {}

	-- 1) Neutral/hostile NPCs.
	for _, m in ipairs(iter_all_npc_models()) do
		if is_alive(m) then
			local r = get_root(m)
			if r then
				local dist = (r.Position - player_pos).Magnitude
				if dist <= AGGRO_RANGE then
					table.insert(candidates, m)
				end
			end
		end
	end

	-- 2) Other players + their army units (PvP).
	for _, other_player in ipairs(Players:GetPlayers()) do
		if other_player ~= player then
			local other_char = other_player.Character
			if other_char and is_alive(other_char) then
				local r = get_root(other_char)
				if r then
					local dist = (r.Position - player_pos).Magnitude
					if dist <= AGGRO_RANGE then
						table.insert(candidates, other_char)
					end
				end
			end

			if army_service and army_service.get_army_units then
				local other_units: { Model } = army_service.get_army_units(other_player)
				for _, u in ipairs(other_units) do
					if u and u.Parent ~= nil and is_alive(u) then
						local r = get_root(u)
						if r then
							local dist = (r.Position - player_pos).Magnitude
							if dist <= AGGRO_RANGE then
								table.insert(candidates, u)
							end
						end
					end
				end
			end
		end
	end

	return candidates
end

local function find_closest_to_unit(unit_pos: Vector3, candidates: { Model }): Model?
	local best: Model? = nil
	local best_dist = math.huge

	for _, m in ipairs(candidates) do
		local r = get_root(m)
		if r then
			local dist = (r.Position - unit_pos).Magnitude
			if dist < best_dist then
				best_dist = dist
				best = m
			end
		end
	end

	return best
end

local function compute_damage_after_defense(target: Model, raw_damage: number): number
	local defense = target:GetAttribute("Defense")
	if typeof(defense) ~= "number" then
		defense = 0
	end

	defense = clamp(defense, 0, 0.9)
	local final = raw_damage * (1 - defense)

	return math.max(1, math.floor(final + 0.5))
end

local function get_spawn_time_seed(model: Model): number
	local spawn_time = model:GetAttribute("SpawnTime")
	if typeof(spawn_time) == "number" then
		return spawn_time
	end
	return 0
end

local function emit_arrow_tracer(from_root: BasePart, target_root: BasePart)
	local start_pos = from_root.Position + Vector3.new(0, 1.5, 0)
	local end_pos = target_root.Position + Vector3.new(0, 1.2, 0)
	local delta = end_pos - start_pos
	if delta.Magnitude < 0.1 then
		return
	end

	local arrow = Instance.new("Part")
	arrow.Name = "NecroArrowTracer"
	arrow.Size = Vector3.new(0.12, 0.12, 1.7)
	arrow.Color = Color3.fromRGB(117, 79, 44)
	arrow.Material = Enum.Material.Wood
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanTouch = false
	arrow.CanQuery = false
	arrow.CastShadow = false
	arrow.CFrame = CFrame.lookAt(start_pos, end_pos)
	arrow.Parent = Workspace

	local travel_time = clamp(delta.Magnitude / 85, 0.12, 0.42)
	TweenService:Create(
		arrow,
		TweenInfo.new(travel_time, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(end_pos, end_pos + delta.Unit) }
	):Play()
	Debris:AddItem(arrow, travel_time + 0.08)
end

local function stamp_last_hit_owner(attacker: Model, target: Model)
	local owner_user_id = attacker:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) ~= "number" then
		return
	end

	target:SetAttribute("LastDamageSourceKind", "PLAYER_ARMY")
	target:SetAttribute("LastHitOwnerUserId", owner_user_id)
	target:SetAttribute("LastHitTime", now())
end

local function try_attack(attacker: Model, target: Model, s: UnitState)
	local a_root = get_root(attacker)
	local t_root = get_root(target)
	local t_hum = get_humanoid(target)
	local a_hum = get_humanoid(attacker)

	if not (a_root and t_root and t_hum and a_hum) then
		return
	end

	if a_hum.Health <= 0 or t_hum.Health <= 0 then
		return
	end

	local dist = (a_root.Position - t_root.Position).Magnitude
	local attack_range = get_effective_attack_range(attacker)
	if dist > attack_range then
		return
	end

	local raw_damage = attacker:GetAttribute("Damage")
	if typeof(raw_damage) ~= "number" then
		raw_damage = 10
	end

	local cooldown = attacker:GetAttribute("AttackCooldown")
	if typeof(cooldown) ~= "number" then
		cooldown = 1.0
	end

	local t = now()
	if (t - s.last_attack) < cooldown then
		return
	end

	s.last_attack = t

	-- Important: mark who got the last hit BEFORE applying damage.
	stamp_last_hit_owner(attacker, target)

	if attack_range > ATTACK_RANGE + 0.5 then
		emit_arrow_tracer(a_root, t_root)
	end

	local final_damage = compute_damage_after_defense(target, raw_damage)
	t_hum:TakeDamage(final_damage)
end

local function compute_attack_approach_goal(
	unit_model: Model,
	unit_index: number,
	unit_count: number,
	target_pos: Vector3
): Vector3
	-- Keep approach INSIDE ATTACK_RANGE so units actually hit.
	local count = math.max(1, unit_count)

	local seed = get_spawn_time_seed(unit_model)
	local extra = ((seed % 17) * 0.06)

	local angle = ((unit_index - 1) / count) * (math.pi * 2)

	local max_radius = math.max(APPROACH_RADIUS_MIN, ATTACK_RANGE - APPROACH_RADIUS_MARGIN)
	local radius = clamp((ATTACK_RANGE - 1.0) + extra, APPROACH_RADIUS_MIN, max_radius)

	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return Vector3.new(target_pos.X, target_pos.Y, target_pos.Z) + offset
end

local function compute_formation_slots(center: Vector3, count: number): { Vector3 }
	local slots: { Vector3 } = {}

	if count <= 0 then
		return slots
	end

	local remaining = count
	local ring = 1

	while remaining > 0 do
		local radius = MIN_RING_RADIUS + ((ring - 1) * RING_SPACING)
		local ring_capacity = math.min(MAX_UNITS_PER_RING, remaining)
		local angle_step = (math.pi * 2) / ring_capacity

		for i = 1, ring_capacity do
			local angle = (i - 1) * angle_step
			local x = math.cos(angle) * radius
			local z = math.sin(angle) * radius
			table.insert(slots, Vector3.new(center.X + x, center.Y, center.Z + z))
		end

		remaining -= ring_capacity
		ring += 1
	end

	return slots
end

local function get_unit_cohort(unit_model: Model): string
	local cohort = unit_model:GetAttribute("Cohort")
	if typeof(cohort) == "string" and VALID_COHORTS[cohort] then
		return cohort
	end

	local fallback = unit_model:GetAttribute("DefaultCohort")
	if typeof(fallback) ~= "string" or not VALID_COHORTS[fallback] then
		fallback = "SecondLine"
	end
	unit_model:SetAttribute("Cohort", fallback)
	return fallback
end

local function get_formation_preset(player: Player): string
	local preset = player:GetAttribute("FormationPreset")
	if typeof(preset) == "string" and VALID_FORMATION_PRESETS[preset] then
		return preset
	end

	player:SetAttribute("FormationPreset", "Standard")
	return "Standard"
end

local function get_unit_preferred_range(unit_model: Model): number
	local attack_range = get_effective_attack_range(unit_model)
	local cohort = get_unit_cohort(unit_model)

	if cohort == "Ranged" or cohort == "RearGuard" then
		return get_preferred_range_attribute(unit_model)
	end

	if attack_range <= ATTACK_RANGE + 0.5 then
		return ATTACK_RANGE - 1
	end
	return math.max(ATTACK_RANGE - 1, attack_range - 1.5)
end

local function get_auto_engage_limit(unit_model: Model): number
	local cohort = get_unit_cohort(unit_model)
	if cohort == "PersonalGuard" then
		return PERSONAL_GUARD_ENGAGE_RANGE
	end
	if cohort == "RearGuard" then
		return REAR_GUARD_ENGAGE_RANGE
	end
	return TARGET_LEASH_RANGE
end

local function make_anchor_cframe(position: Vector3, facing: Vector3): CFrame
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

local function compute_band_slot(
	anchor: CFrame,
	index: number,
	count: number,
	base_z: number,
	max_per_row: number,
	spacing: number,
	row_spacing: number
): Vector3
	local row = math.floor((index - 1) / max_per_row)
	local first_in_row = row * max_per_row
	local remaining = count - first_in_row
	local row_count = math.min(max_per_row, remaining)
	local position_in_row = index - first_in_row
	local x = (position_in_row - ((row_count + 1) * 0.5)) * spacing
	local z = base_z + (row * row_spacing)
	return anchor:PointToWorldSpace(Vector3.new(x, 0, z))
end

local function compute_cohort_formation_slots(
	anchor: CFrame,
	units: { Model },
	preset_name: string?
): { Vector3 }
	local groups: { [string]: { number } } = {}
	for _, cohort in ipairs(COHORT_ORDER) do
		groups[cohort] = {}
	end

	for index, unit_model in ipairs(units) do
		local cohort = get_unit_cohort(unit_model)
		table.insert(groups[cohort], index)
	end

	for _, cohort in ipairs(COHORT_ORDER) do
		table.sort(groups[cohort], function(a, b)
			local a_id = units[a]:GetAttribute("ArmyUnitId")
			local b_id = units[b]:GetAttribute("ArmyUnitId")
			local a_num = typeof(a_id) == "number" and a_id or a
			local b_num = typeof(b_id) == "number" and b_id or b
			return a_num < b_num
		end)
	end

	local preset = FORMATION_PRESETS[preset_name or "Standard"]
		or FORMATION_PRESETS.Standard
	local slots: { Vector3 } = table.create(#units)

	local function assign_band(cohort: string, base_z: number, max_per_row: number)
		local indices = groups[cohort]
		for local_index, unit_index in ipairs(indices) do
			slots[unit_index] = compute_band_slot(
				anchor,
				local_index,
				#indices,
				base_z,
				max_per_row,
				preset.spacing,
				preset.rowSpacing
			)
		end
	end

	assign_band("Frontline", preset.frontline, 6)
	assign_band("SecondLine", preset.secondLine, 6)
	assign_band("Ranged", preset.ranged, 7)
	assign_band("RearGuard", preset.rearGuard, 6)
	assign_band("PersonalGuard", preset.personalGuard, 4)

	local flank_indices = groups.Flanks
	for local_index, unit_index in ipairs(flank_indices) do
		local pair_index = math.floor((local_index - 1) / 2)
		local side = local_index % 2 == 1 and -1 or 1
		local x = side * (preset.flankX + (pair_index * preset.flankStep))
		local z = preset.flankZ + ((pair_index % 3) * preset.rowSpacing)
		slots[unit_index] = anchor:PointToWorldSpace(Vector3.new(x, 0, z))
	end

	return slots
end

local function build_cohort_meta(units: { Model })
	local groups: { [string]: { Model } } = {}
	for _, cohort in ipairs(COHORT_ORDER) do
		groups[cohort] = {}
	end

	for _, unit_model in ipairs(units) do
		local cohort = get_unit_cohort(unit_model)
		table.insert(groups[cohort], unit_model)
	end

	local meta: { [Model]: any } = {}
	for _, cohort in ipairs(COHORT_ORDER) do
		local members = groups[cohort]
		table.sort(members, function(a, b)
			local a_id = a:GetAttribute("ArmyUnitId")
			local b_id = b:GetAttribute("ArmyUnitId")
			local a_num = typeof(a_id) == "number" and a_id or 0
			local b_num = typeof(b_id) == "number" and b_id or 0
			return a_num < b_num
		end)

		for index, unit_model in ipairs(members) do
			meta[unit_model] = {
				cohort = cohort,
				index = index,
				count = #members,
			}
		end
	end
	return meta
end

local function bucket_key(x: number, z: number): string
	return ("%d:%d"):format(x, z)
end

local function build_separation_offsets(units: { Model }): { [Model]: Vector3 }
	local buckets: { [string]: { Model } } = {}
	local positions: { [Model]: Vector3 } = {}

	for _, unit_model in ipairs(units) do
		local root = get_root(unit_model)
		if root then
			local position = root.Position
			positions[unit_model] = position

			local bx = math.floor(position.X / SEPARATION_CELL_SIZE)
			local bz = math.floor(position.Z / SEPARATION_CELL_SIZE)
			local key = bucket_key(bx, bz)
			if not buckets[key] then
				buckets[key] = {}
			end
			table.insert(buckets[key], unit_model)
		end
	end

	local offsets: { [Model]: Vector3 } = {}
	for unit_model, position in pairs(positions) do
		local bx = math.floor(position.X / SEPARATION_CELL_SIZE)
		local bz = math.floor(position.Z / SEPARATION_CELL_SIZE)
		local push = Vector3.zero

		for x = bx - 1, bx + 1 do
			for z = bz - 1, bz + 1 do
				local members = buckets[bucket_key(x, z)]
				if members then
					for _, other in ipairs(members) do
						if other ~= unit_model then
							local other_position = positions[other]
							if other_position then
								local delta = Vector3.new(
									position.X - other_position.X,
									0,
									position.Z - other_position.Z
								)
								local distance = delta.Magnitude
								if distance < SEPARATION_RADIUS then
									if distance < 0.05 then
										local unit_id = unit_model:GetAttribute("ArmyUnitId")
										local seed = typeof(unit_id) == "number" and unit_id or 1
										local angle = (seed % 16) / 16 * math.pi * 2
										delta = Vector3.new(
											math.cos(angle),
											0,
											math.sin(angle)
										)
										distance = 0.05
									end

									local weight = (
										(SEPARATION_RADIUS - distance)
										/ SEPARATION_RADIUS
									)
									push += delta.Unit * weight
								end
							end
						end
					end
				end
			end
		end

		if push.Magnitude > 0.001 then
			local magnitude = math.min(
				SEPARATION_MAX_OFFSET,
				push.Magnitude * SEPARATION_STRENGTH
			)
			offsets[unit_model] = push.Unit * magnitude
		else
			offsets[unit_model] = Vector3.zero
		end
	end

	return offsets
end

local function with_separation(
	goal: Vector3,
	unit_model: Model,
	offsets: { [Model]: Vector3 }
): Vector3
	return goal + (offsets[unit_model] or Vector3.zero)
end

local function compute_combat_goal(
	unit_model: Model,
	local_index: number,
	local_count: number,
	target_pos: Vector3,
	player_pos: Vector3
): Vector3
	local direction = target_pos - player_pos
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end

	local anchor = CFrame.lookAt(target_pos, target_pos + flat.Unit)
	local cohort = get_unit_cohort(unit_model)
	local preferred_range = get_unit_preferred_range(unit_model)
	local attack_range = get_effective_attack_range(unit_model)

	if cohort == "PersonalGuard" then
		local player_anchor = make_anchor_cframe(player_pos, flat)
		local side = local_index % 2 == 1 and -1 or 1
		local pair = math.floor((local_index - 1) / 2)
		return player_anchor:PointToWorldSpace(
			Vector3.new(side * (3 + pair * 2.5), 0, 2 + pair * 1.5)
		)
	end

	if cohort == "Ranged" and attack_range > ATTACK_RANGE + 0.5 then
		local width = math.min(7, math.max(1, local_count))
		return compute_band_slot(
			anchor,
			local_index,
			local_count,
			preferred_range,
			width,
			4.5,
			3.5
		)
	end

	if cohort == "RearGuard" and attack_range > ATTACK_RANGE + 0.5 then
		return compute_band_slot(
			anchor,
			local_index,
			local_count,
			math.min(attack_range - 0.5, preferred_range + 4),
			6,
			4.5,
			3.5
		)
	end

	if cohort == "Flanks" then
		local pair = math.floor((local_index - 1) / 2)
		local side = local_index % 2 == 1 and -1 or 1
		local x = side * (4.3 + pair * 2.8)
		local z = 2.6 + (pair % 2) * 1.2
		return anchor:PointToWorldSpace(Vector3.new(x, 0, z))
	end

	local melee_row_size = cohort == "Frontline" and 4 or 3
	local base_z = cohort == "Frontline" and 4.2 or 5.1
	return compute_band_slot(
		anchor,
		local_index,
		local_count,
		base_z,
		melee_row_size,
		2.4,
		2.2
	)
end

local function should_unit_engage_target(
	unit_model: Model,
	target: Model,
	player_pos: Vector3
): boolean
	local target_root = get_root(target)
	if not target_root then
		return false
	end
	return (target_root.Position - player_pos).Magnitude
		<= get_auto_engage_limit(unit_model)
end

local function find_closest_engageable(
	unit_model: Model,
	unit_pos: Vector3,
	player_pos: Vector3,
	candidates: { Model }
): Model?
	local best: Model? = nil
	local best_distance = math.huge

	for _, candidate in ipairs(candidates) do
		if should_unit_engage_target(unit_model, candidate, player_pos) then
			local root = get_root(candidate)
			if root then
				local distance = (root.Position - unit_pos).Magnitude
				if distance < best_distance then
					best = candidate
					best_distance = distance
				end
			end
		end
	end

	return best
end

local function move_unit_smooth(humanoid: Humanoid, s: UnitState, goal: Vector3)
	local t = now()
	local model = humanoid.Parent
	local root: BasePart? = nil
	if model and model:IsA("Model") then
		root = get_root(model)
	end

	if root and model and model:IsA("Model") then
		local position = root.Position
		if not s.last_progress_position then
			s.last_progress_position = position
			s.last_progress_time = t
		else
			local progress = (position - s.last_progress_position).Magnitude
			local distance_to_goal = (goal - position).Magnitude

			if progress >= STUCK_MIN_PROGRESS then
				s.last_progress_position = position
				s.last_progress_time = t
				s.stuck_recoveries = 0
			elseif distance_to_goal > STUCK_GOAL_DISTANCE
				and (t - s.last_progress_time) >= STUCK_CHECK_SECONDS
			then
				s.stuck_recoveries += 1
				humanoid.PlatformStand = false
				humanoid.AutoRotate = true

				local current_state = humanoid:GetState()
				if current_state == Enum.HumanoidStateType.GettingUp
					or current_state == Enum.HumanoidStateType.FallingDown
					or current_state == Enum.HumanoidStateType.Physics
					or current_state == Enum.HumanoidStateType.Ragdoll
					or current_state == Enum.HumanoidStateType.PlatformStanding
				then
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end

				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				pcall(function()
					root:SetNetworkOwner(nil)
				end)

				local flat_delta = Vector3.new(
					goal.X - position.X,
					0,
					goal.Z - position.Z
				)
				if flat_delta.Magnitude > 0.05 then
					local recovery_position: Vector3
					if s.stuck_recoveries >= STUCK_HARD_RECOVERY_COUNT then
						recovery_position = snap_model_to_ground(model, goal)
					else
						recovery_position = snap_model_to_ground(
							model,
							position
								+ (flat_delta.Unit * STUCK_NUDGE_DISTANCE)
								+ Vector3.new(0, 1, 0)
						)
					end
					model:PivotTo(CFrame.lookAt(
						recovery_position,
						recovery_position + flat_delta.Unit
					))
				end

				s.last_progress_position = root.Position
				s.last_progress_time = t
				s.last_move_goal = nil
				s.last_move_time = 0

				task.delay(0.8, function()
					if root and root.Parent then
						pcall(function()
							root:SetNetworkOwnershipAuto()
						end)
					end
				end)
			end
		end
	end

	if s.last_move_goal then
		local delta = (goal - s.last_move_goal).Magnitude
		if delta < MOVE_MIN_DELTA and (t - s.last_move_time) < MOVE_REISSUE_SECONDS then
			return
		end
	end

	s.last_move_goal = goal
	s.last_move_time = t
	humanoid:MoveTo(goal)
end

local function maybe_retarget_to_closer(
	unit_model: Model,
	unit_pos: Vector3,
	player_pos: Vector3,
	s: UnitState,
	candidates: { Model }
)
	if now() < s.next_retarget_time then
		return
	end

	if not s.target then
		return
	end

	local t_root = get_root(s.target)
	if not t_root then
		return
	end

	local current_dist = (t_root.Position - unit_pos).Magnitude
	local best = find_closest_engageable(
		unit_model,
		unit_pos,
		player_pos,
		candidates
	)
	if not best or best == s.target then
		return
	end

	local best_root = get_root(best)
	if not best_root then
		return
	end

	local best_dist = (best_root.Position - unit_pos).Magnitude
	if best_dist + RETARGET_HYSTERESIS < current_dist then
		s.target = best
		s.next_retarget_time = now() + RETARGET_COOLDOWN_SECONDS
	end
end

local function get_command_state(player: Player): ArmyCommandState
	get_formation_preset(player)

	local existing = command_by_user_id[player.UserId]
	if existing then
		return existing
	end

	local created: ArmyCommandState = {
		mode = "FOLLOW",
		position = nil,
		target = nil,
		facing = nil,
	}
	command_by_user_id[player.UserId] = created
	player:SetAttribute("ArmyCommandMode", "FOLLOW")
	return created
end

local function send_command_feedback(
	player: Player,
	mode: string,
	message: string
)
	if command_remote then
		command_remote:FireClient(player, {
			mode = mode,
			message = message,
		})
	end
end

local function set_command(
	player: Player,
	mode: string,
	position: Vector3?,
	target: Model?,
	message: string
)
	local facing: Vector3? = nil
	if position then
		local character = player.Character
		local root = character and get_root(character)
		if root then
			local look = root.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.01 then
				facing = flat.Unit
			end
		end
	end

	command_by_user_id[player.UserId] = {
		mode = mode,
		position = position,
		target = target,
		facing = facing,
	}
	player:SetAttribute("ArmyCommandMode", mode)
	send_command_feedback(player, mode, message)
end

local function get_army_center(player: Player, fallback: Vector3): Vector3
	local units: { Model } = army_service.get_army_units(player)
	local total = Vector3.zero
	local count = 0

	for _, model in ipairs(units) do
		if is_alive(model) then
			local root = get_root(model)
			if root then
				total += root.Position
				count += 1
			end
		end
	end

	if count <= 0 then
		return fallback
	end
	return total / count
end

local function snap_command_position(player: Player, requested: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false

	local excluded: { Instance } = {}
	if player.Character then
		table.insert(excluded, player.Character)
	end
	local armies = Workspace:FindFirstChild("PlayerArmies")
	if armies then
		table.insert(excluded, armies)
	end
	params.FilterDescendantsInstances = excluded

	local origin = requested + Vector3.new(0, 180, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -500, 0), params)
	if result then
		return result.Position
	end
	return requested
end

local function is_valid_command_target(player: Player, target: Model): boolean
	if target == player.Character or not is_alive(target) then
		return false
	end

	local owner_user_id = target:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) == "number" and owner_user_id == player.UserId then
		return false
	end

	return true
end

local function handle_command_request(
	player: Player,
	action: any,
	payload: any
)
	if typeof(action) ~= "string" then
		return
	end

	local char = player.Character
	local player_root = char and get_root(char)
	if not player_root then
		return
	end

	if action == "FOLLOW" then
		set_command(
			player,
			"FOLLOW",
			nil,
			nil,
			"Army regrouping and following."
		)
		return
	end

	if action == "RETREAT" then
		set_command(
			player,
			"RETREAT",
			nil,
			nil,
			"Army retreating to you."
		)
		return
	end

	if action == "HOLD" then
		local center = get_army_center(player, player_root.Position)
		set_command(
			player,
			"HOLD",
			center,
			nil,
			"Army holding position."
		)
		return
	end

	if action == "MOVE" then
		if typeof(payload) ~= "Vector3" then
			send_command_feedback(player, get_command_state(player).mode, "Choose a ground position.")
			return
		end
		if (payload - player_root.Position).Magnitude > COMMAND_MAX_DISTANCE then
			send_command_feedback(player, get_command_state(player).mode, "That position is too far away.")
			return
		end

		local position = snap_command_position(player, payload)
		set_command(
			player,
			"MOVE",
			position,
			nil,
			"Army moving to the marked position."
		)
		return
	end

	if action == "SET_FORMATION_PRESET" then
		if typeof(payload) ~= "string" or not VALID_FORMATION_PRESETS[payload] then
			return
		end

		player:SetAttribute("FormationPreset", payload)

		local units: { Model } = army_service.get_army_units(player)
		for _, unit_model in ipairs(units) do
			local state = state_by_unit[unit_model]
			if state then
				reset_movement_progress(state)
			end
		end

		send_command_feedback(
			player,
			get_command_state(player).mode,
			("Formation switched to %s."):format(payload)
		)
		return
	end

	if action == "SET_COHORT" then
		if typeof(payload) ~= "table" then
			return
		end

		local target = payload.target
		local cohort = payload.cohort
		if typeof(target) ~= "Instance"
			or not target:IsA("Model")
			or typeof(cohort) ~= "string"
			or not VALID_COHORTS[cohort]
		then
			return
		end

		if target:GetAttribute("ArmyOwnerUserId") ~= player.UserId
			or not is_alive(target)
		then
			send_command_feedback(
				player,
				get_command_state(player).mode,
				"Aim at one of your living undead."
			)
			return
		end

		target:SetAttribute("Cohort", cohort)
		local target_state = state_by_unit[target]
		if target_state then
			reset_movement_progress(target_state)
		end
		send_command_feedback(
			player,
			get_command_state(player).mode,
			("%s assigned to %s."):format(target.Name, cohort)
		)
		return
	end

	if action == "ATTACK" then
		if typeof(payload) ~= "Instance" or not payload:IsA("Model") then
			send_command_feedback(player, get_command_state(player).mode, "Choose an enemy target.")
			return
		end
		if not is_valid_command_target(player, payload) then
			send_command_feedback(player, get_command_state(player).mode, "That is not a valid enemy target.")
			return
		end

		local target_root = get_root(payload)
		if not target_root or (target_root.Position - player_root.Position).Magnitude > COMMAND_MAX_DISTANCE then
			send_command_feedback(player, get_command_state(player).mode, "That enemy is too far away.")
			return
		end

		set_command(
			player,
			"ATTACK",
			nil,
			payload,
			"Army attacking the selected target."
		)
	end
end

local function tick_commanded_mode(
	player: Player,
	alive_units: { Model },
	player_pos: Vector3,
	player_cframe: CFrame,
	player_speed: number
): boolean
	local command = get_command_state(player)
	if command.mode == "FOLLOW" then
		return false
	end

	local desired_speed = clamp(
		player_speed * UNIT_SPEED_MULTIPLIER,
		UNIT_SPEED_MIN,
		UNIT_SPEED_MAX
	)
	local preset_name = get_formation_preset(player)
	local separation_offsets = build_separation_offsets(alive_units)
	local cohort_meta = build_cohort_meta(alive_units)

	if command.mode == "MOVE" or command.mode == "HOLD" then
		local center = command.position or player_pos
		local facing = command.facing or player_cframe.LookVector
		local anchor = make_anchor_cframe(center, facing)
		local slots = compute_cohort_formation_slots(
			anchor,
			alive_units,
			preset_name
		)
		local all_arrived = true

		for i, unit_model in ipairs(alive_units) do
			local root = get_root(unit_model)
			local humanoid = get_humanoid(unit_model)
			if not (root and humanoid) then
				continue
			end

			humanoid.WalkSpeed = desired_speed
			local state = get_or_create_state(unit_model)
			state.target = nil

			local slot = slots[i]
			if slot then
				local goal = with_separation(
					slot,
					unit_model,
					separation_offsets
				)
				local distance = (root.Position - slot).Magnitude
				if distance > COMMAND_ARRIVAL_DISTANCE then
					all_arrived = false
					move_unit_smooth(humanoid, state, goal)
				end
			end
		end

		if command.mode == "MOVE" and all_arrived then
			set_command(
				player,
				"HOLD",
				center,
				nil,
				"Move complete. Army holding position."
			)
		end
		return true
	end

	if command.mode == "RETREAT" then
		local slots = compute_cohort_formation_slots(
			player_cframe,
			alive_units,
			preset_name
		)
		local all_close = true
		local retreat_speed = clamp(
			player_speed * RETREAT_SPEED_MULTIPLIER,
			UNIT_SPEED_MIN,
			UNIT_SPEED_MAX + 4
		)

		for i, unit_model in ipairs(alive_units) do
			local root = get_root(unit_model)
			local humanoid = get_humanoid(unit_model)
			if not (root and humanoid) then
				continue
			end

			humanoid.WalkSpeed = retreat_speed
			local state = get_or_create_state(unit_model)
			state.target = nil

			if (root.Position - player_pos).Magnitude > RETREAT_COMPLETE_DISTANCE then
				all_close = false
			end

			local slot = slots[i]
			if slot then
				move_unit_smooth(
					humanoid,
					state,
					with_separation(slot, unit_model, separation_offsets)
				)
			end
		end

		if all_close then
			set_command(
				player,
				"FOLLOW",
				nil,
				nil,
				"Retreat complete. Army following."
			)
		end
		return true
	end

	if command.mode == "ATTACK" then
		local target = command.target
		if not target or not is_valid_command_target(player, target) then
			set_command(
				player,
				"FOLLOW",
				nil,
				nil,
				"Target lost. Army following."
			)
			return true
		end

		local target_root = get_root(target)
		if not target_root
			or (target_root.Position - player_pos).Magnitude > COMMAND_MAX_DISTANCE
		then
			set_command(
				player,
				"FOLLOW",
				nil,
				nil,
				"Target moved out of command range."
			)
			return true
		end

		for _, unit_model in ipairs(alive_units) do
			local root = get_root(unit_model)
			local humanoid = get_humanoid(unit_model)
			if not (root and humanoid) then
				continue
			end

			humanoid.WalkSpeed = desired_speed
			local state = get_or_create_state(unit_model)
			local meta = cohort_meta[unit_model]
			local cohort = meta and meta.cohort or get_unit_cohort(unit_model)
			local local_index = meta and meta.index or 1
			local local_count = meta and meta.count or 1

			if cohort == "PersonalGuard"
				and (target_root.Position - player_pos).Magnitude
					> PERSONAL_GUARD_ENGAGE_RANGE
			then
				state.target = nil
				local guard_goal = compute_combat_goal(
					unit_model,
					local_index,
					local_count,
					target_root.Position,
					player_pos
				)
				move_unit_smooth(
					humanoid,
					state,
					with_separation(
						guard_goal,
						unit_model,
						separation_offsets
					)
				)
				continue
			end

			state.target = target

			local distance = (root.Position - target_root.Position).Magnitude
			local attack_range = get_effective_attack_range(unit_model)
			local preferred_range = get_unit_preferred_range(unit_model)
			local should_reposition = distance > (attack_range - 0.25)

			if attack_range > ATTACK_RANGE + 0.5
				and distance < (preferred_range - 2)
			then
				should_reposition = true
			end

			if should_reposition then
				local approach = compute_combat_goal(
					unit_model,
					local_index,
					local_count,
					target_root.Position,
					player_pos
				)
				move_unit_smooth(
					humanoid,
					state,
					with_separation(
						approach,
						unit_model,
						separation_offsets
					)
				)
			end
			try_attack(unit_model, target, state)
		end
		return true
	end

	set_command(player, "FOLLOW", nil, nil, "Army following.")
	return false
end

local function should_refresh_target(unit_model: Model): boolean
	local unit_id = unit_model:GetAttribute("ArmyUnitId")
	if typeof(unit_id) ~= "number" then
		return true
	end

	local bucket = math.floor(unit_id) % TARGET_ACQUISITION_BUCKETS
	return bucket == (ai_cycle % TARGET_ACQUISITION_BUCKETS)
end

local function record_tick_metric(player: Player, elapsed_seconds: number)
	local state = metrics_by_user_id[player.UserId]
	if not state then
		state = { total_ms = 0, samples = 0, max_ms = 0 }
		metrics_by_user_id[player.UserId] = state
	end

	local elapsed_ms = elapsed_seconds * 1000
	state.total_ms += elapsed_ms
	state.samples += 1
	state.max_ms = math.max(state.max_ms, elapsed_ms)
end

local function publish_metrics_if_due()
	local current_time = now()
	if current_time < next_metric_publish then
		return
	end
	next_metric_publish = current_time + METRIC_REPORT_SECONDS

	for _, player in ipairs(Players:GetPlayers()) do
		local metric = metrics_by_user_id[player.UserId]
		if metric and metric.samples > 0 then
			player:SetAttribute(
				"ArmyAITickAverageMs",
				metric.total_ms / metric.samples
			)
			player:SetAttribute("ArmyAITickMaxMs", metric.max_ms)
		end

		local unit_count = 0
		if army_service and army_service.get_army_units then
			unit_count = #army_service.get_army_units(player)
		end
		player:SetAttribute("ArmyAIUnitCount", unit_count)
		metrics_by_user_id[player.UserId] = nil
	end
end

local function tick_player(player: Player)
	if not army_service or not army_service.get_army_units then
		return
	end

	local char = player.Character
	if not (char and is_alive(char)) then
		return
	end

	local hrp = get_root(char)
	local hum = get_humanoid(char)
	if not (hrp and hum) then
		return
	end

	local player_pos = hrp.Position
	local player_speed = hum.WalkSpeed

	local units: { Model } = army_service.get_army_units(player)
	if #units <= 0 then
		return
	end

	local alive_units: { Model } = {}
	for _, u in ipairs(units) do
		if is_alive(u) then
			table.insert(alive_units, u)
		end
	end
	if #alive_units <= 0 then
		return
	end

	if tick_commanded_mode(
		player,
		alive_units,
		player_pos,
		hrp.CFrame,
		player_speed
	) then
		return
	end

	local desired_speed = clamp(
		player_speed * UNIT_SPEED_MULTIPLIER,
		UNIT_SPEED_MIN,
		UNIT_SPEED_MAX
	)

	local preset_name = get_formation_preset(player)
	local slots = compute_cohort_formation_slots(
		hrp.CFrame,
		alive_units,
		preset_name
	)
	local separation_offsets = build_separation_offsets(alive_units)
	local cohort_meta = build_cohort_meta(alive_units)
	local candidates = get_enemy_candidates_near_player(player, player_pos)

	for i, unit_model in ipairs(alive_units) do
		local u_root = get_root(unit_model)
		local u_hum = get_humanoid(unit_model)
		if not (u_root and u_hum) then
			continue
		end

		u_hum.WalkSpeed = desired_speed

		local s = get_or_create_state(unit_model)

		-- Leash to player.
		-- Leash to player.
		local dist_to_player = (u_root.Position - player_pos).Magnitude

		if dist_to_player > TELEPORT_BACK_RANGE then
			-- Teleport back (failsafe for stuck units).
			local last_tp = s.last_teleport_time
			if typeof(last_tp) ~= "number" then
				last_tp = 0
			end

			if (now_seconds() - last_tp) >= TELEPORT_COOLDOWN_SECONDS then
				s.target = nil
				s.last_teleport_time = now()

				local slot = slots[i]
				teleport_unit_to_player(unit_model, player_pos, slot)
			end

			continue
		end

		if dist_to_player > LEASH_RANGE then
			-- Walk back normally.
			s.target = nil
			local slot = slots[i]
			if slot then
				move_unit_smooth(
					u_hum,
					s,
					with_separation(slot, unit_model, separation_offsets)
				)
			end
			continue
		end


		-- Spread expensive target searches across several AI cycles.
		if not s.target then
			if should_refresh_target(unit_model) then
				local best = find_closest_engageable(
					unit_model,
					u_root.Position,
					player_pos,
					candidates
				)
				if best then
					s.target = best
					s.next_retarget_time = now() + RETARGET_COOLDOWN_SECONDS
				end
			end
		else
			-- Validate every cycle, but only search for a better target in
			-- this unit's acquisition bucket.
			if not is_alive(s.target)
				or not should_unit_engage_target(
					unit_model,
					s.target,
					player_pos
				)
			then
				s.target = nil
			elseif should_refresh_target(unit_model) then
				maybe_retarget_to_closer(
					unit_model,
					u_root.Position,
					player_pos,
					s,
					candidates
				)
			end
		end

		-- Act.
		if s.target then
			local t_root = get_root(s.target)
			if t_root then
				local dist_to_target = (u_root.Position - t_root.Position).Magnitude
				local attack_range = get_effective_attack_range(unit_model)
				local preferred_range = get_unit_preferred_range(unit_model)
				local should_reposition = dist_to_target > (attack_range - 0.25)

				if attack_range > ATTACK_RANGE + 0.5
					and dist_to_target < (preferred_range - 2)
				then
					should_reposition = true
				end

				if should_reposition then
					local meta = cohort_meta[unit_model]
					local approach = compute_combat_goal(
						unit_model,
						meta and meta.index or 1,
						meta and meta.count or 1,
						t_root.Position,
						player_pos
					)
					move_unit_smooth(
						u_hum,
						s,
						with_separation(
							approach,
							unit_model,
							separation_offsets
						)
					)
				end

				try_attack(unit_model, s.target, s)
			else
				s.target = nil
			end
		end

		if not s.target then
			local slot = slots[i]
			if slot then
				move_unit_smooth(
					u_hum,
					s,
					with_separation(slot, unit_model, separation_offsets)
				)
			end
		end
	end
end

function ArmyAIService.init(army_service_module)
	army_service = army_service_module
end

function ArmyAIService.start()
	if running then
		return
	end
	running = true

	command_remote = Remotes.army_command()
	command_remote.OnServerEvent:Connect(handle_command_request)

	for _, player in ipairs(Players:GetPlayers()) do
		get_command_state(player)
	end
	Players.PlayerAdded:Connect(function(player)
		get_command_state(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		command_by_user_id[player.UserId] = nil
	end)

	ai_task = task.spawn(function()
		while running do
			clear_dead_unit_state()
			ai_cycle += 1

			for _, player in ipairs(Players:GetPlayers()) do
				local started_at = now()
				tick_player(player)
				record_tick_metric(player, now() - started_at)
			end

			publish_metrics_if_due()
			task.wait(AI_TICK_SECONDS)
		end
	end)
end

function ArmyAIService.stop()
	running = false
	if ai_task then
		task.cancel(ai_task)
		ai_task = nil
	end
end

return ArmyAIService
