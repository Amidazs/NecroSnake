--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

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

-- Formation:
local RING_SPACING = 7
local MIN_RING_RADIUS = 8
local MAX_UNITS_PER_RING = 10

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

-- Attack approach:
local APPROACH_RADIUS_MIN = 2.5
local APPROACH_RADIUS_MARGIN = 0.6

type UnitState = {
	target: Model?,
	last_attack: number,

	last_move_goal: Vector3?,
	last_move_time: number,

	next_retarget_time: number,
}

local state_by_unit: { [Model]: UnitState } = {}

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
	}

	state_by_unit[unit_model] = created
	return created
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

local function stamp_last_hit_owner(attacker: Model, target: Model)
	local owner_user_id = attacker:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) ~= "number" then
		return
	end

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
	if dist > ATTACK_RANGE then
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

local function move_unit_smooth(humanoid: Humanoid, s: UnitState, goal: Vector3)
	local t = now()

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

local function maybe_retarget_to_closer(unit_pos: Vector3, s: UnitState, candidates: { Model })
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
	local best = find_closest_to_unit(unit_pos, candidates)
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

	local desired_speed = clamp(
		player_speed * UNIT_SPEED_MULTIPLIER,
		UNIT_SPEED_MIN,
		UNIT_SPEED_MAX
	)

	local slots = compute_formation_slots(player_pos, #alive_units)
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
				move_unit_smooth(u_hum, s, slot)
			end
			continue
		end


		-- Acquire target.
		if not s.target then
			local best = find_closest_to_unit(u_root.Position, candidates)
			if best then
				s.target = best
				s.next_retarget_time = now() + RETARGET_COOLDOWN_SECONDS
			end
		else
			-- Validate target.
			if not is_alive(s.target) then
				s.target = nil
			else
				local t_root = get_root(s.target)
				if t_root then
					local dist_to_target = (t_root.Position - player_pos).Magnitude
					if dist_to_target > TARGET_LEASH_RANGE then
						s.target = nil
					else
						maybe_retarget_to_closer(u_root.Position, s, candidates)
					end
				else
					s.target = nil
				end
			end
		end

		-- Act.
		if s.target then
			local t_root = get_root(s.target)
			if t_root then
				local dist_to_target = (u_root.Position - t_root.Position).Magnitude

				-- If we're already basically in range, stop orbiting and just attack.
				if dist_to_target > (ATTACK_RANGE - 0.25) then
					local approach = compute_attack_approach_goal(
						unit_model,
						i,
						#alive_units,
						t_root.Position
					)
					move_unit_smooth(u_hum, s, approach)
				end

				try_attack(unit_model, s.target, s)
			else
				s.target = nil
			end
		end

		if not s.target then
			local slot = slots[i]
			if slot then
				move_unit_smooth(u_hum, s, slot)
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

	ai_task = task.spawn(function()
		while running do
			clear_dead_unit_state()

			for _, player in ipairs(Players:GetPlayers()) do
				tick_player(player)
			end

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
