-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/interact.lua
--
-- Захист взаємодії (скрині, печі, інвентар).

local S = minetest.get_translator("lean_protect")

-- Перевірка, чи заборонена ВЗАЄМОДІЯ (не ламання) з блоком
local function is_interaction_protected(pos, pname)
	-- 1. Адміністратори мають повний доступ
	if minetest.check_player_privs(pname, "protection_admin") then
		return false
	end

	-- 2. Перевіряємо, чи є тут взагалі захищена область
	local _, data = lean_protect.get_area_at(pos)
	if not data then
		return false -- Не захищено, взаємодія дозволена
	end

	-- 3. Чи є гравець власником або учасником?
	if lean_protect.is_member(data, pname) then
		return false -- Дозволено
	end

	-- 4. Чужа область. Ігноруємо protection_bypass тут.
	return true
end

local function rotate_and_close(pname, pos)
	local player = minetest.get_player_by_name(pname)
	if player then
		-- ВАЖЛИВО: Викликаємо логування, щоб спрацював on_protection_violation
		if pos then
			minetest.record_protection_violation(pos, pname)
		end
		
		minetest.close_formspec(pname, "")
		
		local yaw = player:get_look_horizontal() + math.pi
		yaw = yaw % (2 * math.pi)
		local pitch = -player:get_look_vertical()

		for i = 1, 5 do
			minetest.after(i * 0.1, function()
				local p = minetest.get_player_by_name(pname)
				if p then
					p:set_look_horizontal(yaw)
					p:set_look_vertical(pitch)
				end
			end)
		end
	end
end

minetest.register_on_mods_loaded(function()
	local wrapped_click = 0
	local wrapped_dig = 0
	local wrapped_inv = 0

	for name, def in pairs(core.registered_nodes) do
		-- 1. Перехоплення on_rightclick (для скринь)
		if def.on_rightclick and not def._lean_protect_click_wrapped then
			local orig = def.on_rightclick
			def.on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
				if clicker and clicker:is_player() then
					local pname = clicker:get_player_name()
					if is_interaction_protected(pos, pname) then
						rotate_and_close(pname, pos)
						return itemstack
					end
				end
				return orig(pos, node, clicker, itemstack, pointed_thing)
			end
			def._lean_protect_click_wrapped = true
			wrapped_click = wrapped_click + 1
		end

		-- 2. Перехоплення ламання (can_dig)
		if def.can_dig and not def._lean_protect_candig_wrapped then
			local orig_can_dig = def.can_dig
			def.can_dig = function(pos, player)
				if player and player:is_player() then
					local pname = player:get_player_name()
					-- Для ламання використовуємо core.is_protected (bypass працює)
					if core.is_protected(pos, pname) then
						-- ДОДАНО: Якщо рушій скасовує ламання тут, 
						-- ми самі фіксуємо порушення, щоб спрацював розворот
						minetest.record_protection_violation(pos, pname)
						return false
					end
				end
				return orig_can_dig(pos, player)
			end
			def._lean_protect_candig_wrapped = true
			wrapped_dig = wrapped_dig + 1
		end

		-- 3. Блокування інвентарю (для печі)
		if def.allow_metadata_inventory_put and not def._lean_protect_inv_wrapped then
			local old_put = def.allow_metadata_inventory_put
			local old_take = def.allow_metadata_inventory_take
			local old_move = def.allow_metadata_inventory_move

			def.allow_metadata_inventory_put = function(pos, listname, index, stack, player)
				if player and player:is_player() then
					local pname = player:get_player_name()
					if is_interaction_protected(pos, pname) then
						rotate_and_close(pname, pos)
						return 0
					end
				end
				return old_put and old_put(pos, listname, index, stack, player) or stack:get_count()
			end

			def.allow_metadata_inventory_take = function(pos, listname, index, stack, player)
				if player and player:is_player() then
					local pname = player:get_player_name()
					if is_interaction_protected(pos, pname) then
						rotate_and_close(pname, pos)
						return 0
					end
				end
				return old_take and old_take(pos, listname, index, stack, player) or stack:get_count()
			end

			def.allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
				if player and player:is_player() then
					local pname = player:get_player_name()
					if is_interaction_protected(pos, pname) then
						rotate_and_close(pname, pos)
						return 0
					end
				end
				return old_move and old_move(pos, from_list, from_index, to_list, to_index, count, player) or count
			end

			def._lean_protect_inv_wrapped = true
			wrapped_inv = wrapped_inv + 1
		end
	end

	minetest.log("action", "[lean_protect] Wrapped: " .. wrapped_click .. 
		" clicks, " .. wrapped_dig .. " digs, " .. wrapped_inv .. " inventories")
end)