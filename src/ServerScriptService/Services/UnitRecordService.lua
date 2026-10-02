--!strict

local HttpService = game:GetService("HttpService")

local UnitRecordService = {}

local ATTR_RECORD_ID = "PersistentUnitId"
local ATTR_EVOLUTION_ID = "EvolutionId"
local ATTR_ABILITY_IDS = "AbilityIdsJson"
local ATTR_SOURCE_MASTER_ID = "SourceMasterId"
local ATTR_DEPLOYED_MASTER_ID = "DeployedMasterId"
local ATTR_ACQUISITION_KIND = "AcquisitionKind"
local ATTR_FACTION_ID = "FactionId"
local ATTR_COMBAT_ROLE = "CombatRole"
local ATTR_FACTION_RARITY = "FactionRarity"

export type UnitRecord = {
	record_id: string,
	template_name: string,
	size_tier: string?,
	trait: string?,
	evolution_id: string?,
	ability_ids: { string },
	source_master_id: string?,
	deployed_master_id: string?,
	acquisition_kind: string?,
	faction_id: string?,
	combat_role: string?,
	faction_rarity: string?,
	command_cost: number?,
}

local function read_string_attribute(
	model: Model,
	name: string
): string?
	local value = model:GetAttribute(name)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function optional_string(value: any): string?
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function copy_string_list(raw: any): { string }
	local result: { string } = {}
	if typeof(raw) ~= "table" then
		return result
	end

	for _, value in ipairs(raw) do
		if typeof(value) == "string" and value ~= "" then
			table.insert(result, value)
		end
	end
	return result
end

local function read_abilities(model: Model): { string }
	local encoded = read_string_attribute(model, ATTR_ABILITY_IDS)
	if not encoded then
		return {}
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not ok then
		return {}
	end
	return copy_string_list(decoded)
end

local function write_optional_attribute(
	model: Model,
	name: string,
	value: string?
)
	if value then
		model:SetAttribute(name, value)
	else
		model:SetAttribute(name, nil)
	end
end

local function copy_record(record: UnitRecord): UnitRecord
	return {
		record_id = record.record_id,
		template_name = record.template_name,
		size_tier = record.size_tier,
		trait = record.trait,
		evolution_id = record.evolution_id,
		ability_ids = copy_string_list(record.ability_ids),
		source_master_id = record.source_master_id,
		deployed_master_id = record.deployed_master_id,
		acquisition_kind = record.acquisition_kind,
		faction_id = record.faction_id,
		combat_role = record.combat_role,
		faction_rarity = record.faction_rarity,
		command_cost = record.command_cost,
	}
end

function UnitRecordService.new_record_id(): string
	return HttpService:GenerateGUID(false)
end

function UnitRecordService.normalize(raw: any): UnitRecord?
	if typeof(raw) ~= "table" then
		return nil
	end

	local template_name = optional_string(raw.template_name)
	if not template_name then
		return nil
	end

	local record_id = optional_string(raw.record_id)
		or UnitRecordService.new_record_id()

	local command_cost = raw.command_cost
	if typeof(command_cost) ~= "number" then
		command_cost = nil
	else
		command_cost = math.max(1, math.floor(command_cost))
	end

	return {
		record_id = record_id,
		template_name = template_name,
		size_tier = optional_string(raw.size_tier),
		trait = optional_string(raw.trait),
		evolution_id = optional_string(raw.evolution_id),
		ability_ids = copy_string_list(raw.ability_ids),
		source_master_id = optional_string(raw.source_master_id),
		deployed_master_id = optional_string(
			raw.deployed_master_id
		),
		acquisition_kind = optional_string(raw.acquisition_kind),
		faction_id = optional_string(raw.faction_id),
		combat_role = optional_string(raw.combat_role),
		faction_rarity = optional_string(raw.faction_rarity),
		command_cost = command_cost,
	}
end

function UnitRecordService.copy(raw: any): UnitRecord?
	local normalized = UnitRecordService.normalize(raw)
	if not normalized then
		return nil
	end
	return copy_record(normalized)
end

function UnitRecordService.from_model(model: Model): UnitRecord
	local template_name = read_string_attribute(
		model,
		"TemplateName"
	) or model.Name

	local command_cost = model:GetAttribute("CommandCost")
	if typeof(command_cost) ~= "number" then
		command_cost = nil
	end

	return {
		record_id = read_string_attribute(
			model,
			ATTR_RECORD_ID
		) or UnitRecordService.new_record_id(),
		template_name = template_name,
		size_tier = read_string_attribute(model, "SizeTier"),
		trait = read_string_attribute(model, "Trait"),
		evolution_id = read_string_attribute(
			model,
			ATTR_EVOLUTION_ID
		),
		ability_ids = read_abilities(model),
		source_master_id = read_string_attribute(
			model,
			ATTR_SOURCE_MASTER_ID
		),
		deployed_master_id = read_string_attribute(
			model,
			ATTR_DEPLOYED_MASTER_ID
		),
		acquisition_kind = read_string_attribute(
			model,
			ATTR_ACQUISITION_KIND
		),
		faction_id = read_string_attribute(
			model,
			ATTR_FACTION_ID
		),
		combat_role = read_string_attribute(
			model,
			ATTR_COMBAT_ROLE
		),
		faction_rarity = read_string_attribute(
			model,
			ATTR_FACTION_RARITY
		),
		command_cost = command_cost,
	}
end

function UnitRecordService.apply_to_model(
	model: Model,
	raw: any
): boolean
	local record = UnitRecordService.normalize(raw)
	if not record then
		return false
	end

	model:SetAttribute(ATTR_RECORD_ID, record.record_id)
	write_optional_attribute(
		model,
		ATTR_EVOLUTION_ID,
		record.evolution_id
	)
	write_optional_attribute(
		model,
		ATTR_SOURCE_MASTER_ID,
		record.source_master_id
	)
	write_optional_attribute(
		model,
		ATTR_DEPLOYED_MASTER_ID,
		record.deployed_master_id
	)
	write_optional_attribute(
		model,
		ATTR_ACQUISITION_KIND,
		record.acquisition_kind
	)
	write_optional_attribute(
		model,
		ATTR_FACTION_ID,
		record.faction_id
	)
	write_optional_attribute(
		model,
		ATTR_COMBAT_ROLE,
		record.combat_role
	)
	write_optional_attribute(
		model,
		ATTR_FACTION_RARITY,
		record.faction_rarity
	)

	local encoded = HttpService:JSONEncode(record.ability_ids)
	model:SetAttribute(ATTR_ABILITY_IDS, encoded)
	if record.command_cost then
		model:SetAttribute("CommandCost", record.command_cost)
	end
	return true
end

function UnitRecordService.stack_key(raw: any): string
	local record = UnitRecordService.normalize(raw)
	if not record then
		return ""
	end

	return table.concat({
		record.template_name,
		record.size_tier or "",
		record.trait or "",
		record.evolution_id or "",
		table.concat(record.ability_ids, ","),
		record.deployed_master_id or "",
		record.faction_id or "",
		record.combat_role or "",
		record.faction_rarity or "",
	}, "|")
end

function UnitRecordService.make_clone(
	master_raw: any
): UnitRecord?
	local master = UnitRecordService.normalize(master_raw)
	if not master then
		return nil
	end

	local clone = copy_record(master)
	clone.record_id = UnitRecordService.new_record_id()
	clone.source_master_id = master.record_id
	clone.deployed_master_id = nil
	clone.acquisition_kind = "Clone"
	return clone
end

function UnitRecordService.make_captured(
	raw: any
): UnitRecord?
	local captured = UnitRecordService.normalize(raw)
	if not captured then
		return nil
	end

	if captured.deployed_master_id
		and not captured.source_master_id
	then
		captured.source_master_id = captured.deployed_master_id
	end

	captured.record_id = UnitRecordService.new_record_id()
	captured.deployed_master_id = nil
	captured.acquisition_kind = "Raised"
	return captured
end

return UnitRecordService
