-- lean_protect/api.lua
--
-- Core logic: create, remove, look up, and check protection.

local areas = lean_protect.areas
local chunks = lean_protect.chunks
local by_owner = lean_protect.by_owner
local used_volume = lean_protect.used_volume

local storage_api = lean_protect.storage_api

-- ============================================================
-- Налаштування
-- ============================================================
local CHUNK_SIZE = 16
local MAX_AREAS_PER_PLAYER = 3
local MAX_VOLUME_PER_PLAYER = 10000
local MIN_VOLUME_PER_AREA = 1000

lean_protect.CHUNK_SIZE = CHUNK_SIZE
lean_protect.MAX_AREAS_PER_PLAYER = MAX_AREAS_PER_PLAYER
lean_protect.MAX_VOLUME_PER_PLAYER = MAX_VOLUME_PER_PLAYER
lean_protect.MIN_VOLUME_PER_AREA = MIN_VOLUME_PER_AREA

local floor = math.floor
local min = math.min
local max = math.max

-- ============================================================
-- Утиліти
-- ============================================================

local function chunk_hash(cx, cy, cz)
	return (cx * 1048576 + cy) * 1048576 + cz
end

local function block_to_chunk(b)
	return floor(b / CHUNK_SIZE)
end

local function pos_key(x, y, z)
	local cx = floor(x / CHUNK_SIZE)
	local cy = floor(y / CHUNK_SIZE)
	local cz = floor(z / CHUNK_SIZE)
	return (cx * 1048576 + cy) * 1048576 + cz
end

local function volume_of(minp, maxp)
	local dx = maxp.x - minp.x + 1
	local dy = maxp.y - minp.y + 1
	local dz = maxp.z - minp.z + 1
	return dx * dy * dz
end

function lean_protect.is_member(data, name)
	if not data or not name then return false end
	if name == data.owner then return true end
	if data.members and data.members[name] then return true end
	return false
end

-- ============================================================
-- Індексація
-- ============================================================
local function index_area(id, data)
	local list = by_owner[data.owner]
	if not list then
		list = {}
		by_owner[data.owner] = list
	end
	list[#list+1] = id

	used_volume[data.owner] = (used_volume[data.owner] or 0) + data.volume

	local cx1 = block_to_chunk(data.min.x)
	local cy1 = block_to_chunk(data.min.y)
	local cz1 = block_to_chunk(data.min.z)
	local cx2 = block_to_chunk(data.max.x)
	local cy2 = block_to_chunk(data.max.y)
	local cz2 = block_to_chunk(data.max.z)

	for cx = cx1, cx2 do
		for cy = cy1, cy2 do
			for cz = cz1, cz2 do
				local key = chunk_hash(cx, cy, cz)
				local lst = chunks[key]
				if not lst then
					lst = {}
					chunks[key] = lst
				end
				lst[#lst+1] = id
			end
		end
	end
end

local function unindex_area(id, data)
	local list = by_owner[data.owner]
	if list then
		for i = #list, 1, -1 do
			if list[i] == id then
				table.remove(list, i)
				break
			end
		end
		if #list == 0 then
			by_owner[data.owner] = nil
		end
	end

	local used = (used_volume[data.owner] or 0) - data.volume
	if used <= 0 then
		used_volume[data.owner] = nil
	else
		used_volume[data.owner] = used
	end

	local cx1 = block_to_chunk(data.min.x)
	local cy1 = block_to_chunk(data.min.y)
	local cz1 = block_to_chunk(data.min.z)
	local cx2 = block_to_chunk(data.max.x)
	local cy2 = block_to_chunk(data.max.y)
	local cz2 = block_to_chunk(data.max.z)

	for cx = cx1, cx2 do
		for cy = cy1, cy2 do
			for cz = cz1, cz2 do
				local key = chunk_hash(cx, cy, cz)
				local lst = chunks[key]
				if lst then
					for i = #lst, 1, -1 do
						if lst[i] == id then
							table.remove(lst, i)
							break
						end
					end
					if #lst == 0 then
						chunks[key] = nil
					end
				end
			end
		end
	end
end

local function index_all()
	local count = 0
	for id, data in pairs(areas) do
		index_area(id, data)
		count = count + 1
	end
	minetest.log("action", "[lean_protect] Indexed " .. count ..
		" areas into chunks")
end

-- ============================================================
-- Перевірки
-- ============================================================
local function check_limits(owner, minp, maxp)
	local vol = volume_of(minp, maxp)

	if vol < MIN_VOLUME_PER_AREA then
		return false, "Area is too small (" .. vol ..
			" blocks, minimum " .. MIN_VOLUME_PER_AREA .. ")"
	end

	local count = #(by_owner[owner] or {})
	if count >= MAX_AREAS_PER_PLAYER then
		return false, "You already have " .. count ..
			" areas (maximum " .. MAX_AREAS_PER_PLAYER .. ")"
	end

	local used = used_volume[owner] or 0
	if used + vol > MAX_VOLUME_PER_PLAYER then
		return false, "Not enough budget: need " .. vol ..
			", have " .. (MAX_VOLUME_PER_PLAYER - used) ..
			" (used " .. used .. " of " .. MAX_VOLUME_PER_PLAYER .. ")"
	end

	return true, vol
end

local function check_overlap(minp, maxp)
	local candidates = {}

	local cx1 = block_to_chunk(minp.x)
	local cy1 = block_to_chunk(minp.y)
	local cz1 = block_to_chunk(minp.z)
	local cx2 = block_to_chunk(maxp.x)
	local cy2 = block_to_chunk(maxp.y)
	local cz2 = block_to_chunk(maxp.z)

	for cx = cx1, cx2 do
		for cy = cy1, cy2 do
			for cz = cz1, cz2 do
				local key = chunk_hash(cx, cy, cz)
				local lst = chunks[key]
				if lst then
					for i = 1, #lst do
						local id = lst[i]
						if not candidates[id] then
							candidates[id] = true

							local data = areas[id]
							if data then
								if not (maxp.x < data.min.x or minp.x > data.max.x or
								        maxp.y < data.min.y or minp.y > data.max.y or
								        maxp.z < data.min.z or minp.z > data.max.z) then
									return false, "Area overlaps with '" ..
										data.name .. "' (id " .. id ..
										", owner " .. data.owner .. ")"
								end
							end
						end
					end
				end
			end
		end
	end

	return true
end

-- ============================================================
-- Створення
-- ============================================================
function lean_protect.create_area(owner, name, pos1, pos2)
	if not owner or not name or not pos1 or not pos2 then
		return nil, "Missing arguments"
	end

	local minp = {
		x = min(pos1.x, pos2.x),
		y = min(pos1.y, pos2.y),
		z = min(pos1.z, pos2.z),
	}
	local maxp = {
		x = max(pos1.x, pos2.x),
		y = max(pos1.y, pos2.y),
		z = max(pos1.z, pos2.z),
	}

	local ok, result = check_limits(owner, minp, maxp)
	if not ok then return nil, result end
	local vol = result

	local ok2, err2 = check_overlap(minp, maxp)
	if not ok2 then return nil, err2 end

	local id = storage_api.next_id()
	local data = {
		owner = owner,
		name = name,
		min = minp,
		max = maxp,
		volume = vol,
		created_at = os.time(),
		members = {},
	}

	storage_api.save_area(id, data)
	index_area(id, data)

	return id
end

-- ============================================================
-- Видалення (admin може передати force = true)
-- ============================================================
function lean_protect.remove_area(id, owner, force)
	local data = areas[id]
	if not data then
		return false, "Area not found"
	end
	if not force and data.owner ~= owner then
		return false, "You are not the owner of this area"
	end
	unindex_area(id, data)
	storage_api.delete_area(id)
	return true
end

-- ============================================================
-- Перейменування (force пропускає перевірки)
-- ============================================================
function lean_protect.rename_area(id, owner, new_name, force)
	local data = areas[id]
	if not data then
		return false, "Area not found"
	end
	if not force and data.owner ~= owner then
		return false, "You are not the owner of this area"
	end

	if not force then
		local list = by_owner[data.owner] or {}
		for i = 1, #list do
			local other_id = list[i]
			if other_id ~= id then
				local other = areas[other_id]
				if other and other.name == new_name then
					return false, "You already have an area named '" ..
						new_name .. "'"
				end
			end
		end
	end

	local old_name = data.name
	data.name = new_name
	storage_api.save_area(id, data)

	return true, old_name
end

-- ============================================================
-- Передача власності (force пропускає перевірки бюджету)
-- ============================================================
function lean_protect.transfer_area(id, owner, new_owner, force)
	local data = areas[id]
	if not data then
		return false, "Area not found"
	end
	if not force and data.owner ~= owner then
		return false, "You are not the owner of this area"
	end
	if not new_owner or new_owner == "" then
		return false, "New owner name is empty"
	end
	if new_owner == data.owner then
		return false, "You already own this area"
	end

	if not force then
		local new_count = #(by_owner[new_owner] or {})
		if new_count >= MAX_AREAS_PER_PLAYER then
			return false, "Player '" .. new_owner ..
				"' already has " .. new_count .. " areas (max " ..
				MAX_AREAS_PER_PLAYER .. ")"
		end

		local new_used = used_volume[new_owner] or 0
		if new_used + data.volume > MAX_VOLUME_PER_PLAYER then
			return false, "Player '" .. new_owner ..
				"' has insufficient budget (needs " .. data.volume ..
				", free " .. (MAX_VOLUME_PER_PLAYER - new_used) .. ")"
		end
	end

	unindex_area(id, data)

	local old_owner = data.owner
	data.owner = new_owner
	data.members = {}

	index_area(id, data)
	storage_api.save_area(id, data)

	return true, old_owner
end

-- ============================================================
-- Учасники
-- ============================================================
function lean_protect.add_member(id, owner, member_name, force)
	local data = areas[id]
	if not data then
		return false, "Area not found"
	end
	if not force and data.owner ~= owner then
		return false, "You are not the owner of this area"
	end
	if not member_name or member_name == "" then
		return false, "Empty player name"
	end
	if member_name == data.owner then
		return false, "Owner is already a member"
	end

	if not data.members then data.members = {} end
	if data.members[member_name] then
		return false, "Player '" .. member_name ..
			"' is already a member"
	end

	data.members[member_name] = true
	storage_api.save_area(id, data)
	return true
end

function lean_protect.remove_member(id, owner, member_name, force)
	local data = areas[id]
	if not data then
		return false, "Area not found"
	end
	if not force and data.owner ~= owner then
		return false, "You are not the owner of this area"
	end
	if not data.members or not data.members[member_name] then
		return false, "Player '" .. member_name ..
			"' is not a member of this area"
	end

	data.members[member_name] = nil
	storage_api.save_area(id, data)
	return true
end

function lean_protect.get_members(id)
	local data = areas[id]
	if not data then return {} end
	local result = {}
	if data.members then
		for name in pairs(data.members) do
			result[#result+1] = name
		end
		table.sort(result)
	end
	return result
end

-- ============================================================
-- Пошук
-- ============================================================
function lean_protect.is_pos_protected(pos, player_name)
	local lst = chunks[pos_key(pos.x, pos.y, pos.z)]
	if not lst then return false end

	for i = 1, #lst do
		local id = lst[i]
		local data = areas[id]
		if data and
			pos.x >= data.min.x and pos.x <= data.max.x and
			pos.y >= data.min.y and pos.y <= data.max.y and
			pos.z >= data.min.z and pos.z <= data.max.z then
			if lean_protect.is_member(data, player_name) then
				return false
			end
			return true, data.owner, id
		end
	end
	return false
end

function lean_protect.get_area_at(pos)
	local lst = chunks[pos_key(pos.x, pos.y, pos.z)]
	if not lst then return nil end

	for i = 1, #lst do
		local id = lst[i]
		local data = areas[id]
		if data and
			pos.x >= data.min.x and pos.x <= data.max.x and
			pos.y >= data.min.y and pos.y <= data.max.y and
			pos.z >= data.min.z and pos.z <= data.max.z then
			return id, data
		end
	end
	return nil
end

function lean_protect.get_areas_by_owner(owner)
	local list = by_owner[owner] or {}
	local result = {}
	for i = 1, #list do
		local id = list[i]
		local data = areas[id]
		if data then
			result[#result+1] = {id = id, data = data}
		end
	end
	return result
end

function lean_protect.find_by_name(owner, name)
	local list = by_owner[owner] or {}
	for i = 1, #list do
		local id = list[i]
		local data = areas[id]
		if data and data.name == name then
			return id, data
		end
	end
	return nil
end

function lean_protect.get_used_volume(owner)
	return used_volume[owner] or 0
end

-- ============================================================
-- Запуск
-- ============================================================
index_all()