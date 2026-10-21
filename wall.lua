-- SPDX-License-Identifier: GPL-3.0-only
-- Copyright (C) 2026 8a7l

-- lean_protect/wall.lua
--
-- Тимчасові стіни. Без метаданих — VoxelManip не викликає
-- on_construct, а LBM сам прибирає залишки при завантаженні чанка.
--
-- PERFORMANCE:
--   * Ніяких meta-записів на блок → немає роботи для SQLite.
--   * Один LBM на групу temp_wall замість двох окремих.

-- Золота стіна (для /protect_show)
minetest.register_node("lean_protect:wall", {
	description = "Protection Wall (temp)",
	drawtype = "glasslike_framed_optional",
	tiles = {"default_glass.png^[colorize:#FFD700:200",
	         "default_glass_detail.png^[colorize:#FFD700:200"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	groups = {not_in_creative_inventory = 1, temp_wall = 1},
})

-- Зелена стіна (для виділення палками)
minetest.register_node("lean_protect:sel_wall", {
	description = "Selection Wall (temp)",
	drawtype = "glasslike_framed_optional",
	tiles = {"default_glass.png^[colorize:#00FF00:200",
	         "default_glass_detail.png^[colorize:#00FF00:200"},
	use_texture_alpha = "blend",
	paramtype = "light",
	sunlight_propagates = true,
	walkable = false,
	pointable = false,
	diggable = false,
	buildable_to = true,
	is_ground_content = false,
	drop = "",
	groups = {not_in_creative_inventory = 1, temp_wall = 1},
})

-- ============================================================
-- LBM: прибирає будь-які залишки стін при завантаженні чанка з
-- диска. Це гарантує, що після краша або рестарту залишки зникнуть.
-- У звичайній роботі стіни тримаються в пам'яті — LBM їх не чіпає.
-- ============================================================
minetest.register_lbm({
	name = "lean_protect:clear_leftover_walls",
	nodenames = {"group:temp_wall"},
	run_at_every_load = true,
	action = function(pos, node)
		minetest.remove_node(pos)
	end,
})

minetest.log("action", "[lean_protect] Wall nodes registered")