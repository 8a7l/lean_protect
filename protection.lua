-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/protection.lua
--
-- Protection hooks for Luanti 5.17+.
-- This file ensures is_protected is a pure query with no side effects.

local S = minetest.get_translator("lean_protect")

local chunks = lean_protect.chunks
local areas = lean_protect.areas
local is_member = lean_protect.is_member
local pos_chunk_hash = lean_protect.pos_chunk_hash

local check_player_privs = minetest.check_player_privs

-- ============================================================
-- Реєстрація привілею protection_bypass
-- ============================================================
minetest.register_privilege("protection_bypass", {
	description = S("Can bypass area protection (moderator tool)"),
	give_to_singleplayer = false,
})

-- ============================================================
-- Обробка порушень (Рушій викликає це сам, рівно 1 раз на подію)
-- ============================================================
local last_msg = {}

minetest.register_on_protection_violation(function(pos, player_name)
	if not player_name then return end

	-- 1. Повідомлення (з throttle)
	local now = minetest.get_gametime()
	if not last_msg[player_name] or now - last_msg[player_name] > 2 then
		last_msg[player_name] = now
		local id, data = lean_protect.get_area_at(pos)
		local owner = data and data.owner or "someone"
		minetest.chat_send_player(player_name, S("Protected by @1", owner))
	end

	-- 2. 3D-розворот (миттєвий + відкладений)
	local player = minetest.get_player_by_name(player_name)
	if player then
		local yaw = player:get_look_horizontal() + math.pi
		yaw = yaw % (2 * math.pi)
		local pitch = -player:get_look_vertical()

		-- Миттєвий розворот
		player:set_look_horizontal(yaw)
		player:set_look_vertical(pitch)

		-- Друга спроба через 0.1с (тепер вона потрібна для всіх!)
		minetest.after(0.1, function()
			local p = minetest.get_player_by_name(player_name)
			if p then
				p:set_look_horizontal(yaw)
				p:set_look_vertical(pitch)
			end
		end)
	end
end)

minetest.register_on_leaveplayer(function(player)
	last_msg[player:get_player_name()] = nil
end)

-- ============================================================
-- Перевизначення core.is_protected (ЧИСТА ФУНКЦІЯ, БЕЗ САЙД-ЕФЕКТІВ)
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
			in_area = true
			break
		end
	end

	if not in_area then
		return delegate(pos, player_name)
	end

	-- Точка в чужій області — перевіряємо bypass БЕЗ кешу.
	if check_player_privs(player_name, "protection_bypass") or
			check_player_privs(player_name, "protection_admin") then
		return delegate(pos, player_name)
	end

	return true
end

minetest.log("action", "[lean_protect] Protection hooks registered " ..
	"(optimized core.is_protected override)")