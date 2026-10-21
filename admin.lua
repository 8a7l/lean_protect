-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/admin.lua
--
-- Admin commands for managing all protected areas on the server.
-- Requires the "protection_admin" privilege.

local S = minetest.get_translator("lean_protect")

-- ============================================================
-- Реєстрація привілею
-- ============================================================
minetest.register_privilege("protection_admin", {
	description = S("Can manage all protection areas on the server"),
	give_to_singleplayer = false,
})

local function msg(name, text)
	minetest.chat_send_player(name, text)
end

local function pos_str(pos)
	return minetest.pos_to_string(pos)
end

-- ============================================================
-- /protect_admin_list <player>
-- ============================================================
minetest.register_chatcommand("protect_admin_list", {
	params = "<player>",
	description = S("List all protection areas owned by a player"),
	privs = {protection_admin = true},

	func = function(name, param)
		param = param:trim()
		if param == "" then
			return false, S("Usage: /protect_admin_list <player>")
		end

		local list = lean_protect.get_areas_by_owner(param)
		if #list == 0 then
			return true, S("Player '@1' has no areas", param)
		end

		msg(name, S("Areas of '@1' (@2):", param, #list))
		msg(name, S("Used budget: @1 / @2",
			lean_protect.get_used_volume(param),
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
			local line = string.format("  [%d] %s%s — %s -> %s (%d blocks)",
				entry.id, d.name, members_str,
				pos_str(d.min), pos_str(d.max), d.volume)
			msg(name, line)
		end

		return true
	end,
})

-- ============================================================
-- /protect_admin_remove <player> <area>
-- ============================================================
minetest.register_chatcommand("protect_admin_remove", {
	params = "<player> <area>",
	description = S("Force-remove an area owned by a player"),
	privs = {protection_admin = true},

	func = function(name, param)
		local owner, area_name = param:match("^(%S+)%s+(%S+)$")
		if not owner or not area_name then
			return false, S("Usage: /protect_admin_remove <player> <area>")
		end

		local id, data = lean_protect.find_by_name(owner, area_name)
		if not id then
			return false, S("Area '@1' of player '@2' not found",
				area_name, owner)
		end

		local ok, err = lean_protect.remove_area(id, name, true)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Removed area '@1' of '@2' (freed @3 blocks)",
			area_name, owner, data.volume)
	end,
})

-- ============================================================
-- /protect_admin_rename <player> <old> <new>
-- ============================================================
minetest.register_chatcommand("protect_admin_rename", {
	params = "<player> <old> <new>",
	description = S("Rename any player's area"),
	privs = {protection_admin = true},

	func = function(name, param)
		local owner, old_name, new_name =
			param:match("^(%S+)%s+(%S+)%s+(%S+)$")
		if not owner or not old_name or not new_name then
			return false, S("Usage: /protect_admin_rename <player> <old> <new>")
		end

		local id = lean_protect.find_by_name(owner, old_name)
		if not id then
			return false, S("Area '@1' of '@2' not found", old_name, owner)
		end

		local ok, err = lean_protect.rename_area(id, name, new_name, true)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Renamed '@1' of '@2' to '@3'",
			old_name, owner, new_name)
	end,
})

-- ============================================================
-- /protect_admin_transfer <player> <area> <new_owner>
-- ============================================================
minetest.register_chatcommand("protect_admin_transfer", {
	params = "<player> <area> <new_owner>",
	description = S("Transfer any player's area to another player"),
	privs = {protection_admin = true},

	func = function(name, param)
		local owner, area_name, new_owner =
			param:match("^(%S+)%s+(%S+)%s+(%S+)$")
		if not owner or not area_name or not new_owner then
			return false, S("Usage: /protect_admin_transfer <player> <area> <new_owner>")
		end

		local id = lean_protect.find_by_name(owner, area_name)
		if not id then
			return false, S("Area '@1' of '@2' not found", area_name, owner)
		end

		local ok, err = lean_protect.transfer_area(id, name, new_owner, true)
		if not ok then
			return false, S("Failed: @1", err)
		end

		return true, S("[OK] Area '@1' transferred from '@2' to '@3'",
			area_name, owner, new_owner)
	end,
})

-- ============================================================
-- /protect_admin_count
-- ============================================================
minetest.register_chatcommand("protect_admin_count", {
	description = S("Show server-wide protection stats"),
	privs = {protection_admin = true},

	func = function(name)
		local total_areas = 0
		local total_owners = 0
		local total_volume = 0

		for _, data in pairs(lean_protect.areas) do
			total_areas = total_areas + 1
			total_volume = total_volume + (data.volume or 0)
		end
		for _ in pairs(lean_protect.by_owner) do
			total_owners = total_owners + 1
		end

		msg(name, S("=== Server protection stats ==="))
		msg(name, S("Areas: @1", total_areas))
		msg(name, S("Owners: @1", total_owners))
		msg(name, S("Total volume: @1 blocks", total_volume))

		return true
	end,
})

minetest.log("action", "[lean_protect] Admin commands registered " ..
	"(privilege: protection_admin)")