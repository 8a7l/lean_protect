-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/commands.lua
--
-- Chat commands for the protection mod.

local S = minetest.get_translator("lean_protect")

local selections = lean_protect.selections
local visuals = lean_protect.visuals

local function msg(name, text)
	minetest.chat_send_player(name, text)
end

local function pos_str(pos)
	return minetest.pos_to_string(pos)
end

-- Перевірка імені області
local function validate_name(name)
	if name == "" then
		return false, "Name is empty"
	end
	if #name > 32 then
		return false, "Name is too long (max 32 characters)"
	end
	if name:find("[^%w_%-]") then
		return false, "Name can only contain letters, digits, _ and -"
	end
	return true
end

-- ============================================================
-- /protect <name>
-- ============================================================
minetest.register_chatcommand("protect", {
	params = "<name>",
	description = S("Create a protection area from two selected corners"),
	privs = {interact = true},

	func = function(name, param)
		param = param:trim()
		local ok, err = validate_name(param)
		if not ok then
			return false, S("Usage: /protect <name> (@1)", err)
		end

		local sel = selections[name]
		if not sel or not sel.pos1 or not sel.pos2 then
			return false, S("You must select two corners first " ..
				"(use markers 1 and 2)")
		end

		local id, err2 = lean_protect.create_area(name, param,
			sel.pos1, sel.pos2)

		if not id then
			return false, S("Failed: @1", err2)
		end

		local data = lean_protect.areas[id]

		if sel.wall_positions then
			visuals.clear_selection(sel.wall_positions)
		end
		selections[name] = nil
		lean_protect.tools_forget(name)   -- ДОДАНО: прибрати зі selected_list

		msg(name, S("[OK] Area '@1' created (id @2, volume @3)",
			param, id, data.volume))
		msg(name, S("From @1 to @2",
			pos_str(data.min), pos_str(data.max)))

		local used = lean_protect.get_used_volume(name)
		msg(name, S("Used budget: @1 / @2",
			used, lean_protect.MAX_VOLUME_PER_PLAYER))

		return true
	end,
})

-- ============================================================
-- /protect_list
-- ============================================================
minetest.register_chatcommand("protect_list", {
	description = S("List your protection areas"),
	privs = {interact = true},

	func = function(name)
		local list = lean_protect.get_areas_by_owner(name)

		if #list == 0 then
			return true, S("You have no areas")
		end

		msg(name, S("Your areas (@1):", #list))
		msg(name, S("Used: @1 / @2",
			lean_protect.get_used_volume(name),
			lean_protect.MAX_VOLUME_PER_PLAYER))

		for i = 1, #list do
			local entry = list[i]
			local d = entry.data
			local n_members = 0
			if d.members then
				for _ in pairs(d.members) do n_members = n_members + 1 end
			end
			local members_str = (n_members > 0)
				and (" [shared: " .. n_members .. "]") or ""
			local line = string.format("  [%d] %s%s — %s → %s (%d blocks)",
				entry.id, d.name, members_str,
				pos_str(d.min), pos_str(d.max), d.volume)
			msg(name, line)
		end

		return true
	end,
})

-- ============================================================
-- /protect_remove <name>
-- ============================================================
minetest.register_chatcommand("protect_remove", {
	params = "<name>",
	description = S("Remove one of your protection areas"),

	func = function(name, param)
		param = param:trim()
		if param == "" then
			return false, S("Usage: /protect_remove <name>")
		end

		local id, data = lean_protect.find_by_name(name, param)
		if not id then
			return false, S("Area '@1' not found", param)
		end

		local ok, err = lean_protect.remove_area(id, name)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Area '@1' removed (freed @2 blocks)",
			param, data.volume)
	end,
})

-- ============================================================
-- /protect_info
-- ============================================================
minetest.register_chatcommand("protect_info", {
	description = S("Show your budget and area count"),

	func = function(name)
		local list = lean_protect.get_areas_by_owner(name)
		local used = lean_protect.get_used_volume(name)
		local maxvol = lean_protect.MAX_VOLUME_PER_PLAYER
		local maxareas = lean_protect.MAX_AREAS_PER_PLAYER

		msg(name, S("=== Your protection info ==="))
		msg(name, S("Areas: @1 / @2", #list, maxareas))
		msg(name, S("Budget: @1 / @2 blocks (free @3)",
			used, maxvol, maxvol - used))
		msg(name, S("Minimum area: @1 blocks",
			lean_protect.MIN_VOLUME_PER_AREA))

		return true
	end,
})

-- ============================================================
-- /protect_cancel
-- ============================================================
minetest.register_chatcommand("protect_cancel", {
	description = S("Cancel the current corner selection"),

	func = function(name)
		local sel = selections[name]
		if sel then
			if sel.wall_positions then
				visuals.clear_selection(sel.wall_positions)
			end
			selections[name] = nil
			lean_protect.tools_forget(name)   -- ДОДАНО: прибрати зі selected_list
			return true, S("Selection cleared")
		end
		return true, S("You had no selection")
	end,
})

-- ============================================================
-- /protect_show [name]
-- ============================================================
minetest.register_chatcommand("protect_show", {
	params = "[name]",
	description = S("Highlight an area for 15 seconds (visible to everyone)"),

	func = function(name, param)
		param = param:trim()

		local id, data

		if param == "" then
			local player = minetest.get_player_by_name(name)
			if not player then
				return false, S("Player not found")
			end
			local pos = player:get_pos()
			if not pos then
				return false, S("Cannot get player position")
			end
			local p = {
				x = math.floor(pos.x),
				y = math.floor(pos.y),
				z = math.floor(pos.z),
			}
			id, data = lean_protect.get_area_at(p)
			if not id then
				return false, S("You are not inside any protected area")
			end
		else
			id, data = lean_protect.find_by_name(name, param)
			if not id then
				return false, S("Area '@1' not found", param)
			end
		end

		visuals.box_global(data.min, data.max, 15)

		return true, S("Highlighting '@1' for 15 seconds (all players)",
			data.name)
	end,
})

-- ============================================================
-- /protect_cleanup
-- ============================================================
minetest.register_chatcommand("protect_cleanup", {
	description = S("Remove all leftover protection walls"),
	privs = {server = true},

	func = function(name)
		local n = lean_protect.visuals.cleanup()
		return true, S("Removed @1 leftover wall nodes", n)
	end,
})

-- ============================================================
-- /protect_add <area> <player> — додати учасника
-- ============================================================
minetest.register_chatcommand("protect_add", {
	params = "<area> <player>",
	description = S("Give another player access to your area"),

	func = function(name, param)
		local area_name, target = param:match("^(%S+)%s+(%S+)$")
		if not area_name or not target then
			return false, S("Usage: /protect_add <area> <player>")
		end

		local id = lean_protect.find_by_name(name, area_name)
		if not id then
			return false, S("Area '@1' not found", area_name)
		end

		local ok, err = lean_protect.add_member(id, name, target)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Player '@1' now has access to '@2'",
			target, area_name)
	end,
})

-- ============================================================
-- /protect_remove_member <area> <player>
-- ============================================================
minetest.register_chatcommand("protect_remove_member", {
	params = "<area> <player>",
	description = S("Remove access for a player"),

	func = function(name, param)
		local area_name, target = param:match("^(%S+)%s+(%S+)$")
		if not area_name or not target then
			return false, S("Usage: /protect_remove_member <area> <player>")
		end

		local id = lean_protect.find_by_name(name, area_name)
		if not id then
			return false, S("Area '@1' not found", area_name)
		end

		local ok, err = lean_protect.remove_member(id, name, target)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Player '@1' removed from '@2'",
			target, area_name)
	end,
})

-- ============================================================
-- /protect_members <area>
-- ============================================================
minetest.register_chatcommand("protect_members", {
	params = "<area>",
	description = S("List players with access to your area"),

	func = function(name, param)
		param = param:trim()
		if param == "" then
			return false, S("Usage: /protect_members <area>")
		end

		local id = lean_protect.find_by_name(name, param)
		if not id then
			return false, S("Area '@1' not found", param)
		end

		local members = lean_protect.get_members(id)
		if #members == 0 then
			return true, S("Area '@1' has no shared members", param)
		end

		msg(name, S("Members of '@1' (@2):", param, #members))
		for i = 1, #members do
			msg(name, "  " .. members[i])
		end
		return true
	end,
})

-- ============================================================
-- /protect_rename <old> <new>
-- ============================================================
minetest.register_chatcommand("protect_rename", {
	params = "<old> <new>",
	description = S("Rename one of your areas"),

	func = function(name, param)
		local old_name, new_name = param:match("^(%S+)%s+(%S+)$")
		if not old_name or not new_name then
			return false, S("Usage: /protect_rename <old> <new>")
		end

		local ok, err = validate_name(new_name)
		if not ok then
			return false, S("Invalid new name: @1", err)
		end

		local id = lean_protect.find_by_name(name, old_name)
		if not id then
			return false, S("Area '@1' not found", old_name)
		end

		local ok2, err2 = lean_protect.rename_area(id, name, new_name)
		if not ok2 then
			return false, S("Failed: @1", err2)
		end

		return true, S("[OK] Area '@1' renamed to '@2'",
			old_name, new_name)
	end,
})

-- ============================================================
-- /protect_transfer <area> <player>
-- ============================================================
minetest.register_chatcommand("protect_transfer", {
	params = "<area> <player>",
	description = S("Transfer ownership of your area to another player"),

	func = function(name, param)
		local area_name, target = param:match("^(%S+)%s+(%S+)$")
		if not area_name or not target then
			return false, S("Usage: /protect_transfer <area> <player>")
		end

		local id = lean_protect.find_by_name(name, area_name)
		if not id then
			return false, S("Area '@1' not found", area_name)
		end

		local ok, err = lean_protect.transfer_area(id, name, target)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Area '@1' transferred to '@2'",
			area_name, target)
	end,
})

-- ============================================================
-- /protect_help
-- ============================================================
minetest.register_chatcommand("protect_help", {
	description = S("Show protection mod help"),

	func = function(name)
		msg(name, S("=== lean_protect help ==="))
		msg(name, S("Craft two markers: stone + stick (green and red)"))
		msg(name, S("Click marker #1 on one corner, marker #2 on the opposite"))
		msg(name, S("Then: /protect <name> — create the area"))
		msg(name, "")
		msg(name, S("/protect_list — list your areas"))
		msg(name, S("/protect_info — show budget"))
		msg(name, S("/protect_show [name] — highlight area for 15s"))
		msg(name, S("/protect_remove <name> — delete an area"))
		msg(name, S("/protect_cancel — clear selection"))
		msg(name, "")
		msg(name, S("/protect_add <area> <player> — share access"))
		msg(name, S("/protect_remove_member <area> <player> — revoke access"))
		msg(name, S("/protect_members <area> — list shared members"))
		msg(name, S("/protect_rename <old> <new> — rename area"))
		msg(name, S("/protect_transfer <area> <player> — give ownership"))
		msg(name, "")
		msg(name, S("Limits: @1 areas, @2 blocks total, min @3 blocks per area",
			lean_protect.MAX_AREAS_PER_PLAYER,
			lean_protect.MAX_VOLUME_PER_PLAYER,
			lean_protect.MIN_VOLUME_PER_AREA))

		return true
	end,
})

minetest.log("action", "[lean_protect] Commands registered")