-- lean_protect/tools.lua
--
-- Marker tools for selecting area corners.
--
-- Visibility rule: the green preview box is shown ONLY when the player
-- holds a marker tool (tool1 or tool2) in the active hand.
-- If the player switches to any other item, the preview hides
-- automatically, but pos1/pos2 stay in memory.

local S = minetest.get_translator("lean_protect")

local selections = lean_protect.selections
local visuals = lean_protect.visuals

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

-- Показати виділення (якщо є обидві точки і ще не показано)
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

-- Приховати виділення (pos1/pos2 залишаються в пам'яті)
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

	show_pos(player, S("Marker @1 set", marker_index), sel[key])

	-- Перебудувати: прибрати старе і показати нове
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
-- ============================================================
local CHECK_INTERVAL = 0.5
local accum = 0

-- Свій список активних гравців
local active_list = {}
local active_lookup = {}

minetest.register_globalstep(function(dtime)
	if #active_list == 0 then return end
	accum = accum + dtime
	if accum < CHECK_INTERVAL then return end
	accum = 0

	for i = 1, #active_list do
		local player = active_list[i]
		local sel = selections[player:get_player_name()]
		if sel then
			if holds_marker(player) then
				show_preview(player, sel)
			else
				hide_preview(sel)
			end
		end
	end
end)

-- ============================================================
-- Lifecycle
-- ============================================================
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	if not active_lookup[name] then
		active_lookup[name] = true
		active_list[#active_list+1] = player
	end
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()

	-- Прибрати виділення (саме блоки)
	local sel = selections[name]
	if sel then
		hide_preview(sel)
	end
	selections[name] = nil

	-- Прибрати зі списку
	if active_lookup[name] then
		active_lookup[name] = nil
		for i = #active_list, 1, -1 do
			if active_list[i] == player then
				table.remove(active_list, i)
				break
			end
		end
	end
end)

minetest.log("action", "[lean_protect] Tools registered")