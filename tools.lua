-- lean_protect/tools.lua
--
-- Marker tools for selecting area corners.
--
-- PERFORMANCE (critical):
--   * globalstep проходить лише по гравцях із активним виділенням
--     (selected_list), а не по всіх на сервері.
--   * Якщо гравець не має pos1/pos2 — він взагалі не перевіряється.
--   * Це дає ~500× менше роботи при 1000 гравцях і 2 активних.
--
-- Visibility rule: the green preview box is shown ONLY when the player
-- holds a marker tool (tool1 or tool2) in the active hand.
-- If the player switches to any other item, the preview hides
-- automatically, but pos1/pos2 stay in memory.

local S = minetest.get_translator("lean_protect")

local selections = lean_protect.selections
local visuals = lean_protect.visuals

-- ============================================================
-- Список гравців з активним виділенням
-- ============================================================
local selected_list = {}
local selected_lookup = {}

local function add_to_selected(player, pname)
	if selected_lookup[pname] then return end
	selected_lookup[pname] = true
	selected_list[#selected_list+1] = player
end

local function remove_from_selected(pname)
	if not selected_lookup[pname] then return end
	selected_lookup[pname] = nil
	for i = #selected_list, 1, -1 do
		if selected_list[i]:get_player_name() == pname then
			table.remove(selected_list, i)
			return
		end
	end
end

-- ============================================================
-- Перевірка: чи тримає гравець палку-маркер
-- ============================================================
local function holds_marker(player)
	local name = player:get_wielded_item():get_name()
	return name == "lean_protect:tool1" or name == "lean_protect:tool2"
end

-- ============================================================
-- Допоміжні
-- ============================================================
local function show_pos(player, label, pos)
	minetest.chat_send_player(player:get_player_name(),
		label .. ": " .. minetest.pos_to_string(pos))
end

local function calc_volume(p1, p2)
	local dx = math.abs(p2.x - p1.x) + 1
	local dy = math.abs(p2.y - p1.y) + 1
	local dz = math.abs(p2.z - p1.z) + 1
	return dx * dy * dz
end

local function show_preview(player, sel)
	if sel.wall_positions then return end
	if not (sel.pos1 and sel.pos2) then return end

	local mn = {
		x = math.min(sel.pos1.x, sel.pos2.x),
		y = math.min(sel.pos1.y, sel.pos2.y),
		z = math.min(sel.pos1.z, sel.pos2.z),
	}
	local mx = {
		x = math.max(sel.pos1.x, sel.pos2.x),
		y = math.max(sel.pos1.y, sel.pos2.y),
		z = math.max(sel.pos1.z, sel.pos2.z),
	}

	sel.wall_positions = visuals.show_selection(mn, mx)
end

local function hide_preview(sel)
	if not sel.wall_positions then return end
	visuals.clear_selection(sel.wall_positions)
	sel.wall_positions = nil
end

-- ============================================================
-- on_use: клік палкою
-- ============================================================
local function on_use_tool(player, pos, marker_index, itemstack)
	local pname = player:get_player_name()

	local sel = selections[pname]
	if not sel then
		sel = {}
		selections[pname] = sel
	end

	local key = (marker_index == 1) and "pos1" or "pos2"
	sel[key] = {x = pos.x, y = pos.y, z = pos.z}

	-- Додаємо до selected_list: цей гравець тепер активний
	add_to_selected(player, pname)

	show_pos(player, S("Marker @1 set", marker_index), sel[key])

	hide_preview(sel)
	show_preview(player, sel)

	if sel.pos1 and sel.pos2 then
		local vol = calc_volume(sel.pos1, sel.pos2)
		local maxvol = lean_protect.MAX_VOLUME_PER_PLAYER
		local used = lean_protect.get_used_volume(pname)
		local available = maxvol - used

		minetest.chat_send_player(pname, S("Volume: @1 blocks", vol))
		minetest.chat_send_player(pname,
			S("Budget: @1 / @2 (free @3)", used, maxvol, available))
		minetest.chat_send_player(pname,
			S("Use /protect <name> to create the area"))

		if vol > available then
			minetest.chat_send_player(pname,
				S("[WARNING] This volume exceeds your remaining budget!"))
		end
	end

	return itemstack
end

-- ============================================================
-- Реєстрація інструментів
-- ============================================================
minetest.register_tool("lean_protect:tool1", {
	description = S("Area Marker #1 (first corner)"),
	inventory_image = "default_stick.png^[colorize:#00AA00:120",
	wield_image = "default_stick.png^[colorize:#00AA00:120",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then return itemstack end
		return on_use_tool(user, pointed_thing.under, 1, itemstack)
	end,
})

minetest.register_tool("lean_protect:tool2", {
	description = S("Area Marker #2 (second corner)"),
	inventory_image = "default_stick.png^[colorize:#AA0000:120",
	wield_image = "default_stick.png^[colorize:#AA0000:120",
	stack_max = 1,
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type ~= "node" then return itemstack end
		return on_use_tool(user, pointed_thing.under, 2, itemstack)
	end,
})

minetest.register_craft({
	output = "lean_protect:tool1",
	recipe = {{"default:stick"}, {"default:stone"}},
})
minetest.register_craft({
	output = "lean_protect:tool2",
	recipe = {{"default:stone"}, {"default:stick"}},
})

-- ============================================================
-- Globalstep: показ/приховування залежно від триманого предмета
-- Проходить ЛИШЕ по selected_list.
-- ============================================================
local CHECK_INTERVAL = 0.5
local accum = 0

minetest.register_globalstep(function(dtime)
	if #selected_list == 0 then return end
	accum = accum + dtime
	if accum < CHECK_INTERVAL then return end
	accum = 0

	-- Проходимо з кінця: якщо гравець вийшов зі стану selected
	-- (наприклад, /protect_cancel), видаляємо його зі списку.
	for i = #selected_list, 1, -1 do
		local player = selected_list[i]
		local pname = player:get_player_name()
		local sel = selections[pname]

		if not sel then
			-- Виділення вже немає — прибираємо з selected
			selected_lookup[pname] = nil
			table.remove(selected_list, i)
		else
			if holds_marker(player) then
				show_preview(player, sel)
			else
				hide_preview(sel)
			end
		end
	end
end)

-- ============================================================
-- Публічна функція для commands.lua — забути гравця
-- ============================================================
function lean_protect.tools_forget(pname)
	remove_from_selected(pname)
end

-- ============================================================
-- Lifecycle
-- ============================================================
minetest.register_on_leaveplayer(function(player)
	local pname = player:get_player_name()

	-- Прибрати виділення (саме блоки)
	local sel = selections[pname]
	if sel then
		hide_preview(sel)
	end
	selections[pname] = nil
	remove_from_selected(pname)
end)

minetest.log("action", "[lean_protect] Tools registered (selected_list)")