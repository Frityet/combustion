-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

---@class Combustion.BuildOptions
---@field lua Lua
---@field c_compiler string?
---@field c_flags string[]
---@field linker string?
---@field build_dir string
---@field bin_dir string
---@field lua_source_dir string
---@field lua_files string[]
---@field lib_dir string?
---@field c_libraries string[]?
---@field resources_dir string?
---@field resources string[]?
---@field frameworks string[]?
---@field verbose boolean
---@field graphical boolean
---@field entry string

local directory = require("pl.dir")
local path = require("pl.path")
local file = require("pl.file")
local utilities = require("utilities")

---@param luac string
---@param src string
---@param dst string
---@return boolean ok, string? err
local function compile_lua(luac, src, dst)
    if luac == "luajit" then
        local ok, err = utilities.programs[luac] "-b"(src)(dst)()
    else
        local ok, err = utilities.programs[luac] "-o"(dst)(src)()
        if not ok then return false, err end
    end

    return true
end

---@param arg Combustion.Options
---@return Combustion.BuildOptions options
local function validate_arguments(arg)
    ---@type Combustion.BuildOptions
    local opts = {}

    local ok, err = directory.makepath(arg.output_dir)
    if not ok then error(err) end
    opts.build_dir = arg.output_dir

    --lua source dir
    opts.lua_source_dir = path.join(opts.build_dir, "lua")
    path.rmdir(opts.lua_source_dir)
    ok, err = directory.makepath(opts.lua_source_dir)
    if not ok then error(err) end

    opts.bin_dir = path.join(opts.build_dir, "bin")
    path.rmdir(opts.bin_dir)
    ok, err = directory.makepath(opts.bin_dir)
    if not ok then error(err) end

    if arg.library_dirs ~= nil then
        opts.lib_dir = path.join(opts.build_dir, "lib")
        path.rmdir(opts.lib_dir)
        ok, err = directory.makepath(opts.lib_dir)
        if not ok then error(err) end
    end

    if arg.resources_dirs ~= nil then
        opts.resources_dir = path.join(opts.build_dir, "resources")
        path.rmdir(opts.resources_dir)
        ok, err = directory.makepath(opts.resources_dir)
        if not ok then error(err) end
    end

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
    end

    if arg.luac == nil or arg.luac == "<lua>" then
        if opts.lua.version == "JIT" then
            opts.lua.compiler = "luajit"
        else
            ok, err = utilities.find_executable("luac"..(opts.lua.version == "Other" and "" or opts.lua.version))
            if not ok then error(err) end
            opts.lua.compiler = ok
        end
    else
        opts.lua.compiler = arg.luac
    end

    if arg.c_compiler == nil then
        warning("No C compiler found, some features may not work")
    else
        opts.c_compiler = arg.c_compiler
    end

    if opts.c_compiler and not arg.linker or arg.linker == "<c-compiler>" then
        opts.linker = arg.c_compiler
    elseif arg.linker then
        opts.linker = arg.linker
    end

    if arg.c_flags then
        opts.c_flags = arg.c_flags
    end


    opts.entry = arg.entry
    opts.verbose = arg.verbose
    opts.graphical = arg.graphical

    return opts
end

---@param arg Combustion.Options
---@return Combustion.BuildOptions
return function (arg)
    local oldprint = print
    local function print(...)
        if arg.verbose then oldprint(...) end
    end

    local opts = validate_arguments(arg)

    --copy lua files by recursively copying the source directory preserving root
    ---@type { [string] : string[] }
    local srcs = {}
    for _, dir in ipairs(arg.source_dirs) do
        --bad hack, but if `dir` doesnt have a trailing slash, add it, depending on the OS
        if dir:sub(-1) ~= path.sep then
            dir = dir..path.sep
        end
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
            if opts.lua.version == "JIT" then
                print("$ "..opts.lua.compiler.." -b "..file.." "..dest)
            else
                print("$ "..opts.lua.compiler.." -o "..dest.." "..file)
            end
            ok = compile_lua(opts.lua.compiler, file, dest)
            if not ok then error("Failed to compile "..file) end
        end
    end

    if arg.library_dirs ~= nil then
        --Do the same, but for C libraries (.so on *nix, .dll on windows)
        local libext do
            if utilities.os == "windows" then
                libext = ".dll"
            else
                libext = ".so" --technically macOS can also take .dylib, but I'm not going to bother with that
            end
        end

        local srcs = {}
        for _, dir in ipairs(arg.library_dirs) do
            if dir:sub(-1) ~= path.sep then
                dir = dir..path.sep
            end
            srcs[dir] = utilities.find(dir, libext)
        end

        print("Copying C libraries...")
        for k, v in pairs(srcs) do
            for _, lib in ipairs(v) do
                local dest = path.join(opts.lib_dir, (path.relpath(lib, k):gsub(k, "")))

                local ok, err = directory.makepath(path.dirname(dest))
                if not ok then error(err) end
                ok = file.copy(lib, dest)
                if not ok then error("Failed to copy "..lib) end
            end
        end
    end

    if arg.resources_dirs ~= nil then
        --Do the same, but for resources
        local srcs = {}
        for _, dir in ipairs(arg.resources_dirs) do
            if dir:sub(-1) ~= path.sep then
                dir = dir..path.sep
            end
            srcs[dir] = utilities.find(dir, "")
        end

        print("Copying resources...")
        for k, v in pairs(srcs) do
            for _, res in ipairs(v) do
                local dest = path.join(opts.resources_dir, (path.relpath(res, k):gsub(k, "")))

                local ok, err = directory.makepath(path.dirname(dest))
                if not ok then error(err) end
                ok = file.copy(res, dest)
                if not ok then error("Failed to copy "..res) end
            end
        end
    end

    return opts
end
