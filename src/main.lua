local file = require("pl.file")
local dir = require("pl.dir")
local path = require("pl.path")
---@type LuaFileSystem
local lfs = require("lfs")

local executables = require("executables")

local CURRENT_DIR = path.currentdir()

if not path.exists("combust-config.lua") then error("Config file not found in directory "..CURRENT_DIR) end

---@class Config
---@field entry string
---@field path string[]
---@field cpath string[]
---@field lua { version: string, interpreter: string, compiler: string, runtime: string }
---@field c_compiler string
---@field output_format string
local config = assert(dofile("combust-config.lua"))

---@alias Module { name: string, path: string }

---@type Module[], Module[]
local lua_modules, c_modules = {}, {}

---@param dir string
---@param ext string
---@param list Module[]
---@param base string?
local function recursive_add_files(dir, ext, list, base)
    for file in lfs.dir(dir) do
        if file == "." or file == ".." then goto next end
        local abs_path = path.abspath(path.join(dir, file))
        if path.isfile(abs_path) and path.extension(abs_path) == ext then
            table.insert(list, { name = path.join(base or "", file), path = abs_path })
        elseif path.isdir(abs_path) then
            recursive_add_files(path.join(dir, file), ext, list, path.join(base or "", file))
        end

        ::next::
    end
end

print("Finding lua modules...")
for _, dir in ipairs(config.path) do
    recursive_add_files(dir, ".lua", lua_modules)
end

print("Finding c modules...")
for _, dir in ipairs(config.cpath) do
    recursive_add_files(dir, ".so", c_modules)
end

local build_directories = {
    base    = "build",
    obj     = "build/obj",
    dylib   = "build/dylib",
    bin     = "build/bin",
}

path.rmdir(build_directories.base)

for _, dir in pairs(build_directories) do
    path.mkdir(dir)
end

---@param module Module
---@return Module
local function compile(module)
    local outp, outf = path.join(build_directories.obj,path.dirname(module.name)),
                                 path.join(build_directories.obj, module.name)
    dir.makepath(outp)

    local cmd = string.format("%s -s -o %s %s", config.lua.compiler, outf, module.path)
    print("$ "..cmd)

    os.execute(cmd)

    return { name = module.name, path = outf }
end

---@type Module[], Module[]
local luac_mods, c_mods = {}, {}
print("Compiling Lua modules...")
for _, luafile in ipairs(lua_modules) do
    table.insert(luac_mods, compile(luafile))
end

print("Copying C modules...")
for _, cfile in ipairs(c_modules) do
    local outp, outf = path.join(build_directories.dylib,path.dirname(cfile.name)),
                                 path.join(build_directories.dylib, cfile.name)
    dir.makepath(outp)
    file.copy(cfile.path, outf)
    table.insert(c_mods, { name = cfile.name, path = outf })
end

local entry do
    for _, mod in ipairs(luac_mods) do
        if mod.name == config.entry then
            entry = mod
            break
        end
    end

    if not entry then error("Entry point not found in compiled files") end
end

--Remove duplicate modules
local function remove_duplicates(mods)
    local names = {}
    local new = {}
    for _, mod in ipairs(mods) do
        if not names[mod.name] then
            table.insert(new, mod)
            names[mod.name] = true
        end
    end
    return new
end

luac_mods = remove_duplicates(luac_mods)
c_mods = remove_duplicates(c_mods)

print("Building executable...")
executables[config.output_format](luac_mods, c_mods, build_directories.bin, config)
