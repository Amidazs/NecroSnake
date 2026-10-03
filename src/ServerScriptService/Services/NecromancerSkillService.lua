--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
)
local NecromancerSkills = require(
	ReplicatedStorage:WaitForChild("Shared")
		:WaitForChild("NecromancerSkills")
)

local NecromancerSkillService = {}

local BONE_WALL_LIFETIME = 8
local FEAR_RADIUS = 32
local FEAR_SECONDS = 1.8
local RALLY_SECONDS = 10
local RALLY_DAMAGE_MULTIPLIER = 1.15
local CORPSE_EXPLOSION_RANGE = 22
local CORPSE_EXPLOSION_RADIUS = 17
local CORPSE_EXPLOSION_DAMAGE = 34
local SACRIFICE_HEAL_RATIO = 0.35
local FRENZY_SECONDS = 8
local FRENZY_DAMAGE_MULTIPLIER = 1.28
local FRENZY_HEALTH_COST_RATIO = 0.12

local army_service = nil :: any
local progression_service = nil :: any
local pvp_service = nil :: any
local did_start = false

local cooldowns_by_user_id: {
	[number]: { [string]: number },
} = {}

--[[
	Returns a live HumanoidRootPart from a model.

	Args:
		model (Model): Model to inspect.

	Returns:
		BasePart?: Root when available.
]]
local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	return nil
end

--[[
	Returns the player's living character and root.

	Args:
		player (Player): Player to inspect.

	Returns:
		Model?, BasePart?: Character and root when alive.
]]
local function get_character_root(
	player: Player
): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = get_root(character)
	if not humanoid or humanoid.Health <= 0 or not root then
		return nil, nil
	end
	return character, root
end

--[[
	Returns a living Humanoid from a model.

	Args:
		model (Model): Model to inspect.

	Returns:
		Humanoid?: Living Humanoid.
]]
local function get_living_humanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

--[[
	Checks whether a model may be affected offensively.

	Args:
		player (Player): Casting player.
		model (Model): Potential victim.

	Returns:
		boolean: True when the target is an enemy.
]]
local function can_affect_enemy(
	player: Player,
	model: Model
): boolean
	if model == player.Character then
		return false
	end

	local owner_user_id = model:GetAttribute("ArmyOwnerUserId")
	if typeof(owner_user_id) == "number" then
		if owner_user_id == player.UserId then
			return false
		end
		if pvp_service and pvp_service.can_damage then
			return pvp_service.can_damage(player.UserId, model)
		end
		return true
	end

	local target_player = Players:GetPlayerFromCharacter(model)
	if target_player then
		if target_player == player then
			return false
		end
		if pvp_service and pvp_service.can_damage then
			return pvp_service.can_damage(player.UserId, model)
		end
	end

	return true
end

--[[
	Collects enemy models within a radius.

	Args:
		player (Player): Casting player.
		origin (Vector3): Search origin.
		radius (number): Search radius.

	Returns:
		{ Model }: Unique living enemy models.
]]
local function collect_enemies(
	player: Player,
	origin: Vector3,
	radius: number
): { Model }
	local found: { Model } = {}
	local seen: { [Model]: boolean } = {}

	local function consider(model: Model)
		if seen[model]
			or not get_living_humanoid(model)
			or not can_affect_enemy(player, model)
		then
			return
		end
		local root = get_root(model)
		if not root or (root.Position - origin).Magnitude > radius then
			return
		end
		seen[model] = true
		table.insert(found, model)
	end

	for _, other_player in ipairs(Players:GetPlayers()) do
		if other_player.Character then
			consider(other_player.Character)
		end
	end

	for _, folder_name in ipairs({
		"PlayerArmies",
		"NPCGroups",
		"NPCs",
	}) do
		local folder = Workspace:FindFirstChild(folder_name)
		if folder then
			for _, descendant in ipairs(folder:GetDescendants()) do
				if descendant:IsA("Model") then
					consider(descendant)
				end
			end
		end
	end

	return found
end

--[[
	Returns the remaining cooldown for one skill.

	Args:
		player (Player): Casting player.
		skill_id (string): Skill identifier.

	Returns:
		number: Seconds remaining, or zero when ready.
]]
local function cooldown_remaining(
	player: Player,
	skill_id: string
): number
	local by_skill = cooldowns_by_user_id[player.UserId]
	if not by_skill then
		return 0
	end
	return math.max(
		0,
		(by_skill[skill_id] or 0) - Workspace:GetServerTimeNow()
	)
end

--[[
	Starts a skill cooldown.

	Args:
		player (Player): Casting player.
		skill_id (string): Skill identifier.
		duration (number): Cooldown duration.

	Returns:
		number: Absolute server time when the skill is ready.
]]
local function start_cooldown(
	player: Player,
	skill_id: string,
	duration: number
): number
	local by_skill = cooldowns_by_user_id[player.UserId]
	if not by_skill then
		by_skill = {}
		cooldowns_by_user_id[player.UserId] = by_skill
	end

	local ready_at = Workspace:GetServerTimeNow() + duration
	by_skill[skill_id] = ready_at
	return ready_at
end

--[[
	Sends a skill action result to the client.

	Args:
		player (Player): Recipient.
		ok (boolean): Whether the cast succeeded.
		skill_id (string): Skill identifier.
		message (string): User-facing result.
		ready_at (number?): Optional cooldown end time.

	Returns:
		None.
]]
local function send_result(
	player: Player,
	ok: boolean,
	skill_id: string,
	message: string,
	ready_at: number?
)
	Remotes.skills():FireClient(player, {
		kind = "CAST_RESULT",
		ok = ok,
		skillId = skill_id,
		message = message,
		readyAt = ready_at,
	})
end

--[[
	Casts Bone Wall.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_bone_wall(
	player: Player
): (boolean, string)
	local _, root = get_character_root(player)
	if not root then
		return false, "You cannot cast while dead."
	end

	local direction = root.CFrame.LookVector
	local right = root.CFrame.RightVector
	local center = root.Position + direction * 10

	for index = -2, 2 do
		local wall = Instance.new("Part")
		wall.Name = "NecroBoneWall"
		wall.Anchored = true
		wall.CanCollide = true
		wall.Material = Enum.Material.Slate
		wall.Size = Vector3.new(4, 8, 2)
		wall.CFrame = CFrame.lookAt(
			center + right * (index * 3.7) + Vector3.new(0, 3, 0),
			center + right * (index * 3.7)
				+ Vector3.new(0, 3, 0)
				+ direction
		)
		wall:SetAttribute("SkillOwnerUserId", player.UserId)
		wall.Parent = Workspace
		Debris:AddItem(wall, BONE_WALL_LIFETIME)
	end

	return true, "Bone Wall raised."
end

--[[
	Casts Regroup.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_regroup(
	player: Player
): (boolean, string)
	local _, root = get_character_root(player)
	if not root then
		return false, "You cannot cast while dead."
	end

	local units = army_service.get_army_units(player)
	local moved = 0
	for index, model in ipairs(units) do
		local humanoid = get_living_humanoid(model)
		local unit_root = get_root(model)
		if humanoid and unit_root then
			local angle = ((index - 1) / math.max(1, #units))
				* math.pi * 2
			local radius = 7 + math.floor((index - 1) / 12) * 3
			local offset = Vector3.new(
				math.cos(angle) * radius,
				2,
				math.sin(angle) * radius
			)
			model:PivotTo(CFrame.new(root.Position + offset))
			unit_root.AssemblyLinearVelocity = Vector3.zero
			unit_root.AssemblyAngularVelocity = Vector3.zero
			moved += 1
		end
	end

	return true, ("Regrouped %d undead."):format(moved)
end

--[[
	Casts Fear Pulse.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_fear_pulse(
	player: Player
): (boolean, string)
	local _, root = get_character_root(player)
	if not root then
		return false, "You cannot cast while dead."
	end

	local enemies = collect_enemies(player, root.Position, FEAR_RADIUS)
	local affected = 0
	for _, model in ipairs(enemies) do
		local humanoid = get_living_humanoid(model)
		if humanoid then
			affected += 1
			local old_platform_stand = humanoid.PlatformStand
			humanoid.PlatformStand = true
			model:SetAttribute(
				"FearedUntil",
				Workspace:GetServerTimeNow() + FEAR_SECONDS
			)
			task.delay(FEAR_SECONDS, function()
				if humanoid.Parent and humanoid.Health > 0 then
					humanoid.PlatformStand = old_platform_stand
				end
			end)
		end
	end

	return true, ("Fear Pulse affected %d enemies."):format(affected)
end

--[[
	Casts Rally.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_rally(
	player: Player
): (boolean, string)
	local units = army_service.get_army_units(player)
	local expires_at = Workspace:GetServerTimeNow() + RALLY_SECONDS
	local affected = 0

	for _, model in ipairs(units) do
		if get_living_humanoid(model) then
			model:SetAttribute(
				"SkillDamageMultiplier",
				RALLY_DAMAGE_MULTIPLIER
			)
			model:SetAttribute(
				"SkillDamageMultiplierUntil",
				expires_at
			)
			affected += 1
		end
	end

	return true, ("Rallied %d undead."):format(affected)
end

--[[
	Finds the nearest available corpse.

	Args:
		origin (Vector3): Search origin.

	Returns:
		Model?: Nearest corpse in explosion range.
]]
local function nearest_corpse(origin: Vector3): Model?
	local corpses = Workspace:FindFirstChild("Corpses")
	if not corpses then
		return nil
	end

	local best: Model? = nil
	local best_distance = CORPSE_EXPLOSION_RANGE

	for _, child in ipairs(corpses:GetChildren()) do
		if child:IsA("Model")
			and child:GetAttribute("IsNecroCorpse") == true
		then
			local root = get_root(child)
			if root then
				local distance = (root.Position - origin).Magnitude
				if distance <= best_distance then
					best = child
					best_distance = distance
				end
			end
		end
	end

	return best
end

--[[
	Casts Corpse Explosion.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_corpse_explosion(
	player: Player
): (boolean, string)
	local _, root = get_character_root(player)
	if not root then
		return false, "You cannot cast while dead."
	end

	local corpse = nearest_corpse(root.Position)
	if not corpse then
		return false, "No corpse is close enough to detonate."
	end

	local corpse_root = get_root(corpse)
	if not corpse_root then
		return false, "That corpse cannot be detonated."
	end

	local origin = corpse_root.Position
	corpse:SetAttribute("CorpseCollapsed", true)
	corpse:Destroy()

	local hit = 0
	for _, model in ipairs(
		collect_enemies(player, origin, CORPSE_EXPLOSION_RADIUS)
	) do
		local humanoid = get_living_humanoid(model)
		if humanoid then
			model:SetAttribute("LastDamageSourceKind", "SKILL")
			model:SetAttribute("LastHitOwnerUserId", player.UserId)
			humanoid:TakeDamage(CORPSE_EXPLOSION_DAMAGE)
			hit += 1
		end
	end

	return true, ("Corpse Explosion hit %d enemies."):format(hit)
end

--[[
	Casts Sacrifice.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_sacrifice(
	player: Player
): (boolean, string)
	local character = player.Character
	local humanoid = character
		and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "You cannot cast while dead."
	end

	local units = army_service.get_army_units(player)
	local chosen: Model? = nil
	for _, model in ipairs(units) do
		if get_living_humanoid(model) then
			chosen = model
			break
		end
	end
	if not chosen then
		return false, "You have no undead to Sacrifice."
	end

	local ok = army_service.banish_unit(player, chosen)
	if not ok then
		return false, "The Sacrifice failed."
	end

	local heal = humanoid.MaxHealth * SACRIFICE_HEAL_RATIO
	humanoid.Health = math.min(
		humanoid.MaxHealth,
		humanoid.Health + heal
	)
	return true, "Sacrifice restored your vitality."
end

--[[
	Casts Frenzy.

	Args:
		player (Player): Casting player.

	Returns:
		boolean, string: Success and result message.
]]
local function cast_frenzy(
	player: Player
): (boolean, string)
	local units = army_service.get_army_units(player)
	local expires_at = Workspace:GetServerTimeNow() + FRENZY_SECONDS
	local affected = 0

	for _, model in ipairs(units) do
		local humanoid = get_living_humanoid(model)
		if humanoid then
			local cost = humanoid.MaxHealth
				* FRENZY_HEALTH_COST_RATIO
			humanoid.Health = math.max(1, humanoid.Health - cost)
			model:SetAttribute(
				"SkillDamageMultiplier",
				FRENZY_DAMAGE_MULTIPLIER
			)
			model:SetAttribute(
				"SkillDamageMultiplierUntil",
				expires_at
			)
			affected += 1
		end
	end

	return true, ("Frenzied %d undead."):format(affected)
end

local CASTERS: {
	[string]: (Player) -> (boolean, string),
} = {
	BoneWall = cast_bone_wall,
	Regroup = cast_regroup,
	FearPulse = cast_fear_pulse,
	Rally = cast_rally,
	CorpseExplosion = cast_corpse_explosion,
	Sacrifice = cast_sacrifice,
	Frenzy = cast_frenzy,
}

--[[
	Validates and executes one equipped skill.

	Args:
		player (Player): Casting player.
		skill_id (string): Skill identifier.

	Returns:
		boolean, string, number?: Success, message, cooldown end.
]]
function NecromancerSkillService.cast_skill(
	player: Player,
	skill_id: string
): (boolean, string, number?)
	local definition = NecromancerSkills.get(skill_id)
	local cast = CASTERS[skill_id]
	if not definition or not cast then
		return false, "Unknown Necromancer skill.", nil
	end

	if player:GetAttribute("PvPZone") == "SafeZone" then
		return false, "Combat skills cannot be cast in the Base.", nil
	end

	if not progression_service.is_skill_equipped(
		player,
		skill_id
	) then
		return false, "That skill is not equipped.", nil
	end

	local remaining = cooldown_remaining(player, skill_id)
	if remaining > 0 then
		return false,
			("Skill ready in %.1fs."):format(remaining),
			Workspace:GetServerTimeNow() + remaining
	end

	local ok, message = cast(player)
	if not ok then
		return false, message, nil
	end

	local cooldown_multiplier =
		player:GetAttribute("SkillCooldownMultiplier")
	if typeof(cooldown_multiplier) ~= "number" then
		cooldown_multiplier = 1
	end
	cooldown_multiplier = math.clamp(
		cooldown_multiplier,
		0.5,
		1
	)

	local ready_at = start_cooldown(
		player,
		skill_id,
		definition.cooldown * cooldown_multiplier
	)
	return true, message, ready_at
end

--[[
	Handles skill RemoteEvent requests.

	Args:
		player (Player): Requesting player.
		action (any): Request action.
		payload (any): Request payload.

	Returns:
		None.
]]
local function handle_remote(
	player: Player,
	action: any,
	payload: any
)
	if action ~= "CAST" or typeof(payload) ~= "table" then
		return
	end

	local skill_id = payload.skillId
	if typeof(skill_id) ~= "string" then
		return
	end

	local ok, message, ready_at =
		NecromancerSkillService.cast_skill(
			player,
			skill_id
		)
	send_result(player, ok, skill_id, message, ready_at)
end

--[[
	Initializes skill dependencies.

	Args:
		army_service_ref (any): Army management service.
		progression_service_ref (any): Progression service.
		pvp_service_ref (any): PvP validation service.

	Returns:
		None.
]]
function NecromancerSkillService.init(
	army_service_ref: any,
	progression_service_ref: any,
	pvp_service_ref: any
)
	army_service = army_service_ref
	progression_service = progression_service_ref
	pvp_service = pvp_service_ref
end

--[[
	Starts the skill remote listener.

	Args:
		None.

	Returns:
		None.
]]
function NecromancerSkillService.start()
	if did_start then
		return
	end
	did_start = true

	Remotes.skills().OnServerEvent:Connect(handle_remote)
	Players.PlayerRemoving:Connect(function(player)
		cooldowns_by_user_id[player.UserId] = nil
	end)
end

--[[
	Returns cooldown remaining for Studio acceptance tests.

	Args:
		player (Player): Player to inspect.
		skill_id (string): Skill identifier.

	Returns:
		number: Remaining cooldown seconds.
]]
function NecromancerSkillService.get_cooldown_remaining(
	player: Player,
	skill_id: string
): number
	return cooldown_remaining(player, skill_id)
end

return NecromancerSkillService
