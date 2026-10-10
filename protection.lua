-- lean_protect/protection.lua
--
-- Protection hooks for Luanti 5.17+.
--
-- PERFORMANCE (critical): runs on every block interaction.
-- Fast path for positions without any area nearby uses only pure Lua
-- (no C++ calls).

local S = minetest.get_translator("lean_protect")

local chunks = lean_protect.chunks
local areas = lean_protect.areas
local is_member = lean_protect.is_member
local CHUNK_SIZE = lean_protect.CHUNK_SIZE

-- Localized for speed
local floor = math.floor
local check_player_privs = minetest.check_player_privs

-- Bypass cache
local bypass = {}

local function refresh_bypass(player)
	local name = player:get_player_name()
	bypass[name] = check_player_privs(player, "protection_bypass")
end

minetest.register_on_joinplayer(refresh_bypass)

minetest.register_on_priv_grant(function(name, priv)
	if priv == "protection_bypass" then
		bypass[name] = true
	end
end)

minetest.register_on_priv_revoke(function(name, priv)
	if priv == "protection_bypass" then
		bypass[name] = false
	end
end)

minetest.register_on_leaveplayer(function(player)
	bypass[player:get_player_name()] = nil
end)

-- Throttle повідомлень
local last_msg = {}

local function notify(player_name, owner)
	local now = minetest.get_gametime()
	local prev = last_msg[player_name]
	if prev and now - prev < 2 then
		return
	end
	last_msg[player_name] = now
	minetest.chat_send_player(player_name,
		S("Protected by @1", owner or "someone"))
end

-- ============================================================
-- Перевизначення core.is_protected
-- ============================================================
local old_is_protected = core.is_protected

local function delegate(pos, player_name)
	if old_is_protected then
		return old_is_protected(pos, player_name)
	end
	return false
end

core.is_protected = function(pos, player_name)
	if not player_name or player_name == "" then
		return delegate(pos, player_name)
	end

	-- FAST PATH: чи є область у чанку?
	local cx = floor(pos.x / CHUNK_SIZE)
	local cy = floor(pos.y / CHUNK_SIZE)
	local cz = floor(pos.z / CHUNK_SIZE)
	local key = (cx * 1048576 + cy) * 1048576 + cz

	local lst = chunks[key]
	if not lst then
		return delegate(pos, player_name)
	end

	-- SLOW PATH: у чанку є область. Перевіряємо, чи точка належить.
	local owner
	local in_area = false

	for i = 1, #lst do
		local id = lst[i]
		local data = areas[id]
		if data and
			pos.x >= data.min.x and pos.x <= data.max.x and
			pos.y >= data.min.y and pos.y <= data.max.y and
			pos.z >= data.min.z and pos.z <= data.max.z then
			if is_member(data, player_name) then
				return delegate(pos, player_name)
			end
			owner = data.owner
			in_area = true
			break
		end
	end

	if not in_area then
		return delegate(pos, player_name)
	end

	-- Точка в чужій області
	if bypass[player_name] then
		return delegate(pos, player_name)
	end

	if bypass[player_name] == nil then
		local player = minetest.get_player_by_name(player_name)
		if player then
			bypass[player_name] = check_player_privs(player,
				"protection_bypass")
			if bypass[player_name] then
				return delegate(pos, player_name)
			end
		end
	end

	notify(player_name, owner)
	minetest.record_protection_violation(pos, player_name)

	return true
end

minetest.log("action", "[lean_protect] Protection hooks registered " ..
	"(optimized core.is_protected override)")