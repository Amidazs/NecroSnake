--!strict
-- ArmyRegenService
-- Heals player army units over time on the server.
-- Regen rate is controlled by a player attribute so it can be upgraded later.

local Players = game:GetService("Players")

local ArmyRegenService = {}

local army_service = nil :: any
local running = false
local regen_task: thread? = nil

-- How often we apply healing. Smaller = smoother but more CPU.
local TICK_SECONDS = 0.5

-- Stat source (player attribute). Upgrades later just change this attribute.
local PLAYER_REGEN_ATTR = "ArmyRegenPerSecond"

-- Optional: cap regen so it can’t exceed a % of max HP per second.
-- Set to 1.0 for "no cap".
local MAX_FRACTION_OF_MAX_HP_PER_SECOND = 0.10

local function get_humanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function is_alive(humanoid: Humanoid): boolean
	return humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth
end

local function get_player_regen_per_second(player: Player): number
	local value = player:GetAttribute(PLAYER_REGEN_ATTR)
	if typeof(value) ~= "number" then
		return 0
	end
	if value < 0 then
		return 0
	end
	return value
end

local function cap_regen_per_second(regen_per_second: number, max_health: number): number
	if MAX_FRACTION_OF_MAX_HP_PER_SECOND >= 1.0 then
		return regen_per_second
	end

	local cap = max_health * MAX_FRACTION_OF_MAX_HP_PER_SECOND
	if regen_per_second > cap then
		return cap
	end
	return regen_per_second
end

local function heal_model(model: Model, heal_amount: number)
	local humanoid = get_humanoid(model)
	if not humanoid then
		return
	end

	if not is_alive(humanoid) then
		return
	end

	local new_health = humanoid.Health + heal_amount
	if new_health > humanoid.MaxHealth then
		new_health = humanoid.MaxHealth
	end

	humanoid.Health = new_health
end

local function heal_player_army(player: Player, dt: number)
	if not army_service or typeof(army_service.get_army_units) ~= "function" then
		return
	end

	local regen_per_second = get_player_regen_per_second(player)
	if regen_per_second <= 0 then
		return
	end

	local units: { Model } = army_service.get_army_units(player)
	if #units <= 0 then
		return
	end

	for _, unit_model in ipairs(units) do
		if unit_model and unit_model.Parent ~= nil then
			local humanoid = get_humanoid(unit_model)
			if humanoid then
				local capped = cap_regen_per_second(regen_per_second, humanoid.MaxHealth)
				local heal_amount = capped * dt
				if heal_amount > 0 then
					heal_model(unit_model, heal_amount)
				end
			end
		end
	end
end

function ArmyRegenService.init(army_service_module)
	army_service = army_service_module

	-- Default stat. Later your upgrades just change this.
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute(PLAYER_REGEN_ATTR) == nil then
			player:SetAttribute(PLAYER_REGEN_ATTR, 0)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		if player:GetAttribute(PLAYER_REGEN_ATTR) == nil then
			player:SetAttribute(PLAYER_REGEN_ATTR, 0.5)
		end
	end)
end

function ArmyRegenService.start()
	if running then
		return
	end
	running = true

	regen_task = task.spawn(function()
		while running do
			for _, player in ipairs(Players:GetPlayers()) do
				heal_player_army(player, TICK_SECONDS)
			end
			task.wait(TICK_SECONDS)
		end
	end)
end

function ArmyRegenService.stop()
	running = false
	if regen_task then
		task.cancel(regen_task)
		regen_task = nil
	end
end

return ArmyRegenService
