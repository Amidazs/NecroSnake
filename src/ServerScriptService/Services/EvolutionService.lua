--!strict

local EvolutionService = {}

local ATTR_EVOLUTION_ID = "EvolutionId"
local ATTR_APPLIED_EVOLUTION = "AppliedEvolutionId"
local ATTR_RECORD_ID = "PersistentUnitId"
local ATTR_ACQUISITION_KIND = "AcquisitionKind"

local STORMCHARGED_ID = "Stormcharged"
local STORM_COLOR = Color3.fromRGB(95, 205, 255)

type EvolutionDefinition = {
	damage_multiplier: number,
	health_multiplier: number,
	speed_multiplier: number,
	cooldown_multiplier: number,
	defense_bonus: number,
}

local DEFINITIONS: { [string]: EvolutionDefinition } = {
	Stormcharged = {
		damage_multiplier = 1.15,
		health_multiplier = 1.10,
		speed_multiplier = 1.08,
		cooldown_multiplier = 0.92,
		defense_bonus = 0.04,
	},
}
local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function get_root(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return model.PrimaryPart
end

local function multiply_number_attribute(
	model: Model,
	name: string,
	multiplier: number
)
	local value = model:GetAttribute(name)
	if typeof(value) ~= "number" then
		return
	end
	model:SetAttribute(name, value * multiplier)
end

local function add_storm_visuals(model: Model)
	local root = get_root(model)
	if not root then
		return
	end
	if root:FindFirstChild("StormchargedLight") then
		return
	end
	local light = Instance.new("PointLight")
	light.Name = "StormchargedLight"
	light.Color = STORM_COLOR
	light.Brightness = 1.4
	light.Range = 10
	light.Parent = root

	local particles = Instance.new("ParticleEmitter")
	particles.Name = "StormchargedSparks"
	particles.Color = ColorSequence.new(STORM_COLOR)
	particles.LightEmission = 0.8
	particles.Rate = 5
	particles.Lifetime = NumberRange.new(0.18, 0.38)
	particles.Speed = NumberRange.new(1.5, 3.5)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Parent = root
end

local function apply_definition(
	model: Model,
	evolution_id: string,
	definition: EvolutionDefinition
)
	if model:GetAttribute(ATTR_APPLIED_EVOLUTION) == evolution_id then
		return
	end

	local humanoid = get_humanoid(model)
	if humanoid then
		local old_max = math.max(1, humanoid.MaxHealth)
		local ratio = math.clamp(humanoid.Health / old_max, 0, 1)
		humanoid.MaxHealth = math.max(
			1,
			math.floor(old_max * definition.health_multiplier + 0.5)
		)
		humanoid.Health = humanoid.MaxHealth * ratio
		humanoid.WalkSpeed *= definition.speed_multiplier
	end

	multiply_number_attribute(
		model,
		"Damage",
		definition.damage_multiplier
	)
	multiply_number_attribute(
		model,
		"AttackCooldown",
		definition.cooldown_multiplier
	)

	local defense = model:GetAttribute("Defense")
	if typeof(defense) == "number" then
		model:SetAttribute(
			"Defense",
			math.clamp(defense + definition.defense_bonus, 0, 0.9)
		)
	end

	if evolution_id == STORMCHARGED_ID then
		add_storm_visuals(model)
	end

	if not string.find(model.Name, evolution_id, 1, true) then
		model.Name = evolution_id .. " " .. model.Name
	end
	model:SetAttribute(ATTR_APPLIED_EVOLUTION, evolution_id)
end
function EvolutionService.get_definition(
	evolution_id: string
): EvolutionDefinition?
	return DEFINITIONS[evolution_id]
end

function EvolutionService.can_transform(
	model: Model,
	evolution_id: string
): (boolean, string)
	if not DEFINITIONS[evolution_id] then
		return false, "Unknown evolution."
	end
	if model:GetAttribute("IsPlayerArmy") ~= true then
		return false, "Only owned undead can evolve."
	end
	if model:GetAttribute("IsBoss") == true then
		return false, "Major bosses cannot evolve in this event."
	end
	if model:GetAttribute(ATTR_EVOLUTION_ID) ~= nil then
		return false, "This unit has already evolved."
	end
	local record_id = model:GetAttribute(ATTR_RECORD_ID)
	if typeof(record_id) ~= "string" or record_id == "" then
		return false, "Secure or Raise this unit before evolving it."
	end
	if model:GetAttribute(ATTR_ACQUISITION_KIND) == "StarterLoan" then
		return false, "Starter-loan undead cannot evolve."
	end

	local humanoid = get_humanoid(model)
	if not humanoid or humanoid.Health <= 0 then
		return false, "Dead units cannot evolve."
	end
	return true, ""
end
function EvolutionService.apply_model_evolution(model: Model): boolean
	local evolution_id = model:GetAttribute(ATTR_EVOLUTION_ID)
	if typeof(evolution_id) ~= "string" or evolution_id == "" then
		return false
	end

	local definition = DEFINITIONS[evolution_id]
	if not definition then
		return false
	end
	apply_definition(model, evolution_id, definition)
	return true
end

function EvolutionService.transform_model(
	model: Model,
	evolution_id: string
): (boolean, string)
	local allowed, reason = EvolutionService.can_transform(
		model,
		evolution_id
	)
	if not allowed then
		return false, reason
	end

	model:SetAttribute(ATTR_EVOLUTION_ID, evolution_id)
	apply_definition(model, evolution_id, DEFINITIONS[evolution_id])
	return true, evolution_id
end

function EvolutionService.get_stormcharged_id(): string
	return STORMCHARGED_ID
end

return EvolutionService
