-- lean_protect/storage.lua
--
-- Persistent storage for area data.
--
-- PERFORMANCE:
--   * Single key with all areas as JSON.
--   * Writes are DEBOUNCED: multiple changes within 2 s = 1 disk write.
--   * Forced save on server shutdown so nothing is lost.
--   * JSON encoding is skipped if no changes are pending.

local storage = lean_protect.storage
local areas = lean_protect.areas

local SCHEMA_VERSION = 1
local KEY_DATA = "data"
local KEY_SCHEMA = "schema"

local SAVE_INTERVAL = 2.0   -- секунди між записами на диск

local json_encode = minetest.write_json
local json_decode = minetest.parse_json

-- Dirty flag + акумулятор
local dirty = false
local accum = 0

-- ============================================================
-- Ініціалізація
-- ============================================================
local function init_storage()
	local schema = storage:get_int(KEY_SCHEMA)
	if schema == 0 then
		storage:set_int(KEY_SCHEMA, SCHEMA_VERSION)
		minetest.log("action", "[lean_protect] Storage initialized " ..
			"(schema v" .. SCHEMA_VERSION .. ")")
	elseif schema ~= SCHEMA_VERSION then
		minetest.log("warning", "[lean_protect] Storage schema v" .. schema ..
			" differs from mod v" .. SCHEMA_VERSION)
	end
end

-- ============================================================
-- Завантаження (один раз при старті)
-- ============================================================
local function load_all()
	local raw = storage:get_string(KEY_DATA)
	if not raw or raw == "" then
		minetest.log("action", "[lean_protect] Loaded 0 areas from storage")
		return 0
	end

	local data = json_decode(raw)
	if not data then
		minetest.log("error", "[lean_protect] Failed to parse storage data")
		return 0
	end

	local count = 0
	for k, v in pairs(data) do
		local id = tonumber(k)
		if id and v and v.owner then
			areas[id] = v
			count = count + 1
		end
	end

	minetest.log("action", "[lean_protect] Loaded " .. count ..
		" areas from storage")
	return count
end

-- ============================================================
-- Запис на диск (викликається рідко)
-- ============================================================
local function write_now()
	if not dirty then return end

	local t0 = minetest.get_us_time()
	local raw = json_encode(areas)
	local encode_ms = (minetest.get_us_time() - t0) / 1000

	storage:set_string(KEY_DATA, raw)
	dirty = false

	-- Логуємо тільки якщо серіалізація повільна (>20 мс)
	if encode_ms > 20 then
		minetest.log("info", "[lean_protect] Storage write: " ..
			#raw .. " bytes, " .. string.format("%.1f", encode_ms) .. " ms")
	end
end

-- ============================================================
-- Публічне API
-- ============================================================
lean_protect.storage_api = {}

-- In-memory counter, no O(n) scan
local next_id_counter = 1

function lean_protect.storage_api.next_id()
	local id = next_id_counter
	next_id_counter = next_id_counter + 1
	return id
end

function lean_protect.storage_api.save_area(id, data)
	if not id or not data then return false end
	areas[id] = data
	dirty = true
	return true
end

function lean_protect.storage_api.delete_area(id)
	if not id then return false end
	areas[id] = nil
	dirty = true
	return true
end

function lean_protect.storage_api.get_area(id)
	return areas[id]
end

function lean_protect.storage_api.get_all()
	return areas
end

-- Примусовий запис (для shutdown)
function lean_protect.storage_api.flush()
	write_now()
end

-- ============================================================
-- Globalstep: debounced write
-- ============================================================
minetest.register_globalstep(function(dtime)
	if not dirty then return end
	accum = accum + dtime
	if accum < SAVE_INTERVAL then return end
	accum = 0
	write_now()
end)

-- Примусовий запис при зупинці сервера
minetest.register_on_shutdown(function()
	write_now()
	minetest.log("action", "[lean_protect] Storage flushed on shutdown")
end)

-- ============================================================
-- Запуск
-- ============================================================
init_storage()
load_all()

-- Ініціалізуємо next_id на основі завантажених даних
do
	local max_id = 0
	for id in pairs(areas) do
		if id > max_id then max_id = id end
	end
	next_id_counter = max_id + 1
end

minetest.log("action", "[lean_protect] Storage ready " ..
	"(next_id = " .. next_id_counter .. ")")