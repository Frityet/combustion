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
---@field c { compiler: string, flags: string[], linker: string, ldflags: string[] }
---@field libzip { include: string, lib: string }
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
        local rel_path = path.join(dir, file)
        local abs_path = path.abspath(rel_path)
        if path.isfile(abs_path) and path.extension(abs_path) == ext then
            print("- \x1b[32mFound\x1b[0m "..rel_path)
            table.insert(list, { name = path.join(base or "", file), path = abs_path })
        elseif path.isdir(abs_path) then
            recursive_add_files(rel_path, ext, list, path.join(base or "", file))
        end

        ::next::
    end
end

print("\x1b[33mFinding lua modules...\x1b[0m")
for _, dir in ipairs(config.path) do
    recursive_add_files(dir, ".lua", lua_modules)
end

print("\x1b[33mFinding native modules...\x1b[0m")
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

    local cmd = config.lua.compiler:gsub("%$%((input)%)", module.path)
    cmd = cmd:gsub("%$%((output)%)", outf)

    os.execute(cmd)

    return { name = module.name, path = outf }
end

---@type Module[], Module[]
local luac_mods, c_mods = {}, {}
print("\x1b[33mCompiling Lua modules...\x1b[0m")
for _, luafile in ipairs(lua_modules) do
    table.insert(luac_mods, compile(luafile))
    print("- \x1b[32mCompiled\x1b[0m "..luafile.name.."")
end

print("\x1b[33mCopying C modules...\x1b[0m")
for _, cfile in ipairs(c_modules) do
    local outp, outf = path.join(build_directories.dylib,path.dirname(cfile.name)),
                                 path.join(build_directories.dylib, cfile.name)
    dir.makepath(outp)
    file.copy(cfile.path, outf)
    table.insert(c_mods, { name = cfile.name, path = outf })
    print("- \x1b[32mCopied\x1b[0m "..cfile.name.."")
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

print("\x1b[33mBuilding executable...\x1b[0m")
print("- \x1b[33mUsing\x1b[0m \x1b[35m"..config.output_format.."\x1b[0m")

local lprint = print
function print(...) return lprint("[\x1b[34m"..config.output_format.." build\x1b[0m]", ...) end
executables[config.output_format](luac_mods, c_mods, build_directories.base, config)
print = lprint
print("\x1b[32mDone\x1b[0m")
