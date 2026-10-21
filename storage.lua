-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/storage.lua
-- Persistent storage for area data.

local storage = lean_protect.storage
local areas = lean_protect.areas

-- ============================================================
-- Налаштування
-- ============================================================
local settings = minetest.settings

local SCHEMA_VERSION = 2
local NUM_SHARDS = 16 -- НЕ виносимо в конфіг (зламає існуючі дані)
local SAVE_INTERVAL = tonumber(settings:get("lean_protect_save_interval")) or 2.0

local KEY_NEXT_ID = "next_id"
local KEY_SCHEMA = "schema"
local KEY_LEGACY = "data"

local json_encode = minetest.write_json
local json_decode = minetest.parse_json

-- ============================================================
-- Стан у пам'яті
-- ============================================================

-- shard_cache[n] = { [id] = data, ... } — точне дзеркало того,
-- що лежить на диску в шарді n (у пам'яті ключі — числа).
local shard_cache = {}
for n = 0, NUM_SHARDS - 1 do
	shard_cache[n] = {}
end

-- Які шарди треба скинути на диск
local dirty_shards = {}

-- Чи змінився next_id від останнього запису
local next_id_dirty = false

-- Чи заплановано flush
local save_scheduled = false

-- Лічильник id (ініціалізується з диска)
local next_id_counter = 1

-- ============================================================
-- Хеш шарду
-- ============================================================
local function shard_of(id)
	return id % NUM_SHARDS
end

local function shard_key(n)
	return "data_" .. n
end

-- ============================================================
-- Ініціалізація схеми
-- ============================================================
local function init_schema()
	local schema = storage:get_int(KEY_SCHEMA)
	if schema ~= SCHEMA_VERSION then
		storage:set_int(KEY_SCHEMA, SCHEMA_VERSION)
		minetest.log("action", "[lean_protect] Storage schema v" ..
			schema .. " -> v" .. SCHEMA_VERSION)
	end
end

-- ============================================================
-- Завантаження шарду з диска (у shard_cache)
-- ============================================================
local function load_shard(n)
	local raw = storage:get_string(shard_key(n))
	if raw == "" then return 0 end

	local parsed = json_decode(raw)
	if not parsed then
		minetest.log("error",
			"[lean_protect] Failed to parse shard " .. n)
		return 0
	end

	local count = 0
	for k, v in pairs(parsed) do
		local id = tonumber(k)
		if id and v and v.owner then
			shard_cache[n][id] = v
			areas[id] = v
			count = count + 1
		end
	end
	return count
end

-- ============================================================
-- Завантаження всіх шардів (крок 1)
-- ============================================================
local function load_all()
	local total = 0
	for n = 0, NUM_SHARDS - 1 do
		total = total + load_shard(n)
	end
	minetest.log("action", "[lean_protect] Loaded " .. total ..
		" areas from " .. NUM_SHARDS .. " shards")
	return total
end

-- ============================================================
-- Міграція зі старої схеми (крок 2)
-- ============================================================
local function migrate_legacy()
	local raw = storage:get_string(KEY_LEGACY)
	if raw == "" then return 0 end

	local data = json_decode(raw)
	storage:set_string(KEY_LEGACY, "")

	if not data then
		minetest.log("warning",
			"[lean_protect] Legacy data found but could not be parsed")
		return 0
	end

	local count = 0
	for k, v in pairs(data) do
		local id = tonumber(k)
		if id and v and v.owner then
			local s = shard_of(id)
			shard_cache[s][id] = v
			areas[id] = v
			dirty_shards[s] = true
			count = count + 1
		end
	end

	if count > 0 then
		minetest.log("action", "[lean_protect] Migrated " .. count ..
			" areas from legacy single-key storage to " ..
			NUM_SHARDS .. " shards")
	end
	return count
end

-- ============================================================
-- Завантаження next_id (крок 3, ПІСЛЯ міграції)
-- ============================================================
local function load_next_id()
	local stored = storage:get_int(KEY_NEXT_ID)
	if stored > 0 then
		next_id_counter = stored
		return
	end

	local max_id = 0
	for id in pairs(areas) do
		if id > max_id then max_id = id end
	end
	next_id_counter = max_id + 1
	next_id_dirty = true
end

-- ============================================================
-- Запис одного шарду
--
-- FIX: конвертуємо числові id у рядкові ПЕРЕД серіалізацією.
-- Без цього minetest.write_json робить масив з null-заповненням
-- до максимального id у шарді — це роздуває JSON у 15+ разів
-- при великих id.
-- ============================================================
local function flush_shard(n)
	local shard = shard_cache[n]

	-- Будуємо таблицю з рядковими ключами
	local to_save = {}
	local count = 0
	for id, data in pairs(shard) do
		to_save[tostring(id)] = data
		count = count + 1
	end

	if count == 0 then
		storage:set_string(shard_key(n), "")
	else
		storage:set_string(shard_key(n), json_encode(to_save))
	end

	dirty_shards[n] = nil
end

-- ============================================================
-- Запис усіх забруднених шардів + next_id
-- ============================================================
local function flush_dirty()
	if next(dirty_shards) == nil and not next_id_dirty then
		return
	end

	local t0 = minetest.get_us_time()

	for n in pairs(dirty_shards) do
		flush_shard(n)
	end

	if next_id_dirty then
		storage:set_int(KEY_NEXT_ID, next_id_counter)
		next_id_dirty = false
	end

	local ms = (minetest.get_us_time() - t0) / 1000
	if ms > 20 then
		minetest.log("info", string.format(
			"[lean_protect] Storage flush: %.1f ms", ms))
	end
end

-- ============================================================
-- Планувальник flush (без globalstep)
-- ============================================================
local function schedule_flush()
	if save_scheduled then return end
	save_scheduled = true
	minetest.after(SAVE_INTERVAL, function()
		save_scheduled = false
		flush_dirty()
	end)
end

-- ============================================================
-- Публічне API
-- ============================================================
lean_protect.storage_api = {}

function lean_protect.storage_api.next_id()
	local id = next_id_counter
	next_id_counter = next_id_counter + 1
	next_id_dirty = true
	schedule_flush()
	return id
end

function lean_protect.storage_api.save_area(id, data)
	if not id or not data then return false end

	local s = shard_of(id)
	areas[id] = data
	shard_cache[s][id] = data
	dirty_shards[s] = true
	schedule_flush()
	return true
end

function lean_protect.storage_api.delete_area(id)
	if not id then return false end

	local s = shard_of(id)
	areas[id] = nil
	shard_cache[s][id] = nil
	dirty_shards[s] = true
	schedule_flush()
	return true
end

function lean_protect.storage_api.get_area(id)
	return areas[id]
end

function lean_protect.storage_api.get_all()
	return areas
end

function lean_protect.storage_api.flush()
	flush_dirty()
end

-- ============================================================
-- Примусовий flush при shutdown
-- ============================================================
minetest.register_on_shutdown(function()
	flush_dirty()
	minetest.log("action", "[lean_protect] Storage flushed on shutdown")
end)

-- ============================================================
-- Запуск — правильний порядок
-- ============================================================
init_schema()
load_all()
local migrated = migrate_legacy()
load_next_id()

if migrated > 0 then
	flush_dirty()
	minetest.log("action",
		"[lean_protect] Migration flushed to disk immediately")
end

minetest.log("action", "[lean_protect] Storage ready " ..
	"(shards = " .. NUM_SHARDS ..
	", next_id = " .. next_id_counter .. ")")