-- lean_protect/indicator.lua
--
-- HUD indicator: shows the area name and owner in the bottom-left corner.

local S = minetest.get_translator("lean_protect")

local get_area_at = lean_protect.get_area_at

local CHECK_INTERVAL = 0.5
local accum = 0

local GOLD = 0xFFD700

local hud_state = {}

local active_list = {}
local active_lookup = {}

-- ============================================================
-- HUD setup
-- ============================================================
local function ensure_hud(player)
	local name = player:get_player_name()
	local st = hud_state[name]
	if st and st.hud_id then return st end

	st = st or {}
	st.hud_id = player:hud_add({
		type          = "text",
		position      = {x = 0, y = 1},
		alignment     = {x = 1, y = -1},
		offset        = {x = 10, y = -10},
		number        = GOLD,
		text          = "",
		scale         = {x = 100, y = 100},
		style         = 0,
	})
	st.last_text = ""
	st.last_pos  = nil
	hud_state[name] = st
	return st
end

local function update_hud(player, text)
	local st = hud_state[player:get_player_name()]
	if not st then return end
	if st.last_text == text then return end
	st.last_text = text
	player:hud_change(st.hud_id, "text", text)
end

-- ============================================================
-- Перевірка
-- ============================================================
local function check_player(player)
	local name = player:get_player_name()
	local st = hud_state[name]
	if not st then return end

	local pos = player:get_pos()
	if not pos then return end

	local px = math.floor(pos.x + 0.5)
	local py = math.floor(pos.y + 0.5)
	local pz = math.floor(pos.z + 0.5)

	local lp = st.last_pos
	if lp and lp[1] == px and lp[2] == py and lp[3] == pz then
		return
	end
	st.last_pos = {px, py, pz}

	local id, data = get_area_at({x = px, y = py, z = pz})
	if not data then
		update_hud(player, "")
		return
	end

	local who
	if data.owner == name then
		who = S("yours")
	elseif data.members and data.members[name] then
		who = S("shared by @1", data.owner)
	else
		who = data.owner
	end

	update_hud(player, data.name .. "  —  " .. who)
end

-- ============================================================
-- Globalstep
-- ============================================================
minetest.register_globalstep(function(dtime)
	if #active_list == 0 then return end
	accum = accum + dtime
	if accum < CHECK_INTERVAL then return end
	accum = 0

	for i = 1, #active_list do
		check_player(active_list[i])
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
	ensure_hud(player)
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()

	if active_lookup[name] then
		active_lookup[name] = nil
		for i = #active_list, 1, -1 do
			if active_list[i] == player then
				table.remove(active_list, i)
				break
			end
		end
	end
	hud_state[name] = nil
end)

minetest.log("action", "[lean_protect] Indicator registered")