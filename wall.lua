-- lean_protect/wall.lua

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

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("created", os.time())
	end,
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

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("created", os.time())
	end,
})