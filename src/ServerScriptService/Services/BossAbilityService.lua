--!strict

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BossAbilityService = {}

local ATTR_ABILITY_READY = "BossAbilityReadyAt"
local ATTR_BOSS_CLASS = "BossClass"
local ATTR_SIGNATURE = "BossSignatureAbility"
local MAJOR_BOSS_CLASS = "Major"

local GRAVE_BARON_TEMPLATE = "GraveBaron"
local CRYPT_WARDEN_TEMPLATE = "CryptWarden"

local SOUL_NOVA_ID = "SoulNova"
local SOUL_NOVA_RANGE = 17
local SOUL_NOVA_DAMAGE = 42
local SOUL_NOVA_COOLDOWN = 7.5
local SOUL_NOVA_COLOR = Color3.fromRGB(170, 70, 255)

local GRAVE_CHAIN_ID = "GraveChain"
local GRAVE_CHAIN_RANGE = 30
local GRAVE_CHAIN_DAMAGE = 28
local GRAVE_CHAIN_COOLDOWN = 6.5
local GRAVE_CHAIN_SLOW_SECONDS = 2.5
local GRAVE_CHAIN_SPEED_FACTOR = 0.55
local GRAVE_CHAIN_COLOR = Color3.fromRGB(80, 215, 255)

local BOSS_CORPSE_COLOR = Color3.fromRGB(150, 85, 255)
local VFX_LIFETIME_SECONDS = 0.55
export type AbilityContext = {
	source_kind: string,
	owner_user_id: number?,
	faction_id: string?,
}

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function get_template_name(model: Model): string
	local value = model:GetAttribute("TemplateName")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return model.Name
end

local function stamp_damage(
	target: Model,
	context: AbilityContext
)
	target:SetAttribute(
		"LastDamageSourceKind",
		context.source_kind
	)
	target:SetAttribute(
		"LastHitOwnerUserId",
		context.owner_user_id or 0
	)
	if context.faction_id then
		target:SetAttribute(
			"LastHitFactionId",
			context.faction_id
		)
	else
		target:SetAttribute("LastHitFactionId", nil)
	end
	target:SetAttribute("LastHitTime", os.clock())
end

local function compute_damage(
	target: Model,
	raw_damage: number
): number
	local defense = target:GetAttribute("Defense")
	if typeof(defense) ~= "number" then
		defense = 0
	end
	defense = math.clamp(defense, 0, 0.9)
	return math.max(
		1,
		math.floor(raw_damage * (1 - defense) + 0.5)
	)
end
local function make_ring(
	position: Vector3,
	start_size: number,
	end_size: number,
	color: Color3
)
	local ring = Instance.new("Part")
	ring.Name = "BossAbilityPulse"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	ring.Size = Vector3.new(
		0.3,
		start_size,
		start_size
	)
	ring.CFrame = CFrame.new(position)
		* CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = Workspace

	local tween = TweenService:Create(
		ring,
		TweenInfo.new(VFX_LIFETIME_SECONDS),
		{
			Size = Vector3.new(0.3, end_size, end_size),
			Transparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(
		ring,
		VFX_LIFETIME_SECONDS + 0.1
	)
end

local function apply_slow(target: Model)
	local humanoid = get_humanoid(target)
	if not humanoid then
		return
	end

	local original_speed = humanoid.WalkSpeed
	local token = Workspace:GetServerTimeNow()
	target:SetAttribute("BossSlowToken", token)
	humanoid.WalkSpeed = math.max(
		4,
		original_speed * GRAVE_CHAIN_SPEED_FACTOR
	)

	task.delay(GRAVE_CHAIN_SLOW_SECONDS, function()
		if target.Parent == nil then
			return
		end
		if target:GetAttribute("BossSlowToken") ~= token then
			return
		end
		local current = get_humanoid(target)
		if current and current.Health > 0 then
			current.WalkSpeed = original_speed
		end
		target:SetAttribute("BossSlowToken", nil)
	end)
end

local function can_use(
	attacker: Model,
	target: Model,
	range: number
): boolean
	local attacker_root = get_root(attacker)
	local target_root = get_root(target)
	local target_humanoid = get_humanoid(target)
	if not (
		attacker_root
		and target_root
		and target_humanoid
	) then
		return false
	end
	if target_humanoid.Health <= 0 then
		return false
	end
	return (
		attacker_root.Position - target_root.Position
	).Magnitude <= range
end
local function ability_ready(attacker: Model): boolean
	local ready_at = attacker:GetAttribute(
		ATTR_ABILITY_READY
	)
	if typeof(ready_at) ~= "number" then
		return true
	end
	return Workspace:GetServerTimeNow() >= ready_at
end

local function set_cooldown(
	attacker: Model,
	seconds: number
)
	attacker:SetAttribute(
		ATTR_ABILITY_READY,
		Workspace:GetServerTimeNow() + seconds
	)
end

local function use_soul_nova(
	attacker: Model,
	target: Model,
	context: AbilityContext
): boolean
	if not can_use(attacker, target, SOUL_NOVA_RANGE) then
		return false
	end

	local root = get_root(attacker)
	local humanoid = get_humanoid(target)
	if not (root and humanoid) then
		return false
	end

	stamp_damage(target, context)
	humanoid:TakeDamage(
		compute_damage(target, SOUL_NOVA_DAMAGE)
	)
	make_ring(
		root.Position,
		5,
		SOUL_NOVA_RANGE * 2,
		SOUL_NOVA_COLOR
	)
	set_cooldown(attacker, SOUL_NOVA_COOLDOWN)
	attacker:SetAttribute(
		"LastBossAbilityUsed",
		SOUL_NOVA_ID
	)
	return true
end

local function use_grave_chain(
	attacker: Model,
	target: Model,
	context: AbilityContext
): boolean
	if not can_use(
		attacker,
		target,
		GRAVE_CHAIN_RANGE
	) then
		return false
	end

	local target_root = get_root(target)
	local humanoid = get_humanoid(target)
	if not (target_root and humanoid) then
		return false
	end

	stamp_damage(target, context)
	humanoid:TakeDamage(
		compute_damage(target, GRAVE_CHAIN_DAMAGE)
	)
	apply_slow(target)
	make_ring(
		target_root.Position,
		3,
		9,
		GRAVE_CHAIN_COLOR
	)
	set_cooldown(attacker, GRAVE_CHAIN_COOLDOWN)
	attacker:SetAttribute(
		"LastBossAbilityUsed",
		GRAVE_CHAIN_ID
	)
	return true
end

function BossAbilityService.configure_boss(
	model: Model
)
	local template_name = get_template_name(model)
	if template_name == GRAVE_BARON_TEMPLATE then
		model:SetAttribute(
			ATTR_BOSS_CLASS,
			MAJOR_BOSS_CLASS
		)
		model:SetAttribute(
			ATTR_SIGNATURE,
			SOUL_NOVA_ID
		)
		model:SetAttribute(
			"AttackRange",
			SOUL_NOVA_RANGE
		)
		model:SetAttribute("PreferredRange", 10)
	elseif template_name == CRYPT_WARDEN_TEMPLATE then
		model:SetAttribute(
			ATTR_BOSS_CLASS,
			MAJOR_BOSS_CLASS
		)
		model:SetAttribute(
			ATTR_SIGNATURE,
			GRAVE_CHAIN_ID
		)
		model:SetAttribute(
			"AttackRange",
			GRAVE_CHAIN_RANGE
		)
		model:SetAttribute("PreferredRange", 22)
	end
end
function BossAbilityService.is_major_boss(
	model: Model
): boolean
	return model:GetAttribute("IsBoss") == true
		and model:GetAttribute(ATTR_BOSS_CLASS)
			== MAJOR_BOSS_CLASS
end

function BossAbilityService.try_use_signature(
	attacker: Model,
	target: Model,
	context: AbilityContext
): boolean
	if not BossAbilityService.is_major_boss(
		attacker
	) then
		return false
	end
	if not ability_ready(attacker) then
		return false
	end

	local ability_id = attacker:GetAttribute(
		ATTR_SIGNATURE
	)
	if ability_id == SOUL_NOVA_ID then
		return use_soul_nova(
			attacker,
			target,
			context
		)
	end
	if ability_id == GRAVE_CHAIN_ID then
		return use_grave_chain(
			attacker,
			target,
			context
		)
	end
	return false
end

function BossAbilityService.decorate_corpse(
	model: Model,
	root: BasePart
)
	if model:GetAttribute("IsBoss") ~= true then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "BossCorpseLight"
	light.Brightness = 2.2
	light.Color = BOSS_CORPSE_COLOR
	light.Range = 18
	light.Parent = root

	local particles = Instance.new(
		"ParticleEmitter"
	)
	particles.Name = "BossCorpseAura"
	particles.Color = ColorSequence.new(BOSS_CORPSE_COLOR)
	particles.Rate = 14
	particles.Lifetime = NumberRange.new(0.8, 1.4)
	particles.Speed = NumberRange.new(1.5, 3.5)
	particles.SpreadAngle = Vector2.new(
		180,
		180
	)
	particles.Parent = root

	model:SetAttribute("BossCorpse", true)
end

return BossAbilityService
