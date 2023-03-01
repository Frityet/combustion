-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

---@class Combustion.BuildOptions
---@field lua Lua
---@field c_compiler string
---@field linker string
---@field build_dir string
---@field lua_source_dir string
---@field lua_files string[]
---@field clib_dir string?
---@field c_libraries string[]?
---@field resources_dir string?
---@field resources string[]?

local directory = require("pl.dir")
local path = require("pl.path")
local file = require("pl.file")
local utilities = require("utilities")

---@param luac string
---@param src string
---@param dst string
---@return boolean ok, string? err
local function compile_lua(luac, src, dst)
    print("Compiling lua file: "..src.." -> "..dst)
    if luac == "luajit" then
        local ok, err = utilities.programs[luac] "-b"(src)(dst)()
    else
        local ok, err = utilities.programs[luac] "-o"(dst)(src)()
        if not ok then return false, err end
    end

    return true
end

---@param arg Combustion.Options
---@return Combustion.BuildOptions? options, string? err
return function (arg)
    ---@type Combustion.BuildOptions
    local opts = {}

    --#region Argument validation

    local ok, err = directory.makepath(arg.output_dir)
    if not ok then error(err) end
    opts.build_dir = arg.output_dir

    --lua source dir
    opts.lua_source_dir = path.join(opts.build_dir, "lua")
    ok, err = directory.makepath(opts.lua_source_dir)
    if not ok then error(err) end

    if arg.lua == nil then
        local lua = utilities.find_lua()
        if lua == nil then error("Could not find lua") end

        opts.lua = lua
    else
        local luaver, err = utilities.verify_lua(arg.lua)
        if not luaver then error(err) end

        opts.lua = {
            interpreter = arg.lua,
            version = luaver
        }

        if arg.luac == nil then
            if opts.lua.version == "jit" then
                opts.lua.compiler = "luajit"
            else
                opts.lua.compiler = "luac"
            end
        else
            opts.lua.compiler = arg.luac
        end
    end

    --#endregion

    --copy lua files by recursively copying the source directory preserving root
    ---@type { [string] : string[] }
    local srcs = {}
    for _, dir in ipairs(arg.sources) do
        srcs[dir] = utilities.find(dir, ".lua")
    end

    print("Compiling lua files with "..opts.lua.compiler.."...")
    for k, v in pairs(srcs) do
        --Compile each file, making sure that the directory structure is preserved
        --for example, `src/main.lua` -. `build/lua/src/main.lua`
        --`src/executables/self-extract.lua` -. `build/lua/src/executables/self-extract.lua`
        for _, file in ipairs(v) do
            local dest = path.join(opts.lua_source_dir, (path.relpath(file, k):gsub(k, "")))

            local ok, err = directory.makepath(path.dirname(dest))
            if not ok then error(err) end
            ok = compile_lua(opts.lua.compiler, file, dest)
            if not ok then error("Failed to compile "..file) end
        end
    end

    --#endregion


    return opts, nil
end
