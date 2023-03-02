-- Copyright (c) 2023 Amrit Bhogal
--
-- This software is released under the MIT License.
-- https://opensource.org/licenses/MIT

local export = {}

---@alias Platform "Windows"|"Linux"|"MacOS"|"Other"

---@alias LuaVersion "5.1"|"5.2"|"5.3"|"5.4"|"JIT"|"Other"

---@class Lua
---@field version LuaVersion
---@field interpreter string
---@field compiler string

local stringx = require("pl.stringx")
local path = require("pl.path")
local ffi  = require("ffi")

---@type LuaFileSystem
local lfs = require("lfs")

---@param name string
---@return string? executable, string? err
function export.find_executable(name)
    local platform = ffi.os --[[@as Platform]]
    local path = os.getenv("PATH")
    if not path then return nil, "Could not find PATH environment variable" end
    if platform == "Windows" then
        local paths = stringx.split(path, ";")
        for _, path in ipairs(paths) do
            local file = path.."\\"..name..".exe"
            if lfs.attributes(file, "mode") == "file" then return file
            else return nil, "Could not find executable "..name end
        end
    else
        --Use "which"
        local res, err = export.programs["which"](name)()
        if res then return res
        else return nil, err end
    end

    return nil, "Could not find executable "..name
end

---@alias FunctionArgument (fun(str: string): FunctionArgument) | fun(): string?, string?

---@type { [string] : FunctionArgument }
export.programs = setmetatable({}, {
    __index = function(_, prog)
        local exec = prog
        local function arg(x)
            if x == nil then
                local proc, err = io.popen(exec, "r")
                if not proc then return nil, err end
                local contents = proc:read("*a")
                proc:close()
                contents = stringx.strip(contents)
                return contents
            else
                exec = exec.." "..x
                return arg
            end
        end

        return arg
    end
})

---@return Lua? info, string? err
function export.find_lua()
    ---@type Lua
    local luainfo = {}

    for _, name in ipairs { "", "5.1", "5.2", "5.3", "5.4", "jit" } do
        local lua, err = export.find_executable("lua"..name)
        if lua then
            luainfo.interpreter = lua
            if name == "" then
                local ver = export.programs[luainfo.interpreter] "-v"():match("Lua (%d+%.%d+)")
                if ver and ver == "5.1" or ver == "5.2" or ver == "5.3" or ver == "5.4" then
                    luainfo.version = ver
                else
                    luainfo.version = "Other"
                end
            else
                luainfo.version = name --[[@as LuaVersion]]
            end
            break
        end
    end

    if not luainfo.interpreter then return nil, "Could not find Lua interpreter" end

    return luainfo, nil
end


---@param lua string
---@return LuaVersion? version, string? err
function export.verify_lua(lua)
    local verstr, err = export.programs[lua] "-v"()
    if not verstr then return nil, err end

    local version = verstr:match("Lua (%d+%.%d+)")
    if not version then
        version = verstr:match("LuaJIT (%d+%.%d+)")
        if not version then version = "Other"
        else version = "JIT" end
    end

    return version, nil
end

---@param dir string
---@param filetype string
---@return string[]? files, string? err
function export.find(dir, filetype)
    local files = {}
    for dirent in lfs.dir(dir) do
        if dirent == "." or dirent == ".." then goto next end
        local relpath = path.join(dir, dirent)

        if path.isfile(relpath) and path.extension(relpath) == filetype then
            table.insert(files, relpath)
        elseif path.isdir(relpath) then
            local subfiles, err = export.find(relpath, filetype)
            if not subfiles then return nil, err end
            for _, file in ipairs(subfiles) do
                table.insert(files, file)
            end
        end

        ::next::
    end

    return files, nil
end

return export
