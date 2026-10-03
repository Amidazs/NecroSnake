--!strict

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BattlefieldLootService = {}

local LOOT_FOLDER_NAME = "BattlefieldLoot"
local LOOT_LIFETIME_SECONDS = 60
local NORMAL_ESSENCE_CHANCE = 0.48
local BOSS_ESSENCE_CHANCE = 1
local NORMAL_SKILLBOOK_CHANCE = 0.05
local BOSS_SKILLBOOK_CHANCE = 0.35
local PICKUP_DISTANCE = 12

local soul_collection_service = nil :: any
local progression_service = nil :: any
local did_start = false

--[[
	Returns the shared battlefield-loot folder.

	Args:
		None.

	Returns:
		Folder: Existing or newly created loot folder.
]]
local function get_loot_folder(): Folder
	local existing = Workspace:FindFirstChild(LOOT_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = LOOT_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

--[[
	Returns a safe world position for a defeated unit.

	Args:
		model (Model): Defeated unit model.

	Returns:
		Vector3: Position used for spawned loot.
]]
local function get_drop_position(model: Model): Vector3
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 2.5, 0)
	end
	return model:GetPivot().Position + Vector3.new(0, 2.5, 0)
end

--[[
	Adds a readable floating label to one loot part.

	Args:
		part (BasePart): Loot part receiving the label.
		text (string): Label text.
		color (Color3): Text colour.

	Returns:
		None.
]]
local function add_label(
	part: BasePart,
	text: string,
	color: Color3
)
	local gui = Instance.new("BillboardGui")
	gui.Name = "LootLabel"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(190, 42)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.BackgroundColor3 = Color3.fromRGB(12, 10, 17)
	label.BackgroundTransparency = 0.18
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
end

--[[
	Creates the common physical loot part and prompt.

	Args:
		name (string): Instance name.
		position (Vector3): World position.
		color (Color3): Part and label accent.
		action_text (string): Prompt action.
		object_text (string): Prompt object text.
		user_id (number): Player allowed to claim the loot.

	Returns:
		Part, ProximityPrompt: Created loot part and prompt.
]]
local function create_loot_part(
	name: string,
	position: Vector3,
	color: Color3,
	action_text: string,
	object_text: string,
	user_id: number
): (Part, ProximityPrompt)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(2.6, 2.6, 2.6)
	part.CFrame = CFrame.new(position)
	part:SetAttribute("LootOwnerUserId", user_id)
	part.Parent = get_loot_folder()

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LootPrompt"
	prompt.ActionText = action_text
	prompt.ObjectText = object_text
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.HoldDuration = 0.15
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	add_label(part, object_text, color)
	Debris:AddItem(part, LOOT_LIFETIME_SECONDS)
	return part, prompt
end

--[[
	Validates whether a player owns one private battlefield drop.

	Args:
		player (Player): Player attempting the pickup.
		part (BasePart): Loot part being claimed.

	Returns:
		boolean: True when the player is the intended owner.
]]
local function can_collect(
	player: Player,
	part: BasePart
): boolean
	local owner = part:GetAttribute("LootOwnerUserId")
	return typeof(owner) == "number"
		and owner == player.UserId
		and part.Parent ~= nil
end

--[[
	Spawns one Soul Essence pickup.

	Args:
		player (Player): Player allowed to collect it.
		position (Vector3): Drop position.
		amount (number): Soul Essence reward.

	Returns:
		BasePart: Created pickup part.
]]
local function spawn_essence(
	player: Player,
	position: Vector3,
	amount: number
): BasePart
	local safe_amount = math.max(1, math.floor(amount))
	local part, prompt = create_loot_part(
		"SoulEssenceDrop",
		position,
		Color3.fromRGB(92, 222, 190),
		"Collect",
		("Soul Essence +%d"):format(safe_amount),
		player.UserId
	)
	part.Shape = Enum.PartType.Ball
	part:SetAttribute("LootKind", "Essence")
	part:SetAttribute("EssenceAmount", safe_amount)

	prompt.Triggered:Connect(function(triggering_player)
		if not can_collect(triggering_player, part) then
			return
		end
		if not soul_collection_service
			or not soul_collection_service.award_essence
		then
			return
		end

		soul_collection_service.award_essence(
			triggering_player,
			safe_amount
		)
		part:Destroy()
	end)
	return part
end

--[[
	Spawns one permanent-skillbook pickup.

	Args:
		player (Player): Player allowed to collect it.
		position (Vector3): Drop position.
		skill_id (string): Skillbook skill identifier.

	Returns:
		BasePart: Created pickup part.
]]
local function spawn_skillbook(
	player: Player,
	position: Vector3,
	skill_id: string
): BasePart
	local part, prompt = create_loot_part(
		"SkillbookDrop",
		position,
		Color3.fromRGB(178, 102, 236),
		"Learn",
		("Skillbook: %s"):format(skill_id),
		player.UserId
	)
	part.Size = Vector3.new(2.8, 0.7, 3.6)
	part:SetAttribute("LootKind", "Skillbook")
	part:SetAttribute("SkillId", skill_id)

	prompt.Triggered:Connect(function(triggering_player)
		if not can_collect(triggering_player, part) then
			return
		end
		if not soul_collection_service
			or not soul_collection_service.learn_skillbook
		then
			return
		end

		local ok = soul_collection_service.learn_skillbook(
			triggering_player,
			skill_id
		)
		if not ok then
			return
		end

		if progression_service
			and progression_service.push_snapshot
		then
			progression_service.push_snapshot(triggering_player)
		end
		part:Destroy()
	end)
	return part
end

--[[
	Chooses one not-yet-learned advanced skillbook.

	Args:
		player (Player): Player receiving the possible drop.

	Returns:
		string?: Skill identifier, or nil when none remain.
]]
local function choose_missing_skillbook(player: Player): string?
	if not soul_collection_service
		or not soul_collection_service.get_missing_skillbook_ids
	then
		return nil
	end

	local missing =
		soul_collection_service.get_missing_skillbook_ids(player)
	if #missing == 0 then
		return nil
	end
	return missing[math.random(1, #missing)]
end

--[[
	Rolls physical loot for a wild NPC defeated by a player.

	Args:
		model (Model): Defeated NPC model.
		killer (Player): Player credited with the kill.
		command_cost (number): Unit command-cost weight.

	Returns:
		None.
]]
function BattlefieldLootService.spawn_kill_loot(
	model: Model,
	killer: Player,
	command_cost: number
)
	if not soul_collection_service then
		return
	end

	local position = get_drop_position(model)
	local cost = math.max(1, math.floor(command_cost))
	local is_boss = model:GetAttribute("IsBoss") == true

	local essence_chance = if is_boss
		then BOSS_ESSENCE_CHANCE
		else NORMAL_ESSENCE_CHANCE
	if math.random() <= essence_chance then
		local amount = 2 + cost * 2
		if is_boss then
			amount *= 4
		end
		spawn_essence(killer, position, amount)
	end

	local book_chance = if is_boss
		then BOSS_SKILLBOOK_CHANCE
		else NORMAL_SKILLBOOK_CHANCE
	if math.random() <= book_chance then
		local skill_id = choose_missing_skillbook(killer)
		if skill_id then
			spawn_skillbook(
				killer,
				position + Vector3.new(3.5, 0, 0),
				skill_id
			)
		end
	end
end

--[[
	Initializes battlefield-loot dependencies.

	Args:
		soul_collection_ref (any): Soul profile service.
		progression_ref (any): Necromancer progression service.

	Returns:
		None.
]]
function BattlefieldLootService.init(
	soul_collection_ref: any,
	progression_ref: any
)
	soul_collection_service = soul_collection_ref
	progression_service = progression_ref
end

--[[
	Starts battlefield-loot world state.

	Args:
		None.

	Returns:
		None.
]]
function BattlefieldLootService.start()
	if did_start then
		return
	end
	did_start = true
	get_loot_folder()
end

--[[
	Creates deterministic loot during Studio acceptance.

	Args:
		player (Player): Test player.
		kind (string): "Essence" or "Skillbook".
		skill_id (string?): Optional skill ID for a skillbook.

	Returns:
		BasePart?: Created test drop.
]]
function BattlefieldLootService.debug_spawn(
	player: Player,
	kind: string,
	skill_id: string?
): BasePart?
	if not RunService:IsStudio() then
		return nil
	end

	local root = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end

	local position = root.Position + Vector3.new(4, 1, 0)
	if kind == "Essence" then
		return spawn_essence(player, position, 11)
	end
	if kind == "Skillbook" then
		local selected = skill_id or choose_missing_skillbook(player)
		if selected then
			return spawn_skillbook(player, position, selected)
		end
	end
	return nil
end

return BattlefieldLootService
