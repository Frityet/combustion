local inspect = require("inspect")
local mod = require("mod")

print("Hello, World!")

print("arguments:")
for i, v in ipairs(arg) do print(i, v) end


---@type Module[], Module[]
local lua_modules, c_modules = {}, {}

mod.recursive_add_files("lua_modules", ".lua", lua_modules)
mod.recursive_add_files("lua_modules", ".so", c_modules, "lua_modules")

print("Here are all the modules")
for _, v in ipairs(lua_modules) do print(v.name, v.path) end
for _, v in ipairs(c_modules) do print(v.name, v.path) end

print("Here is the paths")

--Split package.path and package.cpath by ;
for i in package.path:gmatch("[^;]+") do print(i) end
for i in package.cpath:gmatch("[^;]+") do print(i) end


