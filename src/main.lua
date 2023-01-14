local file = require("pl.file")
local dir = require("pl.dir")
local path = require("pl.path")
local pprint = require("pprint")
---@type LuaFileSystem
local lfs = require("lfs")

local CURRENT_DIR = path.currentdir()

if not path.exists("combust-config.lua") then error("Config file not found in directory "..CURRENT_DIR) end

---@class Config
---@field entry string
---@field path string[]
---@field cpath string[]
---@field lua { version: string, interpreter: string, compiler: string, runtime: string }
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
            print(path.join(base or "", file))
            recursive_add_files(path.join(dir, file), ext, list, path.join(base or "", file))
        end

        ::next::
    end
end

for _, dir in ipairs(config.path) do
    recursive_add_files(dir, ".lua", lua_modules)
end

for _, dir in ipairs(config.cpath) do
    recursive_add_files(dir, ".so", c_modules)
end

pprint(lua_modules, c_modules)

local build_directories = {
    base    = "build",
    obj     = "build/obj",
    dylib   = "build/dylib",
    bin     = "build/bin",
}

path.rmdir(build_directories.base)

for _, dir in ipairs(build_directories) do
    path.mkdir(dir)
end

---@param module Module
local function compile(module)
    print("Compiling "..module.name.."...")

    local outp, outf = path.join(build_directories.obj,path.dirname(module.name)),
                                 path.join(build_directories.obj, module.name)
    dir.makepath(outp)

    local cmd = string.format("%s -s -o %s %s", config.lua.compiler, outf, module.path)
    print(cmd)

    os.execute(cmd)
end

for _, luafile in ipairs(lua_modules) do
    compile(luafile)
end
