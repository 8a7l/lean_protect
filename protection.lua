-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/protection.lua
--
-- Protection hooks for Luanti 5.17+.
--
-- PERFORMANCE (critical): runs on every block interaction.
-- Fast path for positions without any area nearby uses only pure Lua
-- (no C++ calls).
--
-- BYPASS: привілей protection_bypass перевіряється БЕЗ кешу, щоб
-- /grant і /revoke спрацьовували миттєво без рестарту. Кеш довелось
-- прибрати, бо register_on_priv_grant/revoke не є частиною API
-- Luanti 5.17 — колбеки не викликаються. Ціна: один C++ виклик
-- check_player_privs, але лише в SLOW PATH (коли є область).

local S = minetest.get_translator("lean_protect")

local chunks = lean_protect.chunks
local areas = lean_protect.areas
local is_member = lean_protect.is_member
local pos_chunk_hash = lean_protect.pos_chunk_hash

-- Localized for speed
local check_player_privs = minetest.check_player_privs

-- ============================================================
-- Реєстрація привілею protection_bypass
--
-- ЦЕЙ привілей НЕ вбудований у Luanti — його треба реєструвати
-- самостійно, інакше /grant <name> protection_bypass не працює.
-- Реєстрація — один раз при завантаженні моду. Після цього
-- /grant і /revoke працюють миттєво, БЕЗ рестарту.
-- ============================================================
minetest.register_privilege("protection_bypass", {
	description = S("Can bypass area protection (moderator tool)"),
	give_to_singleplayer = false,
})

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

-- Очищення last_msg при виході гравця, щоб таблиця не росла
minetest.register_on_leaveplayer(function(player)
	last_msg[player:get_player_name()] = nil
end)

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
	local key = pos_chunk_hash(pos.x, pos.y, pos.z)
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

	-- Точка в чужій області — перевіряємо bypass БЕЗ кешу.
	-- Додано перевірку protection_admin, щоб адміни мали доступ.
	if check_player_privs(player_name, "protection_bypass") or
			check_player_privs(player_name, "protection_admin") then
		return delegate(pos, player_name)
	end

	notify(player_name, owner)
	minetest.record_protection_violation(pos, player_name)

	-- Розворот із 5 спробами, щоб клієнт точно його застосував
	local player = minetest.get_player_by_name(player_name)
	if player then
		local yaw = player:get_look_horizontal() + math.pi
		yaw = yaw % (2 * math.pi)
		local pitch = -player:get_look_vertical()

		for i = 1, 5 do
			minetest.after(i * 0.1, function()
				local p = minetest.get_player_by_name(player_name)
				if p then
					p:set_look_horizontal(yaw)
					p:set_look_vertical(pitch)
				end
			end)
		end
	end
	
	
	return true
end

minetest.log("action", "[lean_protect] Protection hooks registered " ..
	"(optimized core.is_protected override)")