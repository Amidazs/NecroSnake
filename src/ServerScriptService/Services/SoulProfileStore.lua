--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local SoulProfileStore = {}

local STORE_NAME = "NecroSnakeSoulCollection_v1"
local SAVE_ATTEMPTS = 3
local RETRY_BASE_SECONDS = 0.5

local store: any = nil
local store_lookup_attempted = false
local studio_fallback: { [number]: any } = {}

local function deep_copy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, item in pairs(value) do
		result[deep_copy(key)] = deep_copy(item)
	end
	return result
end

local function get_store(): any
	if store then
		return store
	end
	if store_lookup_attempted then
		return nil
	end

	store_lookup_attempted = true
	if RunService:IsStudio() and game.PlaceId == 0 then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return store
	end

	if not RunService:IsStudio() then
		warn(
			"[SoulProfileStore] DataStore lookup failed: "
				.. tostring(result)
		)
	end
	return nil
end

local function load_cloud(user_id: number): (boolean, any)
	local active_store = get_store()
	if not active_store then
		return false, nil
	end

	return pcall(function()
		return active_store:GetAsync(tostring(user_id))
	end)
end

local function save_cloud(
	user_id: number,
	snapshot: any,
	expected_revision: number
): (boolean, boolean, any)
	local active_store = get_store()
	if not active_store then
		return false, false, "DataStore unavailable."
	end

	local conflict = false
	local ok, result = pcall(function()
		return active_store:UpdateAsync(
			tostring(user_id),
			function(existing)
				local existing_revision = 0
				if typeof(existing) == "table"
					and typeof(existing.revision) == "number"
				then
					existing_revision = existing.revision
				end

				if existing_revision > expected_revision then
					conflict = true
					return existing
				end
				return snapshot
			end
		)
	end)

	return ok, conflict, result
end

function SoulProfileStore.load(
	user_id: number
): (any?, boolean)
	local cloud_ok, cloud_data = load_cloud(user_id)
	if cloud_ok and typeof(cloud_data) == "table" then
		studio_fallback[user_id] = deep_copy(cloud_data)
		return deep_copy(cloud_data), true
	end

	local fallback = studio_fallback[user_id]
	if fallback then
		return deep_copy(fallback), false
	end

	if not cloud_ok and not RunService:IsStudio() then
		warn(
			("[SoulProfileStore] Load failed for %d: %s"):format(
				user_id,
				tostring(cloud_data)
			)
		)
	end
	return nil, false
end

function SoulProfileStore.save(
	user_id: number,
	raw_snapshot: any,
	expected_revision: number
): (boolean, boolean, number, string?)
	local next_revision = expected_revision + 1
	local snapshot = deep_copy(raw_snapshot)
	snapshot.revision = next_revision

	local last_error = nil
	for attempt = 1, SAVE_ATTEMPTS do
		local ok, conflict, result = save_cloud(
			user_id,
			snapshot,
			expected_revision
		)
		if ok and not conflict then
			studio_fallback[user_id] = deep_copy(snapshot)
			return true, true, next_revision, nil
		end
		if conflict then
			return false, true, expected_revision, "Revision conflict."
		end

		last_error = tostring(result)
		if attempt < SAVE_ATTEMPTS then
			task.wait(RETRY_BASE_SECONDS * (2 ^ (attempt - 1)))
		end
	end

	studio_fallback[user_id] = deep_copy(snapshot)
	if RunService:IsStudio() then
		return true, false, next_revision, last_error
	end
	return false, false, expected_revision, last_error
end

function SoulProfileStore.get_session_copy_for_test(
	user_id: number
): any?
	if not RunService:IsStudio() then
		return nil
	end

	local snapshot = studio_fallback[user_id]
	if not snapshot then
		return nil
	end
	return deep_copy(snapshot)
end

function SoulProfileStore.set_session_copy_for_test(
	user_id: number,
	snapshot: any
): boolean
	if not RunService:IsStudio()
		or typeof(snapshot) ~= "table"
	then
		return false
	end

	studio_fallback[user_id] = deep_copy(snapshot)
	return true
end

return SoulProfileStore
