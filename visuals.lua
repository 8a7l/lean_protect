-- lean_protect/visuals.lua
--
-- Показ стін через VoxelManip.
--
-- PERFORMANCE (критично):
--   * Одне LVM-записування на всю область замість тисяч set_node.
--   * Ніякого on_construct — LVM не викликає колбеків.
--   * Ніякого persist-стану — активні сесії лише в пам'яті.
--   * Краш-recovery робить LBM у wall.lua.

lean_protect.visuals = {}

local WALL_NODE = "lean_protect:wall"
local SEL_WALL  = "lean_protect:sel_wall"

-- Локалізуємо гарячі C++ виклики
local get_vm         = minetest.get_voxel_manip
local get_content_id = minetest.get_content_id

-- Content ID рахуємо один раз при завантаженні
local c_air      = get_content_id("air")
local c_wall     = get_content_id(WALL_NODE)
local c_sel_wall = get_content_id(SEL_WALL)

-- Активні сесії золотих стін (для /protect_show) — тільки в пам'яті,
-- щоб прибрати при shutdown. Persist не потрібен.
local active_walls = {}

-- ============================================================
-- Збір позицій: 4 бічні стіни (периметр) + підлога + стеля
-- ============================================================
local function collect_positions(minp, maxp)
	local positions = {}
	local minx, miny, minz = minp.x, minp.y, minp.z
	local maxx, maxy, maxz = maxp.x, maxp.y, maxp.z

	-- Стіни X = const (охоплюють усі Y і Z, включаючи кути)
	for y = miny, maxy do
		for z = minz, maxz do
			positions[#positions+1] = {x = minx, y = y, z = z}
			if maxx ~= minx then
				positions[#positions+1] = {x = maxx, y = y, z = z}
			end
		end
	end

	-- Стіни Z = const (без кутів, вони вже додані вище)
	for y = miny, maxy do
		for x = minx + 1, maxx - 1 do
			positions[#positions+1] = {x = x, y = y, z = minz}
			if maxz ~= minz then
				positions[#positions+1] = {x = x, y = y, z = maxz}
			end
		end
	end

	-- Підлога Y = miny (без периметра)
	for x = minx + 1, maxx - 1 do
		for z = minz + 1, maxz - 1 do
			positions[#positions+1] = {x = x, y = miny, z = z}
		end
	end

	-- Стеля Y = maxy (без периметра)
	if maxy ~= miny then
		for x = minx + 1, maxx - 1 do
			for z = minz + 1, maxz - 1 do
				positions[#positions+1] = {x = x, y = maxy, z = z}
			end
		end
	end

	return positions
end

-- ============================================================
-- Bounding box для списку позицій
-- ============================================================
local function bbox_of(positions)
	local p1 = positions[1]
	local minx, miny, minz = p1.x, p1.y, p1.z
	local maxx, maxy, maxz = p1.x, p1.y, p1.z

	for i = 2, #positions do
		local p = positions[i]
		if p.x < minx then minx = p.x end
		if p.y < miny then miny = p.y end
		if p.z < minz then minz = p.z end
		if p.x > maxx then maxx = p.x end
		if p.y > maxy then maxy = p.y end
		if p.z > maxz then maxz = p.z end
	end

	return {x = minx, y = miny, z = minz}, {x = maxx, y = maxy, z = maxz}
end

-- ============================================================
-- Замінити в позиціях ноду `from_cid` на `to_cid` одним LVM-викликом.
-- Повертає список позицій, які РЕАЛЬНО змінилися.
--
-- Чому це швидко:
--   * read_from_map читає блок даних у C++ одним викликом.
--   * data[idx] = new_cid — запис у масиві userdata.
--   * write_to_map пише назад одним викликом і сам оновлює освітлення.
-- ============================================================
local function replace_in_positions(positions, from_cid, to_cid)
	if #positions == 0 then return {} end

	local minp, maxp = bbox_of(positions)

	local vm = get_vm()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()

	local changed = {}
	for i = 1, #positions do
		local p = positions[i]
		local idx = area:index(p.x, p.y, p.z)
		if data[idx] == from_cid then
			data[idx] = to_cid
			changed[#changed+1] = p
		end
	end

	if #changed > 0 then
		vm:set_data(data)
		vm:write_to_map()
	end

	return changed
end

-- ============================================================
-- Показ золотих стін (для /protect_show)
-- ============================================================
function lean_protect.visuals.show_walls(minp, maxp, duration)
	local positions = collect_positions(minp, maxp)
	local placed = replace_in_positions(positions, c_air, c_wall)

	if #placed == 0 then return nil end

	local session = {positions = placed}
	active_walls[#active_walls+1] = session

	-- Прибрати через duration секунд
	minetest.after(duration, function()
		replace_in_positions(session.positions, c_wall, c_air)
		for i = #active_walls, 1, -1 do
			if active_walls[i] == session then
				table.remove(active_walls, i)
				break
			end
		end
	end)

	return session
end

function lean_protect.visuals.box_global(minp, maxp, duration)
	return lean_protect.visuals.show_walls(minp, maxp, duration)
end

-- ============================================================
-- Виділення (зелені стіни) — палички-маркери
-- ============================================================
function lean_protect.visuals.show_selection(minp, maxp)
	local positions = collect_positions(minp, maxp)
	return replace_in_positions(positions, c_air, c_sel_wall)
end

function lean_protect.visuals.clear_selection(positions)
	if not positions or #positions == 0 then return end
	replace_in_positions(positions, c_sel_wall, c_air)
end

-- Заглушки для сумісності з рештою коду
function lean_protect.visuals.box_local() end
function lean_protect.visuals.clear() end

-- ============================================================
-- /protect_cleanup
--
-- Залишки тепер прибирає LBM автоматично при завантаженні чанка,
-- тому ця функція — no-op. Залишена для сумісності з командою.
-- ============================================================
function lean_protect.visuals.cleanup()
	return 0
end

-- ============================================================
-- Прибирання перед shutdown
-- Щоб не залишати залишків на диску при штатному вимкненні.
-- ============================================================
minetest.register_on_shutdown(function()
	if #active_walls == 0 then return end
	for i = 1, #active_walls do
		replace_in_positions(active_walls[i].positions, c_wall, c_air)
	end
	active_walls = {}
end)

minetest.log("action", "[lean_protect] Visuals registered (VoxelManip)")