-- lean_protect/init.lua
-- Lightweight area protection for Luanti servers.

local S = minetest.get_translator("lean_protect")

lean_protect = {
	storage = nil,
	areas = {},
	chunks = {},
	by_owner = {},
	selections = {},
	used_volume = {},
}

-- mod_storage
lean_protect.storage = minetest.get_mod_storage()
minetest.log("action", "[lean_protect] mod_storage loaded OK " ..
	"(backend: SQLite by default)")

-- Завантаження модулів
local modpath = minetest.get_modpath("lean_protect")

dofile(modpath .. "/storage.lua")
dofile(modpath .. "/api.lua")
dofile(modpath .. "/wall.lua")
dofile(modpath .. "/visuals.lua")
dofile(modpath .. "/tools.lua")
dofile(modpath .. "/commands.lua")
dofile(modpath .. "/admin.lua")
dofile(modpath .. "/protection.lua")
dofile(modpath .. "/interact.lua")   
dofile(modpath .. "/indicator.lua")

minetest.log("action", "[lean_protect] Mod initialized (skeleton)")