-- lean_protect/visuals.lua
--
-- Wall highlighting via temporary nodes.
-- Crash-safe: leftover walls are removed on next server start (LBM).

lean_protect.visuals = {}

local WALL_NODE = "lean_protect:wall"
local SEL_WALL  = "lean_protect:sel_wall"
local STORAGE_KEY = "active_walls"

local storage = lean_protect.storage

local active_sessions = {}

local function is_wall(node)
	return minetest.get_item_group(node.name, "temp_wall") > 0
end

-- ============================================================
-- Збереження / читання
-- ============================================================
local function save_active()
	local all = {}
	for _, session in ipairs(active_sessions) do
		for _, p in ipairs(session.positions) do
			all[#all+1] = p
		end
	end
	if #all == 0 then
		storage:set_string(STORAGE_KEY, "")
	else
		storage:set_string(STORAGE_KEY, minetest.write_json(all))
	end
end

local function remove_session(session)
	for i = 1, #session.positions do
		local p = session.positions[i]
		local node = minetest.get_node(p)
		if node.name == WALL_NODE then
			minetest.set_node(p, {name = "air"})
		end
	end
	for i = #active_sessions, 1, -1 do
		if active_sessions[i] == session then
			table.remove(active_sessions, i)
			break
		end
	end
	save_active()
end

-- ============================================================
-- Прибирання залишків після старту
-- ============================================================
local function cleanup_leftovers()
	local removed = 0

	local raw = storage:get_string(STORAGE_KEY)
	if raw and raw ~= "" then
		local positions = minetest.parse_json(raw)
		storage:set_string(STORAGE_KEY, "")
		if type(positions) == "table" then
			for i = 1, #positions do
				local p = positions[i]
				if type(p) == "table" and p.x and p.y and p.z then
					local node = minetest.get_node(p)
					if is_wall(node) then
						minetest.set_node(p, {name = "air"})
						removed = removed + 1
					end
				end
			end
		end
	end

	return removed
end

function lean_protect.visuals.cleanup()
	return cleanup_leftovers()
end

-- ============================================================
-- Збір позицій (4 стіни + підлога + стеля)
-- ============================================================
local function collect_positions(minp, maxp)
	local positions = {}
	local minx, miny, minz = minp.x, minp.y, minp.z
	local maxx, maxy, maxz = maxp.x, maxp.y, maxp.z

	for y = miny, maxy do
		for z = minz, maxz do
			positions[#positions+1] = {x = minx, y = y, z = z}
			if maxx ~= minx then
				positions[#positions+1] = {x = maxx, y = y, z = z}
			end
		end
	end
	for y = miny, maxy do
		for x = minx + 1, maxx - 1 do
			positions[#positions+1] = {x = x, y = y, z = minz}
			if maxz ~= minz then
				positions[#positions+1] = {x = x, y = y, z = maxz}
			end
		end
	end
	for x = minx + 1, maxx - 1 do
		for z = minz + 1, maxz - 1 do
			positions[#positions+1] = {x = x, y = miny, z = z}
		end
	end
	if maxy ~= miny then
		for x = minx + 1, maxx - 1 do
			for z = minz + 1, maxz - 1 do
				positions[#positions+1] = {x = x, y = maxy, z = z}
			end
		end
	end

	return positions
end

function lean_protect.visuals.show_walls(minp, maxp, duration)
	local positions = collect_positions(minp, maxp)
	local placed = {}
	for i = 1, #positions do
		local p = positions[i]
		local node = minetest.get_node(p)
		if node.name == "air" then
			minetest.set_node(p, {name = WALL_NODE})
			placed[#placed+1] = p
		end
	end

	local session = {positions = placed}
	active_sessions[#active_sessions+1] = session
	save_active()

	minetest.after(duration, function()
		remove_session(session)
	end)

	return session
end

function lean_protect.visuals.box_global(minp, maxp, duration)
	return lean_protect.visuals.show_walls(minp, maxp, duration)
end

-- ============================================================
-- Виділення палками
-- ============================================================
function lean_protect.visuals.show_selection(minp, maxp)
	local positions = collect_positions(minp, maxp)
	local placed = {}
	for i = 1, #positions do
		local p = positions[i]
		local node = minetest.get_node(p)
		if node.name == "air" then
			minetest.set_node(p, {name = SEL_WALL})
			placed[#placed+1] = p
		end
	end
	return placed
end

function lean_protect.visuals.clear_selection(positions)
	if not positions then return end
	for i = 1, #positions do
		local p = positions[i]
		local node = minetest.get_node(p)
		if node.name == SEL_WALL then
			minetest.set_node(p, {name = "air"})
		end
	end
end

-- Заглушки для сумісності
function lean_protect.visuals.box_local() end
function lean_protect.visuals.clear() end

-- ============================================================
-- LBM: автоочищення залишків при завантаженні чанка
-- Спрацьовує, коли чанк вперше завантажується з диска.
-- ============================================================

-- Для золотих стін (/protect_show)
minetest.register_lbm({
	name = "lean_protect:clear_leftover_wall",
	nodenames = {WALL_NODE},
	run_at_every_load = true,
	action = function(pos, node)
		local meta = minetest.get_meta(pos)
		local created = meta:get_int("created")
		local now = os.time()
		-- Видаляємо, якщо:
		--   * немає мети (старий запис) → created == 0
		--   * стіна старша за 60 сек (нормальний показ — 15 сек)
		if created == 0 or (now - created) > 60 then
			minetest.set_node(pos, {name = "air"})
		end
	end,
})

-- Для зелених стін (виділення)
minetest.register_lbm({
	name = "lean_protect:clear_leftover_sel_wall",
	nodenames = {SEL_WALL},
	run_at_every_load = true,
	action = function(pos, node)
		local meta = minetest.get_meta(pos)
		local created = meta:get_int("created")
		local now = os.time()
		if created == 0 or (now - created) > 3600 then
			minetest.set_node(pos, {name = "air"})
		end
	end,
})

-- ============================================================
-- Прибирання перед shutdown
-- ============================================================
minetest.register_on_shutdown(function()
	for _, session in ipairs(active_sessions) do
		for i = 1, #session.positions do
			local p = session.positions[i]
			local node = minetest.get_node(p)
			if node.name == WALL_NODE then
				minetest.set_node(p, {name = "air"})
			end
		end
	end
	storage:set_string(STORAGE_KEY, "")
end)

-- ============================================================
-- Запуск
-- ============================================================
minetest.after(1, function()
	local n = cleanup_leftovers()
	if n > 0 then
		minetest.log("action", "[lean_protect] Cleaned up " ..
			n .. " leftover wall nodes")
	end
end)

minetest.log("action", "[lean_protect] Visuals registered")